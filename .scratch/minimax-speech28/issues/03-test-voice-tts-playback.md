# 03: MiniMax test-voice TTS playback and barge-in

**What to build:** Use a non-person MiniMax test voice to synthesize the existing local reply, play the returned audio on the iPhone, and preserve the already-verified ordinary-volume interruption behavior.

**Blocked by:** 02: Secure MiniMax Speech gateway.

**Status:** partially implemented — gateway TTS client and AVAudioPlayer path are green; real-device and production hardening gates remain open

- [ ] A configured test `voice_id` produces real MiniMax Speech audio that the iPhone can play; system TTS is not silently used as a success fallback.
- [x] Audio playback begins only after a valid gateway response and reports failure without falling back to system speech; explicit loading UI remains open.
- [x] User speech at ordinary conversational volume uses the existing coordinator stop effect and the App calls `AVAudioPlayer.stop` without continuing buffered playback.
- [x] Stop, pause, end, teardown, network failure, and cancellation release the request/player path; cache hardening remains a later ticket.
- [ ] A connected iPhone smoke test records provider model, latency, audio format, and ordinary-volume interruption result without recording raw audio in the repository.

## Current implementation evidence

- `VoiceReplyPipeline` is covered by Core tests for history/voice propagation, empty output, and incomplete stream rejection.
- App wiring uses `OpenAINextGatewayClient`, `MiniMaxGatewayTTSService`, `AVAudioPlayer`, cancellation, and stale-transcript guards. Provider keys are not referenced by App sources.
- Remaining unchecked items require sentence-level TTS streaming, model/profile UI, consented friend voice binding, local records/context hardening, production cache/offline policy, and a connected-iPhone validation.
