# MiniMax Speech 2.8 implementation map

## Notes

This feature is independent from LLM text generation. Test-voice synthesis is deliberately completed before any real friend material is accepted.

## Tickets

| Ticket | Status | Depends on | Result |
|---|---|---|---|
| 01 | ready-for-agent | — | Verified Speech 2.8 provider, model, limits, data and deletion gate |
| 02 | ready-for-agent | 01 | Server-side MiniMax gateway for upload, clone and synthesis |
| 03 | ready-for-agent | 02 | Test voice audio reaches iPhone and is interruptible |
| 04 | ready-for-agent | 01, 02 | Authorized source intake, validation and consent-gated upload |
| 05 | ready-for-agent | 02, 04 | Authorized clone → voice_id → profile-bound preview |
| 06 | ready-for-agent | 03, 05 | Production TTS cancellation, cache, retry and clone voice output hardening |
