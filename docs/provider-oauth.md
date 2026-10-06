# Provider OAuth

Orvia supports provider sign-in flows that use OAuth rather than manually pasted credentials.

## Flow

1. Orvia creates a provider-specific authorization request.
2. The system browser opens the provider sign-in page.
3. The provider redirects to Orvia's registered callback.
4. Orvia validates the returned state and exchanges the authorization result when required.
5. Tokens are stored using the app's protected credential storage and are never committed to the repository.

## Requirements

- Use a unique state value for every authorization attempt.
- Accept callbacks only for the expected provider and redirect URI.
- Never log authorization codes, access tokens, refresh tokens, or secrets.
- Handle cancellation and expired sessions cleanly.
- Keep provider-specific endpoints configurable where appropriate.
- Do not prefill user credentials.

## Testing

Tests should cover success, cancellation, state mismatch, malformed callback data, expired sessions, and browser selection.
