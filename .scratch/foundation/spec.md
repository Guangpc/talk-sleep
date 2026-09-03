# Spec: Foundation — 可测试的 iOS 工程骨架与域核心

Status: resolved

基准：`PRD.md`（唯一基准）。本 spec 是三个纵向切片的第一个（顺序：Foundation → 创建 AI 好友 → 自动语音会话）。

## Problem Statement

PRD 已锁定产品与验收（多 AI 好友、素材流水线、自动语音会话、睡眠状态机、中英混合、数据控制与合规红线）。本 Foundation slice 已建立可运行的 iOS 工程与可测试的核心逻辑承载点，为后续“创建 AI 好友”和“自动语音会话”提供能编译、能单测领域逻辑、能用真机验收音频/系统 seam 的最小骨架；后续实现不得把核心状态机重新混入 UI、音频或网络细节。

## Solution

搭建一个可编译、可测试、可增量生长的 iOS 工程：

- **App 壳（iOS）**：SwiftUI 应用入口 + 最小占位界面（例如 AI 好友列表的空状态页），承载权限/音频/系统集成 seam。
- **域核心（平台无关 Swift Package）**：按 PRD §6 词汇定义域类型与两个纯逻辑状态机（素材处理流水线、语音会话/睡眠状态机），以**注入时钟与事件驱动**方式实现，全部可在无设备环境单元测试。
- **单一主 seam = 域核心的纯逻辑接口**；**第二 seam = 真机音频/系统矩阵**（无法脱离 iOS 单测，走文档化真机清单验收）。理由与折中记录为 ADR-0001。
- **术语与决策落盘**：建立根 `CONTEXT.md`（沿用 PRD 术语）与 `docs/adr/0001-architecture-seams.md`。
- **测试与质量基线**：`swift test` 可跑（域核心 XCTest 单测）、`swiftlint` 可选；本地文档化运行命令。
- 本 spec 明确不实现任何真实 AI/素材/音频/网络能力（见 Out of Scope），只做地基与可验证的骨架行为。

## User Stories

1. As an iOS engineer, I want a buildable Xcode workspace with an app target and a platform-independent Swift Package for the domain core, so that every later feature lands in a tested home rather than a blank repo.
2. As a developer, I want domain types (AI Friend, Source Material, Turn/Session, Sleep Record, Style Profile, Memory) that match the PRD §6 vocabulary exactly, so that later specs share one glossary instead of drifting.
3. As a developer, I want the voice-session/sleep state machine (chatting → 9:30 silent → gentle prompt → 30 s no reply → possibly-asleep → awaiting wake confirm) as a pure, clock-injected state machine, so that PRD F-201/F-202/F-205 transitions are unit-testable without a microphone or device.
4. As a developer, I want the friend-creation pipeline state machine (imported → OCR/transcript → speaker separation → low-confidence confirm → role generated → ready to chat) as pure logic with injectable processing steps, so that PRD F-001/F-003/F-004 flows can be tested before any real OCR/ASR exists.
5. As a developer, I want all product constants centralised and injectable (9:30 idle, 0:30 grace, 10 h wake rule, 30-day retention default, 3-minute single-utterance cap), so that time-based acceptance criteria are tested with fake clocks rather than sleeps.
6. As an engineer, I want the domain core to depend only on protocols for AudioSession/ASR/TTS/analysis/storage, so that the App shell and future backends can be swapped without changing state-machine logic.
7. As an engineer, I want a minimal iOS shell screen that lists "AI 好友" with an explicit AI badge placeholder, so that the app opens to something real and the PRD §7.3 list surface has a starting point.
8. As a test engineer, I want a documented real-device matrix checklist (per PRD §15.1) checked into the repo, so that the audio/system seam (mic, lock screen, speaker, interruptions) has an executable manual gate before each release.
9. As a developer, I want the compliance guardrails from PRD (18+, China mainland first, no medical claims, AI-not-human labelling, consent-and-deletion controls) listed in CONTEXT.md, so that every later spec is written against them.
10. As an engineer, I want CI-friendly local commands (`swift test`, lint, workspace bootstrap) documented, so that a new contributor or an agent can verify the skeleton without Xcode GUI knowledge.
11. As an iOS developer, I want locale scaffolding for zh-Hans and en present from day one, so that bilingual UI copy is not retrofitted later.
12. As a product owner, I want the Foundation slice to leave PRD scope untouched (no fake voice features), so that early code cannot silently contradict the product decisions made in grilling.

## Implementation Decisions

- 架构分层：**App 壳**（SwiftUI，iOS 音频/权限/UI/锁屏/通知）与**域核心**（Swift Package，无 Apple 平台依赖），二者只经显式协议接口通信。域核心不 import AVFoundation/Speech 等。
- 域核心内容：
  - 域类型：AI 好友配置（自定义名称、头像 ref、声音配置 ref、风格摘要、记忆集、话题偏好、禁提集）、素材批次与条目（截图/文本/音频 + 说话人归属状态）、转写片段、会话 Turn、睡眠记录。
  - 状态机 A（素材处理流水线）：导入 → OCR/转写 → 说话人区分 → 低置信度确认（挂起等待）→ 生成声音配置/风格摘要/候选记忆 → 可聊天。以事件驱动 + 注入处理器协议实现；处理器在 Foundation 阶段用可配置 fake。
  - 状态机 B（语音会话/睡眠）：PRD §7.7 状态图原样建模，含"暂停聆听""结束聊天""用户有效语音重置计时"；时间由注入 Clock 驱动，保证 9:30/0:30/10 h 规则可测。
  - 常量表集中（见 User Story 5），支持测试注入覆盖。
- 域核心只定义所需协议契约（AudioSession/ASR/TTS/素材分析/存储），不在本 spec 提供真实实现；实现留待对应 feature spec。
- 工程形态：Xcode 工程 + 本地 Swift Package（Swift Package Manager）；最低 iOS 版本与 xcodegen/tuist 与否列为技术 Spike，实施前冻结（对应 PRD P1 "最低支持 iPhone 与 iOS 版本"）。
- 术语与决策：创建根 CONTEXT.md；创建 docs/adr/0001-architecture-seams.md 记录"双 seam 折中"（纯逻辑 seam + 真机音频 seam）与"域核心平台无关"决策；后续 ADR 追加同目录。
- 语言与合规红线（18+、中国大陆优先、非医疗表述、AI 标识、同意与删除控制、危机回应）写入 CONTEXT.md 供后续 spec 引用。
- 不创建仓库外服务；不做账号/支付/训练数据。

## Testing Decisions

- 好测试的定义：只测外部行为——向状态机喂事件序列断言状态与输出（例如"9:30 无有效语音且 30 s 无回应 → 状态=可能已入睡，时间=注入时钟值"），不断言内部实现。
- 被测模块：域核心（XCTest）：状态机 A 与 B 的全迁移路径、常量注入、说话人区分低置信度挂起/恢复。
- 时间处理：fake Clock 注入；禁用真实 sleep 测试。
- 壳层（iOS）：仅冒烟测试最小界面与 launch；音频/锁屏/麦克风真实行为不做单测伪装，而是以文档化真机矩阵 checklist（PRD §15.1 导出）作为 seam 2 验收门。
- Prior art：本仓库无既有测试；基准来自 PRD §11 验收标准（F-001…F-305）与 §12 观测指标——每个状态机测试用例可追溯到对应 F 编号。
- 测试不依赖 Xcode 的 GUI 也可在 CI/命令行 `swift test` 执行。

## Out of Scope

- 真实 OCR / 语音转写 / 说话人分离 / LLM / TTS / 声音克隆 / 任何后端或第三方 SDK 接入；
- 素材导入 UI 与相册/微信/文件交互；
- 麦克风、音频会话、锁屏后台、系统通知等 iOS 集成行为；
- 睡眠计时落库、总结/建议生成策略、数据删除/导出实现（`SleepRecord` 的总结/建议字段仅作为 Foundation 类型边界）；
- 账号、订阅、支付、训练数据收集；
- 真机部署与 App Store 提交流程。

## Further Notes

- 完成标准（Definition of Done）：`swift build`/`swift test` 通过；状态机迁移测试可追溯到 PRD F 编号；CONTEXT.md 与 ADR-0001 落盘；壳层启动断言已接入 XCUITest target；真机矩阵 checklist 入库。真实 UI launch 与真机矩阵执行仍是后续环境门禁，不在本次 generic test build 中虚报完成。
- 后续切片顺序：Spec 2「创建 AI 好友（素材流水线）」→ Spec 3「自动语音会话 + 睡眠状态机（接音频 seam）」。各自独立 spec，复用本 Foundation 的 seam 与类型。
- 优先级：本 spec 应一次交付完成再拆下一张；不建议并行开工，避免两个 feature 同时在空骨架上冲突。
