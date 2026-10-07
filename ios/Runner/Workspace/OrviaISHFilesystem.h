#import <Foundation/Foundation.h>
#include <stdbool.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable per-process mappings. The owner must retain this data while any
/// guest thread group (including forked descendants) holds its bytes pointer.
NSData * _Nullable OrviaISHCreateFilesystem(NSArray<NSDictionary<NSString *, id> *> * _Nonnull binds);
bool OrviaISHTranslatePath(const char *guest, uint64_t context, char *out, size_t size);
bool OrviaISHReversePath(const char *host, uint64_t context, char *out, size_t size);

NS_ASSUME_NONNULL_END
