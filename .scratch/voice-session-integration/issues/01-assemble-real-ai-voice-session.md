# 01: Assemble the real AI voice session

**What to build:** With both provider features complete, replace the local tracer reply path with one complete real session: the user speaks, the verified LLM replies, MiniMax Speech 2.8 uses the selected voice configuration, and the iPhone plays the response while ordinary-volume barge-in remains reliable.

**Blocked by:** `openai-next-llm/04`: LLM context, local conversation records, and failure hardening; `minimax-speech28/06`: MiniMax TTS cancellation, cache, and cloned-voice hardening.

**Status:** in progress — first gateway-backed tracer slice assembled; blocked production gates remain

- [x] A final ASR transcript produces one real LLM stream and one MiniMax synthesis request for the configured gateway-backed AI friend/session.
- [x] The spoken response, visible text response, transcript, voice ID, and explicit AI label are carried through one in-memory session and friend voice reference.
- [x] Ordinary-volume user speech stops playback, cancels/supersedes pending pipeline work, marks interrupted text, and prioritizes the new turn in the App path.
- [x] Provider errors, permission errors, offline/cancellation states, and stale responses do not fall back to an unlabelled fake success.
- [ ] A connected iPhone verifies repeated turns, friend/voice switching, ordinary-volume interruption, app interruption behavior, and local record consistency.

## Current implementation evidence

- `VoiceReplyPipeline` is covered by Core tests for history/voice propagation, empty output, and incomplete stream rejection.
- App wiring uses `OpenAINextGatewayClient`, `MiniMaxGatewayTTSService`, `AVAudioPlayer`, cancellation, and stale-transcript guards. Provider keys are not referenced by App sources.
- Remaining unchecked items require sentence-level TTS streaming, model/profile UI, persistent friend records/provenance, local records/context hardening, production cache/offline policy, and a connected-iPhone validation.

- The current App setup now supports consent-gated MP3/M4A/WAV selection, bounded local validation, UTF-8 text entry/file import, server upload→clone, and in-memory voice/profile configuration before the voice session. Text-only setup intentionally uses a pre-bound stock/test voice; text does not pretend to create a custom voice ID.
- The real friend-audio clone and connected-iPhone playback remain human verification gates for the next session.
