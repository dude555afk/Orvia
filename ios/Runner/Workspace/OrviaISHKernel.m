//
//  OrviaISHKernel.m
//  Runner
//
//  Boot sequence adapted from Cuplivo/OpenMinis ISHKernel.m (GPL-3.0, see
//  ios/sandbox/NOTICE). Overlay files are written through the guest VFS so
//  meta.db stays in sync — never write host-side into the fakefs data/ tree.
//

#import "OrviaISHKernel.h"
#import "OrviaISHCrashGuards.h"
#import "OrviaISHExecutor.h"
#import "OrviaISHEnvironment.h"
#import "OrviaISHFilesystem.h"
#import "OrviaISHCompat.h"

@import SystemConfiguration;

#include "ish/kernel/init.h"
#include "ish/kernel/task.h"
#include "ish/kernel/calls.h"
#include "ish/kernel/fs.h"
#include "ish/fs/fake.h"
#include "ish/fs/tty.h"
#include "ish/fs/dev.h"
#include "ish/fs/devices.h"
#include "ish/fs/path.h"
#include "ish/fs/fd.h"
#include "ish/fs/stat.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syslimits.h>
#include <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR
#include <sys/un.h>
#endif

NSNotificationName const OrviaISHProcessExitedNotification = @"OrviaISHProcessExited";

static NSString *const kDnsSubdir = @"OrviaWorkspace/dns";
static const char *kPublicDns[] = {"1.1.1.1", "8.8.8.8", "223.5.5.5"};

extern void (*exit_hook)(struct task *task, int code);

#if !TARGET_OS_SIMULATOR
extern const char *sock_tmp_prefix;
#endif

#pragma mark - Console TTY (init stdio; output discarded)

static int orvia_console_write(struct tty *tty, const void *buf, size_t len, bool blocking) {
    (void)tty;
    (void)buf;
    (void)blocking;
    return (int)len;
}

static int orvia_console_init(struct tty *tty) {
    (void)tty;
    return 0;
}

static void orvia_console_cleanup(struct tty *tty) {
    (void)tty;
}

static struct tty_driver_ops orvia_console_ops = {
    .init = orvia_console_init,
    .write = orvia_console_write,
    .cleanup = orvia_console_cleanup,
};

DEFINE_TTY_DRIVER(orvia_console_driver, &orvia_console_ops, TTY_CONSOLE_MAJOR, 8);

#pragma mark - PTY driver

static int orvia_pty_write(struct tty *tty, const void *buf, size_t len, bool blocking);
static int orvia_pty_init(struct tty *tty) {
    (void)tty;
    return 0;
}
static void orvia_pty_cleanup(struct tty *tty) {
    (void)tty;
}

static struct tty_driver_ops orvia_pty_ops = {
    .init = orvia_pty_init,
    .write = orvia_pty_write,
    .cleanup = orvia_pty_cleanup,
};

static struct tty_driver orvia_pty_driver = {.ops = &orvia_pty_ops};

static bool orvia_reverse_context_path(const char *host, char *out, size_t size) {
    uint64_t context = current && current->group ? current->group->fs_context : 0;
    return OrviaISHReversePath(host, context, out, size);
}

#pragma mark - Session / bind state

@interface OrviaISHPtySession : NSObject
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic) int pid;
@property (nonatomic) pid_t_ pgid;
@property (nonatomic) struct tty *tty;
@property (nonatomic, strong) NSMutableArray<NSData *> *pendingOutput;
@property (nonatomic, strong) NSMutableData *pendingTail;
@property (nonatomic, strong) dispatch_source_t outputTimer;
@property (nonatomic) BOOL outputScheduled;
@property (nonatomic) BOOL outputImmediate;
@property (nonatomic) BOOL hasDeliveredOutput;
@end

@implementation OrviaISHPtySession
@end

@interface OrviaISHKernel ()
- (void)noteGuestExitWithPid:(int)pid code:(int)code;
- (void)queuePtyBytes:(const void *)bytes length:(size_t)length ttyNum:(int)ttyNum;
- (void)flushPtyOutput:(OrviaISHPtySession *)session;
@end

/// iSH `do_exit` passes the Linux wait(2) status (exit << 8, or signal in the
/// low 7 bits). Flutter / the workspace channel expect a process exit code.
static int orvia_decode_wait_status(int status) {
    if (status < 0) return status;
    if ((status & 0x7f) == 0) {
        return (status >> 8) & 0xff;
    }
    return 128 + (status & 0x7f);
}

static void orvia_handle_process_exit(struct task *task, int code) {
    if (task->parent != NULL && task->parent->parent != NULL)
        return;
    pid_t pid = task->pid;
    int decoded = orvia_decode_wait_status(code);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:OrviaISHProcessExitedNotification
                          object:nil
                        userInfo:@{@"pid": @(pid), @"code": @(decoded)}];
        [[OrviaISHKernel shared] noteGuestExitWithPid:pid code:decoded];
    });
}

static int orvia_pty_write(struct tty *tty, const void *buf, size_t len, bool blocking) {
    (void)blocking;
    if (len == 0) return 0;
    @autoreleasepool {
        [[OrviaISHKernel shared] queuePtyBytes:buf length:len ttyNum:tty->num];
    }
    return (int)len;
}

@implementation OrviaISHKernel {
    BOOL _isBooted;
    NSString *_rootPath;
    NSString *_dataPath;
    NSString *_dnsHostPath;
    SCNetworkReachabilityRef _dnsReachability;
    dispatch_queue_t _spawnQueue;
    NSMutableDictionary<NSString *, NSString *> *_activeBinds;
    NSMutableDictionary<NSString *, NSNumber *> *_readOnlyBinds;
    NSMutableDictionary<NSString *, OrviaISHPtySession *> *_ptyBySession;
    NSMutableDictionary<NSNumber *, OrviaISHPtySession *> *_ptyByPid;
    NSMutableDictionary<NSNumber *, OrviaISHPtySession *> *_ptyByTtyNum;
    NSLock *_ptyLock;
    NSMutableSet<NSData *> *_filesystems;
}

- (void)dealloc {
    if (_dnsReachability != NULL) {
        SCNetworkReachabilitySetDispatchQueue(_dnsReachability, NULL);
        CFRelease(_dnsReachability);
    }
}

+ (instancetype)shared {
    static OrviaISHKernel *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OrviaISHKernel alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isBooted = NO;
        _filesystems = [NSMutableSet set];
        _spawnQueue = dispatch_queue_create("com.dude555afk.orvia.workspace.ish.spawn", DISPATCH_QUEUE_SERIAL);
        _activeBinds = [NSMutableDictionary dictionary];
        _readOnlyBinds = [NSMutableDictionary dictionary];
        _ptyBySession = [NSMutableDictionary dictionary];
        _ptyByPid = [NSMutableDictionary dictionary];
        _ptyByTtyNum = [NSMutableDictionary dictionary];
        _ptyLock = [[NSLock alloc] init];
    }
    return self;
}

- (BOOL)isBooted {
    return _isBooted;
}

- (NSString *)bootRootPath {
    return _rootPath;
}

- (void)performOnSpawnQueue:(void (^)(void))block {
    dispatch_sync(_spawnQueue, block);
}

#pragma mark - Boot

- (int)bootWithRootPath:(NSString *)rootPath {
    if (_isBooted) {
        NSLog(@"OrviaISHKernel: already booted");
        return 0;
    }

    int err;
    OrviaISHInstallCrashGuards();
    OrviaISHInstallDieGuard();

    _rootPath = rootPath;
    _dataPath = [rootPath stringByAppendingPathComponent:@"data"];
    err = mount_root(&fakefs, _dataPath.fileSystemRepresentation);
    if (err < 0) {
        NSLog(@"OrviaISHKernel: mount_root failed: %d", err);
        _rootPath = nil;
        _dataPath = nil;
        return err;
    }

    char canonical_data_path[PATH_MAX];
    if (realpath(_dataPath.fileSystemRepresentation, canonical_data_path) != NULL) {
        fakefs_set_rootfs_data_path(canonical_data_path);
    } else {
        NSLog(@"OrviaISHKernel: realpath(data) failed (errno=%d)", errno);
    }

    err = become_first_process();
    if (err < 0) {
        NSLog(@"OrviaISHKernel: become_first_process failed: %d", err);
        return err;
    }
    current->thread = pthread_self();

    [self createDeviceNodes];
    [self applyRootfsPatchBundle];
    [self applyBundleOverlay];
    [self ensureGuestDirs:@[@"/workspace", @"/chat", @"/skills", @"/mounts"]];

    do_mount(&procfs, "proc", "/proc", "", 0);
    do_mount(&devptsfs, "devpts", "/dev/pts", "", 0);

    [self mountDnsConfig];
    [self setUpUnixSocketPrefix];

    fakefs_set_path_translate_hook(OrviaISHTranslatePath);
    fakefs_set_path_reverse_hook(orvia_reverse_context_path);
    exit_hook = orvia_handle_process_exit;

    tty_drivers[TTY_CONSOLE_MAJOR] = &orvia_console_driver;
    set_console_device(TTY_CONSOLE_MAJOR, 1);
    err = create_stdio("/dev/console", TTY_CONSOLE_MAJOR, 1);
    if (err < 0) {
        NSLog(@"OrviaISHKernel: create_stdio failed: %d (non-fatal)", err);
    }

    _isBooted = YES;
    NSLog(@"OrviaISHKernel: kernel initialized");
    return 0;
}

- (void)createDeviceNodes {
    generic_mkdirat(AT_PWD, "/dev", 0755);
    generic_mkdirat(AT_PWD, "/dev/pts", 0755);

    generic_mknodat(AT_PWD, "/dev/tty1", S_IFCHR | 0666, dev_make(TTY_CONSOLE_MAJOR, 1));
    generic_mknodat(AT_PWD, "/dev/tty", S_IFCHR | 0666, dev_make(TTY_ALTERNATE_MAJOR, DEV_TTY_MINOR));
    generic_mknodat(AT_PWD, "/dev/console", S_IFCHR | 0666, dev_make(TTY_ALTERNATE_MAJOR, DEV_CONSOLE_MINOR));
    generic_mknodat(AT_PWD, "/dev/ptmx", S_IFCHR | 0666, dev_make(TTY_ALTERNATE_MAJOR, DEV_PTMX_MINOR));

    generic_mknodat(AT_PWD, "/dev/null", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_NULL_MINOR));
    generic_mknodat(AT_PWD, "/dev/zero", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_ZERO_MINOR));
    generic_mknodat(AT_PWD, "/dev/full", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_FULL_MINOR));
    generic_mknodat(AT_PWD, "/dev/random", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_RANDOM_MINOR));
    generic_mknodat(AT_PWD, "/dev/urandom", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_URANDOM_MINOR));
}

- (void)ensureGuestDirs:(NSArray<NSString *> *)dirs {
    for (NSString *dir in dirs) {
        generic_mkdirat(AT_PWD, dir.fileSystemRepresentation, 0755);
    }
}

/// Apply iSH's Node compatibility scripts on every cold boot, including to
/// existing environments. Use the guest VFS so fakefs metadata stays in sync.
/// No installed-version marker: a failed write is retried on the next boot.
- (void)applyRootfsPatchBundle {
    NSURL *bundleURL = [[NSBundle mainBundle] URLForResource:@"RootfsPatch" withExtension:@"bundle"];
    NSDictionary *manifest = bundleURL == nil ? nil :
        [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"manifest.plist"]];
    if (manifest == nil) {
        NSLog(@"OrviaISHKernel: RootfsPatch manifest missing from bundle");
        return;
    }
    for (NSDictionary *entry in manifest[@"files"]) {
        [self writeGuestFile:entry[@"dst"]
                fromHostURL:[bundleURL URLByAppendingPathComponent:entry[@"src"]]];
    }
}

/// Write each file from the bundled `overlay/` folder through the guest VFS.
- (void)applyBundleOverlay {
    NSURL *overlayURL = [[NSBundle mainBundle] URLForResource:@"overlay" withExtension:nil];
    if (overlayURL == nil) {
        NSLog(@"OrviaISHKernel: overlay folder missing from bundle");
        return;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtURL:overlayURL
                         includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                            options:0
                                       errorHandler:nil];
    NSString *base = overlayURL.URLByStandardizingPath.path;
    for (NSURL *fileURL in en) {
        NSNumber *isFile = nil;
        [fileURL getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isFile.boolValue) continue;

        NSString *rel = [fileURL.URLByStandardizingPath.path substringFromIndex:base.length];
        if (![rel hasPrefix:@"/"]) rel = [@"/" stringByAppendingString:rel];
        [self writeGuestFile:rel fromHostURL:fileURL];
    }
}

- (void)ensureGuestParentDirs:(NSString *)guestPath {
    NSArray<NSString *> *parts = [guestPath componentsSeparatedByString:@"/"];
    NSMutableString *acc = [NSMutableString string];
    for (NSUInteger i = 0; i < parts.count - 1; i++) {
        NSString *part = parts[i];
        if (part.length == 0) continue;
        [acc appendFormat:@"/%@", part];
        generic_mkdirat(AT_PWD, acc.fileSystemRepresentation, 0755);
    }
}

- (void)writeGuestFile:(NSString *)guestPath fromHostURL:(NSURL *)hostURL {
    NSData *contents = [NSData dataWithContentsOfURL:hostURL];
    if (contents == nil) {
        NSLog(@"OrviaISHKernel: overlay read failed: %@", hostURL.path);
        return;
    }
    [self ensureGuestParentDirs:guestPath];

    BOOL isBin = [guestPath containsString:@"/bin/"] || [guestPath containsString:@"/sbin/"];
    int mode = isBin ? 0755 : 0644;
    struct fd *fd = generic_open(guestPath.fileSystemRepresentation,
                                 O_WRONLY_ | O_CREAT_ | O_TRUNC_, mode);
    if (IS_ERR(fd)) {
        NSLog(@"OrviaISHKernel: overlay open %@ failed: %ld", guestPath, PTR_ERR(fd));
        return;
    }
    const char *bytes = contents.bytes;
    size_t offset = 0;
    while (offset < contents.length) {
        ssize_t written = fd->ops->write(fd, bytes + offset, contents.length - offset);
        if (written <= 0) {
            NSLog(@"OrviaISHKernel: overlay write %@ failed: %zd", guestPath, written);
            break;
        }
        offset += (size_t)written;
    }
    fd_close(fd);
}

#pragma mark - DNS

- (void)mountDnsConfig {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dnsDir = [library stringByAppendingPathComponent:kDnsSubdir];
    _dnsHostPath = [dnsDir stringByAppendingPathComponent:@"resolv.conf"];

    if (![fm fileExistsAtPath:dnsDir]) {
        [fm createDirectoryAtPath:dnsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [self refreshDnsConfig];

    int err = fakefs_bind_mount("/etc/resolv.conf", _dnsHostPath.fileSystemRepresentation, false);
    if (err < 0) {
        NSLog(@"OrviaISHKernel: DNS bind mount failed (%d) — writing through VFS", err);
        struct task *prev = current;
        current = pid_get_task(1);
        if (current) {
            NSString *seed = [self dnsContentString];
            struct fd *fd = generic_open("/etc/resolv.conf", O_WRONLY_ | O_CREAT_ | O_TRUNC_, 0666);
            if (!IS_ERR(fd)) {
                fd->ops->write(fd, seed.UTF8String, [seed lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
                fd_close(fd);
            }
        }
        current = prev;
        return;
    }
    [self startDnsWatcher];
}

- (NSString *)dnsContentString {
    NSMutableArray<NSString *> *servers = [NSMutableArray array];
    void (^addServer)(NSString *) = ^(NSString *raw) {
        NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length == 0 || [servers containsObject:s]) return;
        [servers addObject:s];
    };

    FILE *resolv = fopen("/etc/resolv.conf", "r");
    if (resolv != NULL) {
        char line[512];
        while (fgets(line, sizeof(line), resolv) != NULL) {
            char ns[256];
            if (sscanf(line, "nameserver %255s", ns) == 1) {
                NSString *server = [NSString stringWithUTF8String:ns];
                if ([self isUsableDnsServer:server]) addServer(server);
            }
        }
        fclose(resolv);
    }

    for (size_t i = 0; i < sizeof(kPublicDns) / sizeof(kPublicDns[0]); i++) {
        addServer([NSString stringWithUTF8String:kPublicDns[i]]);
    }

    NSMutableString *content = [NSMutableString string];
    for (NSString *server in servers) {
        [content appendFormat:@"nameserver %@\n", server];
    }
    return content;
}

- (BOOL)isUsableDnsServer:(NSString *)server {
    struct in_addr addr4;
    if (inet_pton(AF_INET, server.UTF8String, &addr4) == 1) {
        const uint8_t *bytes = (const uint8_t *)&addr4;
        return bytes[0] != 127;
    }
    struct in6_addr addr6;
    if (inet_pton(AF_INET6, server.UTF8String, &addr6) == 1) {
        return memcmp(&addr6, &in6addr_loopback, sizeof(addr6)) != 0;
    }
    return NO;
}

- (void)refreshDnsConfig {
    if (_dnsHostPath == nil) return;
    NSString *content = [self dnsContentString];
    NSError *error = nil;
    if (![content writeToFile:_dnsHostPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"OrviaISHKernel: DNS refresh write failed: %@", error);
    }
}

static void OrviaDnsReachabilityChanged(SCNetworkReachabilityRef target,
                                         SCNetworkReachabilityFlags flags,
                                         void *info) {
    (void)target;
    (void)flags;
    @autoreleasepool {
        OrviaISHKernel *kernel = (__bridge OrviaISHKernel *)info;
        dispatch_async(dispatch_get_main_queue(), ^{
            [kernel refreshDnsConfig];
        });
    }
}

- (void)startDnsWatcher {
    if (_dnsReachability != NULL) return;
    SCNetworkReachabilityRef reachability =
        SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, "1.1.1.1");
    if (reachability == NULL) return;
    SCNetworkReachabilityContext context = {
        .version = 0, .info = (__bridge void *)self,
        .retain = NULL, .release = NULL, .copyDescription = NULL};
    if (!SCNetworkReachabilitySetCallback(reachability, OrviaDnsReachabilityChanged, &context) ||
        !SCNetworkReachabilitySetDispatchQueue(reachability, dispatch_get_main_queue())) {
        CFRelease(reachability);
        return;
    }
    _dnsReachability = reachability;
}

- (void)setUpUnixSocketPrefix {
#if TARGET_OS_SIMULATOR
    (void)0;
#else
    NSString *tempDir = NSTemporaryDirectory();
    if ([tempDir hasPrefix:@"/private/"]) {
        tempDir = [tempDir substringFromIndex:strlen("/private")];
    }
    NSString *prefix = [tempDir stringByAppendingString:@"ishsock"];
    if (prefix.UTF8String == NULL) return;
    const size_t kSunPathMax = sizeof(((struct sockaddr_un *)0)->sun_path);
    const size_t kSuffixWorstCase = 12;
    size_t prefixLen = strlen(prefix.UTF8String);
    if (prefixLen + kSuffixWorstCase >= kSunPathMax) {
        NSLog(@"OrviaISHKernel: unix socket prefix too long — keeping default");
        return;
    }
    sock_tmp_prefix = strdup(prefix.UTF8String);
#endif
}

#pragma mark - Bind mounts

- (int)bindMountPath:(NSString *)linuxPath toHostPath:(NSString *)hostPath readOnly:(BOOL)readOnly {
    if (!_isBooted) return -1;
    // fakefs_bind_mount recursively removes its destination before binding.
    // Only replace an empty placeholder or an existing mount symlink.
    int targetError = OrviaISHValidateMountTarget(_dataPath, linuxPath);
    if (targetError < 0) return targetError;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:hostPath isDirectory:&isDir]) {
        if ([linuxPath hasPrefix:@"/mounts/"]) return -ENOENT;
        NSError *error = nil;
        if (![fm createDirectoryAtPath:hostPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"OrviaISHKernel: host mkdir %@ failed: %@", hostPath, error);
            return -1;
        }
    }
    struct task *prev = current;
    current = pid_get_task(1);
    [self ensureGuestParentDirs:linuxPath];
    generic_mkdirat(AT_PWD, linuxPath.fileSystemRepresentation, 0755);
    current = prev;

    int err = fakefs_bind_mount(linuxPath.fileSystemRepresentation,
                                hostPath.fileSystemRepresentation, readOnly);
    if (err < 0) {
        NSLog(@"OrviaISHKernel: bindMount %@ -> %@ failed: %d", linuxPath, hostPath, err);
        return err;
    }
    _activeBinds[linuxPath] = hostPath;
    _readOnlyBinds[linuxPath] = @(readOnly);
    return 0;
}

- (int)bindUnmountPath:(NSString *)linuxPath {
    if (!_isBooted) return -1;
    int err = fakefs_bind_unmount(linuxPath.fileSystemRepresentation);
    [_activeBinds removeObjectForKey:linuxPath];
    [_readOnlyBinds removeObjectForKey:linuxPath];
    if (err == 0 && [linuxPath hasPrefix:@"/mounts/"]) {
        struct task *prev = current;
        current = pid_get_task(1);
        generic_rmdirat(AT_PWD, linuxPath.fileSystemRepresentation);
        current = prev;
    }
    return err;
}

- (uint64_t)filesystemContextForBinds:(NSArray<NSDictionary<NSString *, id> *> *)binds {
    NSData *data = OrviaISHCreateFilesystem(binds);
    if (!data) return 0;
    // Fork copies fs_context. Reclaim only contexts absent from the entire task
    // table, rather than freeing a shell's mapping while its children still run.
    NSMutableSet<NSNumber *> *live = [NSMutableSet set];
    lock(&pids_lock);
    for (int pid = 1; pid < MAX_PID; pid++) {
        struct task *task = pid_get_task(pid);
        if (task && !task->exiting && task->group) [live addObject:@(task->group->fs_context)];
    }
    unlock(&pids_lock);
    for (NSData *old in [_filesystems copy]) {
        if (![live containsObject:@((uint64_t)(uintptr_t)old.bytes)]) [_filesystems removeObject:old];
    }
    NSData *existing = [_filesystems member:data];
    if (existing) data = existing;
    else [_filesystems addObject:data];
    return (uint64_t)(uintptr_t)data.bytes;
}

- (int)reconcileBinds:(NSArray<NSDictionary<NSString *, id> *> *)binds {
    if (!_isBooted) return -1;
    for (NSDictionary<NSString *, id> *bind in binds) {
        NSString *host = bind[@"host"];
        NSString *guest = bind[@"guest"];
        if (host.length == 0 || guest.length == 0) continue;
        NSString *currentHost = _activeBinds[guest];
        BOOL readOnly = [bind[@"readOnly"] boolValue];
        if ([currentHost isEqualToString:host] && [_readOnlyBinds[guest] boolValue] == readOnly) continue;
        if (currentHost != nil) {
            [self bindUnmountPath:guest];
        }
        int err = [self bindMountPath:guest toHostPath:host readOnly:readOnly];
        if (err < 0) return err;
    }
    return 0;
}

- (int)reconcileExternalBinds:(NSArray<NSDictionary<NSString *, id> *> *)binds {
    if (!_isBooted) return 0;
    // Check the whole snapshot before removing any existing bindings.
    for (NSDictionary<NSString *, id> *bind in binds) {
        int err = OrviaISHValidateMountTarget(_dataPath, bind[@"guest"]);
        if (err < 0) return err;
    }
    NSSet *desired = [NSSet setWithArray:[binds valueForKey:@"guest"]];
    for (NSString *guest in [_activeBinds.allKeys copy]) {
        if ([guest hasPrefix:@"/mounts/"] && ![desired containsObject:guest]) {
            int err = [self bindUnmountPath:guest];
            if (err < 0) return err;
        }
    }
    return [self reconcileBinds:binds];
}

- (void)ptyCloseAll {
    [_ptyLock lock];
    NSArray *sessions = [_ptyBySession.allKeys copy];
    [_ptyLock unlock];
    for (NSString *session in sessions) [self ptyCloseSession:session];
}

#pragma mark - PTY

- (BOOL)guestFileExists:(const char *)path {
    struct fd *fd = generic_open(path, O_RDONLY_, 0);
    if (IS_ERR(fd)) return NO;
    fd_close(fd);
    return YES;
}

- (int)ptyOpenSession:(NSString *)sessionId
                binds:(NSArray<NSDictionary<NSString *, id> *> *)binds
                  cwd:(NSString *)cwd
                  env:(NSDictionary<NSString *, NSString *> *)env
                 cols:(int)cols
                 rows:(int)rows {
    if (!_isBooted) return OrviaISHPtyOpenErrorNotBooted;
    if (sessionId.length == 0) return OrviaISHPtyOpenErrorBadSessionId;

    [_ptyLock lock];
    BOOL exists = _ptyBySession[sessionId] != nil;
    [_ptyLock unlock];
    if (exists) {
        NSLog(@"OrviaISHKernel: pty session %@ is already open", sessionId);
        return OrviaISHPtyOpenErrorSessionExists;
    }

    NSMutableDictionary<NSString *, NSString *> *merged = [@{
        @"TERM": @"xterm-256color",
        @"HOME": @"/root",
        @"PATH": @"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        @"LANG": @"C.UTF-8",
        @"PS1": @"\\u@orvia:\\w\\$ ",
    } mutableCopy];
    if (env) [merged addEntriesFromDictionary:env];
    OrviaISHEnvironmentError environmentError;
    NSData *environmentData = OrviaISHEncodeEnvironment(merged, &environmentError);
    if (environmentData == nil) {
        return environmentError == OrviaISHEnvironmentErrorTooLarge
            ? OrviaISHPtyOpenErrorEnvironmentTooLarge
            : OrviaISHPtyOpenErrorInvalidEnvironment;
    }

    __block int resultPid = -1;
    [self performOnSpawnQueue:^{
        struct task *saved = current;
        @try {
            uint64_t filesystem = [self filesystemContextForBinds:binds];
            if (!filesystem) { resultPid = -EINVAL; return; }
            int err = become_new_init_child();
            if (err < 0) {
                resultPid = err;
                return;
            }

            current->group->fs_context = filesystem;
            struct tty *tty = pty_open_fake(&orvia_pty_driver);
            if (IS_ERR(tty)) {
                resultPid = (int)PTR_ERR(tty);
                return;
            }
            struct winsize_ winsize = {
                .row = rows > 0 ? rows : 24,
                .col = cols > 0 ? cols : 80,
                .xpixel = 0,
                .ypixel = 0,
            };
            tty_set_winsize(tty, winsize);

            NSString *stdioFile = [NSString stringWithFormat:@"/dev/pts/%d", tty->num];
            err = create_stdio(stdioFile.fileSystemRepresentation, TTY_PSEUDO_SLAVE_MAJOR, tty->num);
            if (err < 0) {
                resultPid = err;
                return;
            }

            if (cwd.length > 0) {
                struct statbuf st;
                int statErr = generic_statat(AT_PWD, cwd.UTF8String, &st, true);
                if (statErr >= 0 && (st.mode & S_IFDIR)) {
                    struct fd *dir = generic_open(cwd.UTF8String, O_RDONLY_, 0);
                    if (!IS_ERR(dir)) {
                        fs_chdir(current->fs, dir);
                    }
                }
            }

            BOOL useBash = [self guestFileExists:"/bin/bash"];
            const char *execPath = useBash ? "/bin/bash" : "/bin/sh";
            NSArray<NSString *> *argvArray = useBash ? @[ @"/bin/bash", @"-l" ] : @[ @"/bin/sh", @"-l" ];
            char argv_buf[4096];
            size_t pos = 0;
            int argc = 0;
            for (NSString *arg in argvArray) {
                const char *s = arg.UTF8String;
                size_t len = strlen(s) + 1;
                if (pos + len >= sizeof(argv_buf) - 1) break;
                memcpy(argv_buf + pos, s, len);
                pos += len;
                argc++;
            }
            argv_buf[pos] = '\0';

            err = do_execve(execPath, argc, argv_buf, environmentData.bytes);
            if (err < 0) {
                resultPid = err;
                return;
            }

            OrviaISHPtySession *session = [[OrviaISHPtySession alloc] init];
            session.sessionId = sessionId;
            session.pid = current->pid;
            session.pgid = current->group->pgid;
            session.tty = tty;
            session.pendingOutput = [NSMutableArray array];
            session.outputTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            __weak OrviaISHPtySession *outputSession = session;
            dispatch_source_set_timer(session.outputTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
            dispatch_source_set_event_handler(session.outputTimer, ^{
                OrviaISHPtySession *active = outputSession;
                if (active) [self flushPtyOutput:active];
            });
            dispatch_resume(session.outputTimer);
            [_ptyLock lock];
            self->_ptyBySession[sessionId] = session;
            self->_ptyByPid[@(session.pid)] = session;
            self->_ptyByTtyNum[@(tty->num)] = session;
            [_ptyLock unlock];

            resultPid = current->pid;
            task_start(current);
        } @finally {
            current = saved;
        }
    }];
    return resultPid;
}

- (void)ptyWriteSession:(NSString *)sessionId data:(NSData *)data {
    [_ptyLock lock];
    OrviaISHPtySession *session = _ptyBySession[sessionId];
    struct tty *tty = session.tty;
    [_ptyLock unlock];
    if (tty && data.length > 0) {
        tty_input(tty, data.bytes, data.length, false);
    }
}

- (void)ptyResizeSession:(NSString *)sessionId cols:(int)cols rows:(int)rows {
    [_ptyLock lock];
    OrviaISHPtySession *session = _ptyBySession[sessionId];
    struct tty *tty = session.tty;
    [_ptyLock unlock];
    if (!tty) return;
    struct winsize_ winsize = {.row = rows, .col = cols, .xpixel = 0, .ypixel = 0};
    tty_set_winsize(tty, winsize);
}

- (void)ptyCloseSession:(NSString *)sessionId {
    [_ptyLock lock];
    OrviaISHPtySession *session = _ptyBySession[sessionId];
    [_ptyLock unlock];
    if (!session) return;
    [OrviaISHExecutor killGuestPid:session.pid groupId:session.pgid];
}

// The guest can write one character at a time (including terminal echo).
// Copy into bounded packets before posting to the main queue, and preserve
// every byte. The first packet is immediate; subsequent bursts wait <=16 ms.
- (void)queuePtyBytes:(const void *)bytes length:(size_t)length ttyNum:(int)ttyNum {
    static const NSUInteger packetBytes = 64 * 1024;
    [_ptyLock lock];
    OrviaISHPtySession *session = _ptyByTtyNum[@(ttyNum)];
    if (!session) { [_ptyLock unlock]; return; }
    const uint8_t *cursor = bytes;
    while (length > 0) {
        if (!session.pendingTail) {
            session.pendingTail = [NSMutableData dataWithCapacity:packetBytes];
        }
        NSUInteger count = MIN(length, packetBytes - session.pendingTail.length);
        [session.pendingTail appendBytes:cursor length:count];
        cursor += count;
        length -= count;
        if (session.pendingTail.length == packetBytes) {
            [session.pendingOutput addObject:session.pendingTail];
            session.pendingTail = nil;
        }
    }
    BOOL immediate = !session.hasDeliveredOutput || session.pendingOutput.count > 0;
    if (!session.outputScheduled || (immediate && !session.outputImmediate)) {
        session.outputScheduled = YES;
        session.outputImmediate = immediate;
        dispatch_source_set_timer(session.outputTimer,
            dispatch_time(DISPATCH_TIME_NOW, immediate ? 0 : 16 * NSEC_PER_MSEC),
            DISPATCH_TIME_FOREVER, 0);
    }
    [_ptyLock unlock];
}

// Only called with _ptyLock held. Detached buffers are never mutated again.
static NSArray<NSData *> *orvia_take_pty_output(OrviaISHPtySession *session) {
    NSMutableArray<NSData *> *packets = session.pendingOutput;
    if (session.pendingTail.length > 0) [packets addObject:session.pendingTail];
    session.pendingOutput = [NSMutableArray array];
    session.pendingTail = nil;
    session.outputScheduled = NO;
    session.outputImmediate = NO;
    session.hasDeliveredOutput = YES;
    return packets;
}

- (void)flushPtyOutput:(OrviaISHPtySession *)session {
    [_ptyLock lock];
    // A cancelled timer can already be queued. Never deliver into a reopened
    // session, even if its string ID or guest TTY number has been reused.
    if (_ptyBySession[session.sessionId] != session) { [_ptyLock unlock]; return; }
    dispatch_source_set_timer(session.outputTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
    NSArray<NSData *> *packets = orvia_take_pty_output(session);
    NSString *sessionId = session.sessionId;
    OrviaISHPtyDataHandler handler = self.ptyDataHandler;
    [_ptyLock unlock];
    if (sessionId && handler) {
        for (NSData *packet in packets) handler(sessionId, packet);
    }
}

- (void)noteGuestExitWithPid:(int)pid code:(int)code {
    [_ptyLock lock];
    OrviaISHPtySession *session = _ptyByPid[@(pid)];
    NSArray<NSData *> *packets = nil;
    if (session) {
        dispatch_source_cancel(session.outputTimer);
        session.outputTimer = nil;
        packets = orvia_take_pty_output(session);
        [_ptyBySession removeObjectForKey:session.sessionId];
        [_ptyByPid removeObjectForKey:@(pid)];
        if (session.tty) {
            [_ptyByTtyNum removeObjectForKey:@(session.tty->num)];
        }
    }
    NSString *sessionId = session.sessionId;
    OrviaISHPtyExitHandler handler = self.ptyExitHandler;
    OrviaISHPtyDataHandler dataHandler = self.ptyDataHandler;
    [_ptyLock unlock];
    // Flush before exit so ChannelPtySession cannot close ahead of its tail.
    if (sessionId && dataHandler) {
        for (NSData *packet in packets) dataHandler(sessionId, packet);
    }
    if (sessionId && handler) {
        handler(sessionId, code);
    }
}

@end
