# 01: MiniMax Speech 2.8 provider contract and compliance gate

**What to build:** Verify the exact MiniMax Speech 2.8 account capability and document a safe provider contract before any real friend recording is uploaded.

**Blocked by:** None (can start immediately).

**Status:** partially-verified — TTS technical contract passed; clone/compliance gates remain open

- [x] Verify the mainland TTS endpoint, authentication, `speech-2.8-hd` model, synchronous synthesis request/response shape, and MP3 output. Upload/clone and streaming options remain open for the later authorized-source slice.
- [ ] Verify the documented source-audio constraints: clone source `mp3/m4a/wav`, 10 seconds–5 minutes, ≤20 MB; optional prompt audio under 8 seconds and ≤20 MB. Implementation must enforce these before upload; no person audio was uploaded in this gate.
- [x] Record a non-person test synthesis latency and error envelope; clone timing, limits, pricing, and rate-limit sampling remain open.
- [ ] Verify MiniMax retention, training use, processing region, user deletion path, and support escalation; unknowns remain explicit launch blockers.
- [x] Define the server-only `MINIMAX_API_KEY` contract and redacted fixture rule; this gate used no person audio.

## Local provider contract verification

- 2026-09-04，使用仓库根目录 `.env.local` 中的本地 secret，通过 `curl` 调用 `https://api.minimax.cn/v1/t2a_v2`；没有输出 key、Authorization header 或原始响应。
- 请求 `model=speech-2.8-hd`、官方内置测试音色 `male-qn-qingse`，返回 HTTP 200、`base_resp.status_code=0`，并返回 MP3 hex 音频；音频采样率 32 kHz、单声道、音频时长约 4.1 秒，接口耗时约 1.24 秒。
- 该结果只证明测试音色的 TTS contract，不证明朋友录音上传、voice clone、数据保留或删除策略已通过。
