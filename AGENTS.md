# SleepMate · 睡前 AI 好友语音陪聊（iOS MVP）

产品单一基准：[`PRD.md`](./PRD.md)（AI 好友中心化、多好友、自动语音会话、睡眠状态机）。
研究约束：[`research/ios-bedtime-voice-companion-constraints.md`](./research/ios-bedtime-voice-companion-constraints.md)。
旧版 PRD 归档：`PRD-v1-2026-09-01-archived.md`（仅供历史参考，不作为基准）。

## Agent skills

### Issue tracker

本地 Markdown tracker：spec 与 issue 以文件存于 `.scratch/<feature-slug>/`，spec 为 `spec.md`，issue 为 `issues/NN-<slug>.md`；triage 状态以文件顶部 `Status:` 行记录。详见 `docs/agents/issue-tracker.md`。

### Triage labels

（triage 技能未安装，不建标签映射；本地以 `Status:` 行直接使用 `needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix` 语义。）

### Domain docs

单上下文（single-context）：根 `CONTEXT.md`（术语与上下文）+ `docs/adr/`（决策记录）。消费规则见 `docs/agents/domain.md`。

## Current implementation and verification

Foundation 与真实语音 tracer 已完成：平台无关 `SleepMateCore`、域类型、注入时钟、睡眠会话状态机、好友创建流水线 seam、`VoiceSessionCoordinator`、自适应 `VoiceActivityDetector`、协议契约、SwiftUI 语音页和 XCUITest target。iOS 壳现在接入真实 `AVAudioSession`/`AVAudioEngine`、voice processing/AEC、Apple Speech 实时转写和系统本地 TTS；云端 LLM、好友声音 TTS/克隆、完整后台音频、云端存储和数据删除仍属于后续 spec。架构细节见 [`docs/architecture.md`](docs/architecture.md)，真机结果见 [`docs/test-matrix.md`](docs/test-matrix.md)，人类接手说明见 [`README.md`](README.md)。

- `swift build` — 编译平台无关域核心。
- `swift test` — 执行 24 个域核心 XCTest；时间相关测试使用注入时钟，禁止真实 sleep。
- `xcodebuild -project SleepMate.xcodeproj -scheme SleepMate -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing` — 编译 App 与 XCUITest target；没有 simulator runtime 时不能执行真实 UI 测试。
- 真机验证使用 `xcodebuild build` + `xcrun devicectl device install app/process launch`；XCUITest Runner 可能因设备 automation mode 超时，不能将该失败误判为 App 签名或安装失败。
