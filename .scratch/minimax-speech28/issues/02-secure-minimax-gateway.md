# 02: Secure MiniMax Speech gateway

**What to build:** Let the iOS app request MiniMax upload, voice clone, and speech synthesis through a server-side gateway that hides the MiniMax key and normalizes provider behavior.

**Blocked by:** 01: MiniMax Speech 2.8 provider contract and compliance gate.

**Status:** implemented — server adapter and authorized gateway routes tested; clone policy/deployment remains open

- [x] The gateway uses a server-only `MINIMAX_API_KEY`; no key or authorization header is present in the iOS bundle, client logs, fixtures, or error text.
- [x] Upload, clone, and synthesis operations return stable app-facing identifiers/results without leaking provider response bodies or raw audio into logs.
- [x] Provider authentication failure, invalid audio, limit violation, timeout, rate limit, cancellation, and outage map to stable errors.
- [x] Contract tests use redacted fixtures and cover success, malformed upstream responses, bounded request behavior, and cancellation; no automatic retry is performed.
- [x] The gateway rejects invalid base64, extensions, size, and verified duration ranges before making a provider request.

## Implementation evidence

- Node 24 built-in server gateway files are under `server/`; provider credentials are constructed only in `server/index.mjs` from the server runtime environment.
- Tests use injected fake providers/fetch and never use `.env.local`; gateway tests cover authentication, normalized SSE/audio, upload/clone validation, bounded bodies, cancellation/error shape, and no raw provider payloads.
- The local authenticated smoke test reached both real providers successfully: OpenAI SSE HTTP 200 and MiniMax TTS HTTP 200; output contained no provider key.
