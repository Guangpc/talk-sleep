# 01: OpenAI-compatible LLM provider contract and compliance gate

**What to build:** Establish a verified, redacted provider contract for `api.openai-next.com` so the team knows the real request path, model, reasoning configuration, data behavior, and operational limits before sending user transcripts.

**Blocked by:** None (can start immediately).

**Status:** partially-verified — technical contract passed; compliance and production gates remain open

- [x] Verify the actual OpenAI-compatible endpoint path, authentication scheme, request and response shape, and streaming behavior using a locally injected credential; timeout/error handling remains covered by the gateway implementation tests. No credential is recorded.
- [x] Verify that `gpt-5.6-sol` and `gpt-5.6-terra` accept the explicit `reasoning_effort` values `medium`, `high`, and `xhigh`; provider-side mapping semantics remain unverified.
- [x] Measure the same short Chinese friend-style turn. SSE smoke calls returned HTTP 200 with text for all six Sol/Terra profile combinations; Terra repeated samples and quality gate are recorded below. A same-condition repeated Sol benchmark is still required before selecting the default.
- [ ] Confirm that user-selectable reasoning settings are validated server-side and rejected visibly when unsupported; this is implemented and tested in ticket 02, but remains open until that slice is reviewed.
- [ ] Verify provider data retention, training use, processing region, China-mainland network accessibility, rate limits, pricing, and deletion/support path; record unknowns as explicit launch blockers.
- [x] Define the server-only `OPENAI_NEXT_API_KEY` environment contract, redacted fixture rule, and no-secret logging rule.
- [x] Confirm that validation used only synthetic Chinese text and no friend voice material or raw audio.

## Current detection notes

- 2026-09-04 无密钥探测：`https://api.openai-next.com/` 可达；`GET /v1/models` 返回结构化 JSON 401；无鉴权 `POST /v1/chat/completions` 与 `POST /v1/responses` 均返回结构化 JSON 401，说明主机的鉴权网关收到了这些路径并先执行 Bearer 鉴权；由于鉴权发生在路由/模型校验前，尚不能单凭 401 证明具体路由和模型可用。
- 用户已在 DeepSeek Harness 中成功部署 `gpt-5.6-sol`，这是该用户配置下的可用性证据；尚未证明服务端 API 的模型枚举、`xhigh` wire 参数、延迟、限额或数据政策。
- 第一实现候选暂不替换为其他 provider；必须用安全注入的服务端密钥完成一次脱敏 chat-completion smoke test，并记录首 token/完整回复延迟。实时语音允许用户选择 Medium/High；xhigh 只在朋友画像、性格总结或长总结等任务中开放，除非实测证明实时延迟达标。
- 备选评估模型：MiniMax 官方 `M2-her`，文档明确定位角色扮演、多轮对话和示例对话学习，64K 上下文；若 openai-next 的模型/延迟/数据条件不达标，可在不改变客户端 LLM seam 的前提下切换。
## Authenticated smoke result

- 2026-09-04 用户在本地安全注入同一 provider key 后验证：`GET /v1/models` HTTP 200 且列出 `gpt-5.6-sol`。
- 非流式 `/v1/chat/completions` 对 `reasoning_effort` 的 `medium`、`high`、`xhigh` 均返回 HTTP 200；耗时分别约 4.57 秒、4.08 秒、5.64 秒。
- HTTP 200 证明三个值未被 gateway 拒绝，但不能证明上游严格执行了三个不同推理档位；仍需核对响应元数据或 provider 文档。
- 本次 `stream: false` 的 TTFB 约等于完整响应等待时间，不能作为首 token 指标。Provider 暂定通过技术兼容 gate，但 streaming、取消、重复采样、数据政策和 reasoning 语义仍未完成。
## Terra authenticated streaming result

- 2026-09-04 `gpt-5.6-terra` 出现在鉴权后的 `/v1/models` 列表。
- Medium 流式调用 3/3 成功，首个实际文本中位数 3.355 秒，完整回复中位数 4.185 秒。
- High 流式调用 3/3 成功，首个实际文本中位数 3.789 秒，完整回复中位数 4.359 秒。
- xhigh 流式兼容测试 1/1 成功，首个实际文本 6.026 秒，完整回复 7.109 秒。
- 合成朋友场景的三档回复均先共情、未立即建议、未编造经历、未冒充真人、未机械复述无关记忆，质量 gate 通过。
- 决策：Terra Medium/High 可加入日常对话模型选择器，但因 LLM 首文字延迟尚未计入 MiniMax TTS，不能作为默认快速档；Terra xhigh 仅用于朋友画像、性格提炼和长总结。

## Local provider contract verification

- 2026-09-04，使用仓库根目录 `.env.local` 中的本地 secret，通过 `curl` 完成脱敏 smoke test；测试过程未输出 key、Authorization header 或原始响应。
- `GET https://api.openai-next.com/v1/models` 返回 HTTP 200；`gpt-5.6-sol`、`gpt-5.6-terra` 均列出。
- OpenAI-compatible SSE `POST /v1/chat/completions` 对 Sol/Terra × Medium/High/xhigh 共 6 组均 HTTP 200 且产生文本。单次总耗时范围约 2.26–4.90 秒；该批次用于确认 wire compatibility，不作为稳定 P95。
- 下一道 gate 是 02 adapter 的单元/集成 seam 测试，以及重复 Sol 基准、SSE 取消、provider data policy 和生产部署认证。
