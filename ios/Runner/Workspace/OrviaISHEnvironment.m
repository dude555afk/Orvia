#import "OrviaISHEnvironment.h"

#include <string.h>

const NSUInteger OrviaISHEnvironmentMaxBytes = 128 * 1024;

NSData *OrviaISHEncodeEnvironment(NSDictionary<NSString *, NSString *> *environment,
                                 OrviaISHEnvironmentError *error) {
    *error = OrviaISHEnvironmentErrorNone;
    NSMutableData *block = [NSMutableData data];
    const char nul = '\0';
    for (NSString *key in environment) {
        if (key.length == 0 || [key containsString:@"="]) {
            *error = OrviaISHEnvironmentErrorInvalidEntry;
            return nil;
        }
        NSString *entry = [NSString stringWithFormat:@"%@=%@", key, environment[key]];
        NSData *bytes = [entry dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
        if (bytes == nil || memchr(bytes.bytes, '\0', bytes.length) != NULL) {
            *error = OrviaISHEnvironmentErrorInvalidEntry;
            return nil;
        }
        // Reserve both this entry's terminator and the final empty entry.
        if (block.length + 2 > OrviaISHEnvironmentMaxBytes ||
            bytes.length > OrviaISHEnvironmentMaxBytes - block.length - 2) {
            *error = OrviaISHEnvironmentErrorTooLarge;
            return nil;
        }
        [block appendData:bytes];
        [block appendBytes:&nul length:1];
    }
    [block appendBytes:&nul length:1];
    return block;
}

NSString *OrviaISHEnvironmentErrorMessage(OrviaISHEnvironmentError error) {
    if (error == OrviaISHEnvironmentErrorTooLarge) {
        return @"Environment variables exceed the iOS sandbox limit of 128 KiB (UTF-8). Reduce their total size and try again.";
    }
    return @"Invalid environment variable name or value.";
}
