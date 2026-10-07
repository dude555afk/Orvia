# AI streaming

Orvia streams model output incrementally so the interface can render text, reasoning indicators, tool calls, and usage updates without waiting for a complete response.

## Expectations

- Preserve token order and message boundaries.
- Keep partial text responsive without rebuilding the whole conversation on every chunk.
- Surface tool-call state separately from assistant text.
- Treat cancellation as a normal terminal state.
- Do not expose hidden provider payloads or credentials in logs.

## Testing

Streaming tests should cover long responses, concurrent conversations, cancellation, malformed chunks, tool calls, and reconnect/retry behavior. Performance tests should use plain English sample text so they remain locale-independent.
