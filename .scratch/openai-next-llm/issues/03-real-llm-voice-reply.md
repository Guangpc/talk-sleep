# 03: Real LLM voice-reply tracer

**What to build:** Replace the canned local response with a real LLM response: the user speaks on the already-working real microphone path, the final transcript goes through the gateway, the reply appears in the chat UI, and the existing system voice reads it aloud.

**Blocked by:** 02: Secure server-side LLM gateway.

**Status:** partially implemented — gateway client and first LLM-to-TTS tracer slice are green; sentence streaming/model UI/real-device gate remain open

- [x] A final transcript triggers exactly one streaming LLM request for that turn and displays the returned text with an explicit AI label when the gateway is configured.
- [ ] Live dialogue exposes user-selectable `gpt-5.6-sol` and `gpt-5.6-terra` models with Medium and High profiles whose provider wire values are server-validated; xhigh is available only for friend profiling, personality extraction, or long-summary tasks.
- [ ] Streaming sentence segmentation can dispatch the first complete short clause to TTS before the full response finishes, while preserving text order and cancellation.
- [ ] The selected model/profile is visibly identified and scoped to the active AI friend or session; unsupported combinations fail visibly and never silently switch model or reasoning level.
- [x] The existing VAD, ordinary-volume barge-in, pause, resume, and end-session behavior remains intact in the integrated App path.
- [x] A late, cancelled, or superseded provider result cannot overwrite a newer turn; task cancellation and transcript identity guards are applied.
- [x] Network unavailable, timeout, empty reply, malformed reply, and provider error states are visible and do not produce a fake success response.
- [ ] A connected iPhone demonstration proves real ASR → real LLM text → system TTS, with no provider key in the app bundle.

## Current implementation evidence

- `VoiceReplyPipeline` is covered by Core tests for history/voice propagation, empty output, and incomplete stream rejection.
- App wiring uses `OpenAINextGatewayClient`, `MiniMaxGatewayTTSService`, `AVAudioPlayer`, cancellation, and stale-transcript guards. Provider keys are not referenced by App sources.
- Remaining unchecked items require sentence-level TTS streaming, model/profile UI, and a connected-iPhone validation.
