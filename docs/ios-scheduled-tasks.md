# iOS scheduled tasks

Orvia can schedule eligible background work using the APIs available on iOS. Execution time is ultimately controlled by the operating system and is not guaranteed to be exact.

## Guidelines

- Persist the task definition before requesting a schedule.
- Validate timestamps and recurrence rules before saving.
- Keep user-visible status clear when iOS may defer execution.
- Avoid promising exact background execution times.
- Make destructive or externally visible actions require the same confirmation rules used in foreground sessions.

## Testing

Cover create, update, cancel, expired tasks, invalid schedules, app relaunch, and system-denied background execution.
