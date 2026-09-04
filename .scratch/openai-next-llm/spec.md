# OpenAI-compatible LLM 接入

## 目标

将当前真实麦克风产生的有效语音转写交给用户指定的 `https://api.openai-next.com` LLM 服务，生成真实 AI 文字回复，并通过现有会话协调器交给后续语音输出 feature。

## Provider 边界

- 当前已知信息包括 base URL，以及已通过鉴权 smoke test 的 `gpt-5.6-sol` 和 `gpt-5.6-terra`；具体 OpenAI-compatible 路径、请求体、鉴权、模型可用性和 reasoning 参数必须用脱敏配置验证。
- Speech 2.8 不属于本 feature；它负责语音合成，不负责生成对话文字。
- API Key 只允许通过服务端环境变量（例如 `OPENAI_NEXT_API_KEY`）注入，禁止进入 iOS bundle、源码、日志、ticket、测试 fixture 或 git 历史。
- 用户在对话中粘贴过一枚密钥；本 feature 不保存、不读取、不回显它。正式接入前应在服务商后台撤销并重新生成。
- 必须明确服务商的数据处理、保留、训练使用和中国大陆网络可用性；不能仅因接口名称兼容 OpenAI 就宣称合规或稳定。

## 期望数据流

```text
有效用户语音
  → 现有 Apple Speech 转写
  → 服务端 LLM gateway
  → 真实 AI 文字回复
  → 本地聊天记录
  → 后续 MiniMax Speech 或当前系统 TTS
```

## Reasoning profile policy

用户希望将推理档位作为可选择的产品配置，而不是固定使用最高档位：

- 实时睡前对话允许用户选择 `gpt-5.6-sol` 或 `gpt-5.6-terra`，并在 Medium 和 High 之间选择；默认模型需由同条件流式基准决定。
- 初期朋友画像、朋友性格总结、长篇对话总结等非实时任务允许使用所选兼容模型的 xhigh；xhigh 不进入实时对话选项。
- `Medium`、`High`、`xhigh` 的实际 wire 参数和 provider 支持情况必须通过服务端 smoke test 确认；不能假设 OpenAI-compatible 中转站一定接受这些字符串。
- 用户选择的档位被 provider 拒绝时，App 必须显示明确错误并保留文字结果/重试入口，不得静默切换到另一个档位。
- 服务端应按任务类型限制可选档位，防止实时会话误用 xhigh 导致超过首段音频响应延迟目标；用户选择仍需可见、可解释。
- Terra 已通过合成朋友场景质量测试，但 Medium/High 的首文字中位数分别为 3.355 秒和 3.789 秒；它可以作为日常对话可选模型，但不能在缺少端到端音频延迟证据时设为默认快速模型。
- 模型与档位选择需要按 AI 好友或会话持久化，并在界面中显示实际使用配置；失败时不得静默换成其他模型。

## 当前基线

已有真实麦克风、Apple Speech、有效语音 gate、普通音量打断、会话协调器和本地系统 TTS tracer。新的实现应保留这些行为，不把网络错误伪装为本地成功回复。

## 非目标

- 不在 iOS 客户端直连 LLM provider。
- 不实现 MiniMax 音色复刻或 TTS；见独立 `minimax-speech28` feature。
- 不把本地固定回复继续留在 production path。
- 不在本 feature 中承诺锁屏/后台持续会话。

## 完成定义

用户可以在真机用普通音量说话，看到最终转写进入本地聊天记录，收到真实 LLM 文字回复；网络、权限、超时、取消和 provider 错误均可见且不会生成虚假回复。
