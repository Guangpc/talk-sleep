# 02: Secure server-side LLM gateway

**What to build:** Give the iOS app a server-side gateway that accepts a normalized conversation request and returns a normalized LLM reply without exposing the provider key or provider-specific details to the device.

**Blocked by:** 01: OpenAI-compatible LLM provider contract and compliance gate.

**Status:** implemented — server adapter and gateway seam tested; production deployment/auth policy remains open

- [x] The gateway authenticates the app-side request and calls the verified provider endpoint using a server-only `OPENAI_NEXT_API_KEY`.
- [x] Provider success, rate limit, timeout, invalid request, authentication failure, and upstream outage map to stable app-facing errors.
- [x] Logs and diagnostics redact API keys, authorization headers, full prompts, transcripts, and provider response bodies by default.
- [x] Contract tests cover successful text, streaming termination, cancellation, malformed upstream data, and normalized errors without real credentials.
- [x] The gateway has bounded request size, timeout, and cancellation behavior; it performs no automatic retry, so a cancelled user turn is never retried.

## Implementation evidence

- Node 24 built-in server gateway files are under `server/`; provider credentials are constructed only in `server/index.mjs` from the server runtime environment.
- Tests use injected fake providers/fetch and never use `.env.local`; gateway tests cover authentication, normalized SSE/audio, upload/clone validation, bounded bodies, cancellation/error shape, and no raw provider payloads.
- The local authenticated smoke test reached both real providers successfully: OpenAI SSE HTTP 200 and MiniMax TTS HTTP 200; output contained no provider key.
