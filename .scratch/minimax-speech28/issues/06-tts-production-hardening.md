# 06: MiniMax TTS cancellation, cache, and cloned-voice hardening

**What to build:** Make MiniMax audio reliable enough for a real session: the active voice configuration produces speech with bounded latency, cancellation is immediate, and retries or cache reuse never cause stale or duplicate playback.

**Blocked by:** 03: MiniMax test-voice TTS playback and barge-in; 05: Authorized MiniMax voice clone and AI-profile binding.

**Status:** partially implemented — complete-audio cancellation and active voice binding are green; cache/streaming/device hardening remain open

- [x] The active in-memory profile voice ID is captured per reply task and passed only through the gateway client; it cannot drift to a later task's voice.
- [x] The current verified path uses bounded complete MP3 audio and documents sentence-level streaming as a later optimization.
- [x] User speech, pause, end, provider cancellation, and stale-reply guards stop or suppress the complete-audio path; app interruption/network-loss device coverage remains open.
- [ ] Cache keys are scoped by voice ID, text, model, and relevant synthesis settings; raw audio cache deletion is testable.
- [ ] A real-device matrix covers ordinary-volume barge-in, repeated turns, timeout, retry, audio interruption, and no-fallback-on-failure behavior.

## Current implementation evidence

- The Swift/Core seam is covered by deterministic validator/client tests and the App generic build.
- Remaining unchecked items require provider-side lifecycle policy, profile persistence/provenance, preview confirmation, cache deletion, and connected-iPhone verification.
