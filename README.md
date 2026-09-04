# SleepMate

SleepMate 是面向中国大陆、iOS 优先的 AI 好友睡前语音陪聊 MVP。项目当前已完成 Foundation，并接通聊天记录分析、真实麦克风、Apple Speech 实时转写、server gateway、OpenAI-compatible LLM 和 MiniMax Speech 2.8 HD TTS 组成的 AI 好友语音会话 tracer。真实朋友声音的逐项授权与 gateway attestation 已接通；provider-side 删除传播、会话持久化和生产合规门仍未完成。

## 当前基准

- 产品唯一基准：[`PRD.md`](PRD.md)
- 旧版产品定义（非规范）：[`PRD-v1-2026-09-01-archived.md`](PRD-v1-2026-09-01-archived.md)
- 项目上下文与术语：[`CONTEXT.md`](CONTEXT.md)
- 架构与语音数据流：[`docs/architecture.md`](docs/architecture.md)
- 架构决策：[`docs/adr/0001-architecture-seams.md`](docs/adr/0001-architecture-seams.md)
- 真机验收记录与待测矩阵：[`docs/test-matrix.md`](docs/test-matrix.md)
- Foundation spec：[`.scratch/foundation/spec.md`](.scratch/foundation/spec.md)

## 已交付

### Foundation

- 平台无关 Swift Package `SleepMateCore`；不依赖 AVFoundation、Speech 或 UIKit。
- PRD 域类型、可注入 `SleepMateClock`、产品时长常量、睡眠会话状态机和好友创建流水线 seam。
- `AudioSession`、`ASRService`、`TTSService`、`MaterialAnalysisService`、`SleepMateStore` interface。
- SwiftUI iOS 壳、中文/英文本地化、自动签名工程和 XCUITest target。
- Foundation tickets 已按依赖完成并记录在 `.scratch/foundation/issues/`；provider/gateway/voice-session 进度记录在各自 `.scratch/*/issues/`。

### 真实语音 tracer

- `VoiceSessionCoordinator`：纯状态/effect reducer，覆盖开始、回复播放、播放完成、用户打断、暂停、恢复和结束。
- `VoiceActivityDetector`：基于环境底噪的纯 RMS onset/end 检测；尾部静音结束 Apple Speech input，取得 final transcript（或 bounded partial fallback）后进入 processing，不再无限保持 listening。
- iOS `AudioSession` adapter：`AVAudioSession(.playAndRecord/.voiceChat)`、`AVAudioEngine` 输入 tap、voice processing/AEC、Apple Speech 流式转写和 `AVAudioPlayer` gateway 音频播放；生成回复期间暂停麦克风，播放时恢复 VAD 以保留打断路径。
- `FriendContextAnalysisPipeline` 用 profiling `xhigh` 将指定好友的聊天记录提取成可编辑的内容摘要、风格、口头禅、习惯、重要地点、重要经历与话题；用户创建好友即确认将编辑后的候选资料用于对话。
- `VoiceReplyPipeline` 把同一轮 transcript、会话文字 history、选定模型/推理档位和 AI 好友 voice reference 串成真实 LLM→TTS 请求；不完整或空的 LLM stream 不生成 TTS/fake success。
- App 不持久化原始音频；当前音频交给 Apple Speech 识别，系统可能使用网络处理，不能表述为完全本地 ASR。
- SwiftUI 会话页进入后自动开始聆听，显示“正在聆听/已暂停/已结束”、麦克风与 gateway 状态、实时转写、AI 回复和打断标记。App 只读取 app-to-gateway 配置；provider keys 只存在 server runtime，绝不进入 iOS。

## 验证

环境基准：Swift 6.3.3、Xcode 26.6、iOS SDK 26.5；最低部署版本当前为 iOS 17。

```sh
swift test
xcodebuild build-for-testing \
  -project SleepMate.xcodeproj \
  -scheme SleepMate \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

`swift test` 当前覆盖 53 个 Core 测试。generic `build-for-testing` 会编译 App 与 XCUITest target；本机没有可用 Simulator runtime 时不能执行模拟器 UI 测试。

2026-09-03 已在 iPhone 12（iPhone13,2，iOS 18.5）完成签名构建、安装和启动；真实麦克风、中文转写、本地朗读均成功。AI gateway/Core 自动验证已完成，但真实 iPhone LLM→MiniMax 音频回归、普通音量 AI 打断和中断恢复仍待补。完整证据和未执行项见 [`docs/test-matrix.md`](docs/test-matrix.md)。

## 目录结构

```text
App/                         SwiftUI 壳、真实 iOS 音频 adapter、gateway 配置、本地化资源
Sources/SleepMateCore/       域模型、状态机、协议、gateway edge clients、reply pipeline 与 VAD
Tests/SleepMateCoreTests/    域核心 XCTest
SleepMate.xcodeproj/         iOS App 与 XCUITest target
.scratch/foundation/         Foundation spec、依赖图与 tickets
docs/                        架构、Agent 约定与真机矩阵
research/                    Apple/隐私/后台音频研究
```

## 尚未实现

1. **生产 AI 对话 hardening**：会话文字本地记录、terminal-result persistence、重试/退避、弱网/offline 和供应商不训练保证。
2. **好友声音生产授权链**：当前已有逐项 consent、上传 attestation、gateway 强制校验、clone 和持久 binding；preview-confirm、授权证明归档、缓存、删除传播和生产音频策略仍待完成。
3. **完整设备行为**：音频中断、锁屏/后台、通知、最低支持机型、噪声/多人环境和长会话稳定性。
4. **完整创建 AI 好友**：当前已有文字输入/UTF-8 文件导入、指定好友的可编辑聊天分析结果和 consent-gated 音频 clone；聊天截图 OCR、素材音频 ASR、可靠说话人区分和持久化 profile UI 仍待完成。
5. **数据与合规**：本地记录、30 天过期、逐类删除、导出、Privacy Manifest 和 App Store 审核材料。

### 本地 App gateway 配置

先按 [`server/README.md`](server/README.md) 启动 gateway。默认监听 `127.0.0.1:8787`，并使用仓库根目录被 Git 忽略的 `.env.local` 读取 server-only provider keys 与 `SLEEPMATE_GATEWAY_TOKEN`。

App 文字与文件页面内置 **Gateway 配置**卡片：

1. Gateway URL 填 `http://127.0.0.1:8787`（App 在模拟器或 Mac 本机运行时）或填你的局域网/HTTPS gateway 地址；
2. App token 填 `.env.local` 中 `SLEEPMATE_GATEWAY_TOKEN` 的值；
3. 点击“保存配置”；App token 会保存到 iOS Keychain，页面不会回显 token；
4. 再点击“总结聊天风格与记忆”或“创建 AI 好友”。

也可以在 Xcode Run Scheme 的 Environment Variables 中注入：

```text
SLEEPMATE_GATEWAY_URL=http://127.0.0.1:8787
SLEEPMATE_GATEWAY_TOKEN=<与 server 的 SLEEPMATE_GATEWAY_TOKEN 完全一致>
SLEEPMATE_LLM_MODEL=gpt-5.6-sol
SLEEPMATE_LLM_REASONING=medium
SLEEPMATE_VOICE_ID=<可选；文字-only 好友使用 stock/test voice>
```

`OPENAI_NEXT_API_KEY` 和 `MINIMAX_API_KEY` 只给 server 使用，绝不能填入 App 或 Xcode Scheme。App token 不是 provider key；两者必须与 gateway runtime 的值匹配。

### 好友声音选择

创建 AI 好友后，在“朋友语音”页选择该好友即可：

- 直接选择 **温柔女声、成熟御姐音、温暖闺蜜音、知性姐姐音、甜美女声**；选择会立即持久绑定对应 MiniMax 系统 voice ID、语速和音调；
- 不上传声音也能使用默认“温柔女声”开始 AI 对话；
- 或导入 MP3/M4A/WAV；
- 或点击“开始录入声音”，录制 10 秒至 5 分钟后再次点击停止，逐项确认授权、用途、云端处理与保留/删除规则后上传并绑定模仿声音。

内置 voice ID 来自 [MiniMax System Voice ID List](https://platform.minimax.io/docs/faq/system-voice-id)。自录/导入素材仍必须经过授权确认，内置音色不需要上传素材。

完整 route contract、导入顺序与本地运维命令见 [`docs/integration-guide.md`](docs/integration-guide.md) 和 [`docs/runbook.md`](docs/runbook.md)。

任何未配置的 ASR/LLM/TTS/云端能力都必须在 UI 与文档中明确标示，不能用 fake 冒充生产实现。
