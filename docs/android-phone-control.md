# Android phone control

Orvia exposes selected Android device actions to the tool layer through explicit, permission-aware handlers.

## Supported areas

Typical actions include contacts, calls, messages, calendar access, alarms, notifications, and device information where Android permits them.

## Safety rules

- Request Android runtime permissions only when required.
- Never silently send messages, place calls, delete data, or perform another destructive action.
- Return structured errors when a permission or platform capability is unavailable.
- Keep provider/model text separate from Android implementation details.
- Do not rely on region-specific defaults.

## Testing

Use deterministic English fixtures and mock Android services. Tests should verify permission denial, malformed arguments, unavailable providers, and successful execution paths.
