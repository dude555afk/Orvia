#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// iSH kernel/exec.c limits each argv/envp string block to 32 guest 4 KiB pages.
extern const NSUInteger OrviaISHEnvironmentMaxBytes;

typedef NS_ENUM(NSInteger, OrviaISHEnvironmentError) {
    OrviaISHEnvironmentErrorNone,
    OrviaISHEnvironmentErrorInvalidEntry,
    OrviaISHEnvironmentErrorTooLarge,
};

/// Encodes all UTF-8 NAME=value entries, including their NUL terminators and
/// the final empty entry required by do_execve. Never returns a partial block.
NSData * _Nullable OrviaISHEncodeEnvironment(
    NSDictionary<NSString *, NSString *> *environment,
    OrviaISHEnvironmentError *error);

NSString *OrviaISHEnvironmentErrorMessage(OrviaISHEnvironmentError error);

NS_ASSUME_NONNULL_END
