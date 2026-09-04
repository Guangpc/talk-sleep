# 04: LLM context, local conversation records, and failure hardening

**What to build:** Make successive AI turns useful and auditable: final user text and AI text are written to the local chat record, context is isolated per AI friend/session, and cancellation or weak network never corrupts the conversation.

**Blocked by:** 03: Real LLM voice-reply tracer.

**Status:** partially implemented — bounded in-memory context and stale/cancelled reply guards are green; local records/offline policy remain open

- [ ] Final user transcripts and final AI replies persist locally only after their turn reaches a terminal result; partial transcripts are not mistaken for final messages.
- [x] A new session or different AI friend cannot inherit the previous session's hidden context or voice/provider configuration in the current App lifecycle; persistent profile switching remains open.
- [x] Context size is bounded to the pipeline limit, and sensitive material is not written to diagnostics by default.
- [x] User interruption cancels or supersedes in-flight LLM work, and stale results cannot be spoken or persisted as the current turn.
- [ ] Offline, retry, rate-limit, and degraded-service states are represented in the UI and covered by deterministic tests plus a real-device smoke check.

## Current implementation evidence

- `VoiceReplyPipeline` preserves the first system instruction, keeps newest turns within a fixed message budget, requires a complete stream, and never calls TTS for empty/incomplete output.
- `VoiceSessionViewModel` resets context for a new session, captures voice/model per task, cancels pending work on interruption/pause/end, and checks transcript identity before playback.
- Local conversation-record persistence, terminal-result record policy, offline/retry UI and connected-device validation remain open.
