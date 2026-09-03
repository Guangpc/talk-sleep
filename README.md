# SleepMate

SleepMate 是面向中国大陆、iOS 优先的 AI 好友睡前语音陪聊 MVP。项目当前已完成 Foundation（工程骨架与可测试域核心），并跑通一条真实 iPhone 语音会话 tracer：真实麦克风、Apple Speech 实时转写、系统本地朗读和普通音量打断。云端 AI 对话与声音克隆尚未接入。

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
- 7 张 Foundation ticket 已按依赖完成并记录在 `.scratch/foundation/issues/`。

### 真实语音 tracer

- `VoiceSessionCoordinator`：纯状态/effect reducer，覆盖开始、回复播放、播放完成、用户打断、暂停、恢复和结束。
- `VoiceActivityDetector`：基于环境底噪的纯 RMS onset 检测；普通说话音量不依赖固定高阈值，连续帧过滤单次毛刺。
- iOS `AudioSession` adapter：`AVAudioSession(.playAndRecord/.voiceChat)`、`AVAudioEngine` 输入 tap、voice processing/AEC、Apple Speech 流式转写和 `AVSpeechSynthesizer` 本地朗读。
- SwiftUI 会话页进入后自动开始聆听，显示“正在聆听/已暂停/已结束”、麦克风与云端连接状态、实时转写、已生成回复和明确的 AI/本地演示标识。
- App 不持久化原始音频；当前音频交给 Apple Speech 识别，系统可能使用网络处理，不能表述为完全本地 ASR。
- 当前回复是本地固定测试文案，不代表 LLM；当前朗读是系统声音，不代表好友声音克隆或已接入云端 TTS。

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

`swift test` 当前覆盖 24 个 Core 测试。generic `build-for-testing` 会编译 App 与 XCUITest target；本机没有可用 Simulator runtime 时不能执行模拟器 UI 测试。

2026-09-03 已在 iPhone 12（iPhone13,2，iOS 18.5）完成签名构建、安装和启动；真实麦克风、中文转写、本地朗读均成功。固定 RMS 阈值导致普通音量打断偶发失败后，已改为自适应 VAD + voice processing/AEC，并由用户连续 3 次以普通音量验证打断成功。完整证据和未执行项见 [`docs/test-matrix.md`](docs/test-matrix.md)。

## 目录结构

```text
App/                         SwiftUI 壳、真实 iOS 音频 adapter、本地化资源
Sources/SleepMateCore/       平台无关域模型、状态机、协议、语音协调器与 VAD
Tests/SleepMateCoreTests/    域核心 XCTest
SleepMate.xcodeproj/         iOS App 与 XCUITest target
.scratch/foundation/         Foundation spec、依赖图与 tickets
docs/                        架构、Agent 约定与真机矩阵
research/                    Apple/隐私/后台音频研究
```

## 尚未实现

1. **真实 AI 对话**：经批准的云端 LLM、错误/重试、弱网行为和供应商不训练保证。
2. **好友声音**：获授权声音素材处理、声音配置、真实 TTS/声音克隆与删除传播。
3. **完整设备行为**：音频中断、锁屏/后台、通知、最低支持机型、噪声/多人环境和长会话稳定性。
4. **创建 AI 好友**：相册/分享/文件导入、OCR、素材 ASR、说话人分析、编辑与确认 UI。
5. **数据与合规**：本地记录、30 天过期、逐类删除、导出、Privacy Manifest 和 App Store 审核材料。

任何未配置的 ASR/LLM/TTS/云端能力都必须在 UI 与文档中明确标示，不能用 fake 冒充生产实现。
