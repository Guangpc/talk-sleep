# OpenAI-compatible LLM implementation map

## Notes

This feature is intentionally independent from MiniMax voice synthesis. It ends with a real text reply that can still use the existing system TTS.

## Tickets

| Ticket | Status | Depends on | Result |
|---|---|---|---|
| 01 | ready-for-agent | — | Provider contract, model/endpoint verification, secret and data-processing gate |
| 02 | ready-for-agent | 01 | Server-side gateway with secret isolation and normalized errors |
| 03 | ready-for-agent | 02 | Real transcript → LLM text → system TTS vertical slice |
| 04 | ready-for-agent | 03 | Context, persistence, cancellation, timeout and failure hardening |
