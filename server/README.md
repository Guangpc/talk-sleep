# SleepMate server gateway

This directory contains server-only provider adapters. The iOS app must never receive provider API keys.

The local gateway exposes these authenticated app-facing routes:

- `POST /v1/llm/chat` — normalized OpenAI-compatible SSE text events.
- `POST /v1/tts/synthesize` — base64 audio response for a selected voice.
- `POST /v1/tts/upload` — consented, bounded base64 audio upload for `voice_clone` or `prompt_audio`.
- `POST /v1/tts/clone` — creates a cloned voice from provider file identifiers.
- `GET /health` — non-sensitive health check.

Run all server tests from this directory with:

```sh
npm test
```

Run the local server from the repository root with:

```sh
node server/index.mjs
```

The server requires `OPENAI_NEXT_API_KEY`, `MINIMAX_API_KEY`, and a separate `SLEEPMATE_GATEWAY_TOKEN`. Runtime secrets are injected through the server environment or a local ignored `.env.local`; provider keys are never sent to the iOS app or committed.
