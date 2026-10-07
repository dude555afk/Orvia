//
//  OrviaISHCrashGuards.h
//  Runner
//
//  Crash containment for the embedded iSH kernel. A guest crash must take
//  down at most the guest task thread, never the whole Flutter app.
//

#ifndef OrviaISHCrashGuards_h
#define OrviaISHCrashGuards_h

/// Install signal handlers that recover from guest JIT faults (SIGSEGV/
/// SIGBUS/SIGILL/SIGTRAP on iSH threads) and re-raise untouched on non-iSH
/// threads. Must be called before any guest code runs.
void OrviaISHInstallCrashGuards(void);

/// Point iSH's die() at a handler that parks the faulting thread instead
/// of abort()ing the entire app process.
void OrviaISHInstallDieGuard(void);

#endif /* OrviaISHCrashGuards_h */
