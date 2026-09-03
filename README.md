# SleepMate

SleepMate 是中国大陆、iOS 优先的 AI 好友睡前语音陪聊 MVP。用户可以基于自己有权处理的聊天素材与声音素材创建可编辑的 AI 好友，在睡前进行自动语音会话；本项目当前完成的是 Foundation（工程骨架与可测试域核心），不是完整产品。

## 当前基准

- 产品唯一基准：[`PRD.md`](PRD.md)
- 旧版产品定义（非规范）：[`PRD-v1-2026-09-01-archived.md`](PRD-v1-2026-09-01-archived.md)
- 项目上下文与术语：[`CONTEXT.md`](CONTEXT.md)
- 架构说明：[`docs/architecture.md`](docs/architecture.md)
- 架构决策：[`docs/adr/0001-architecture-seams.md`](docs/adr/0001-architecture-seams.md)
- 真机验收矩阵：[`docs/test-matrix.md`](docs/test-matrix.md)
- 当前 Foundation spec：[`.scratch/foundation/spec.md`](.scratch/foundation/spec.md)

## Foundation 已交付

- Swift Package Manager 域核心 `SleepMateCore`，平台无关，不依赖 AVFoundation、Speech 或 UIKit。
- PRD 域类型：AI 好友、声音配置、风格摘要、记忆、素材批次、转写片段、会话 Turn、睡眠记录。
- 可注入 `SleepMateClock` 与产品时长常量。
- 睡眠会话状态机：9:30 无有效用户语音后询问，30 秒无回应进入“可能已入睡”；支持暂停冻结计时、恢复、结束、锁屏/App/手动起床确认、10 小时后抑制静默自动填充。
- 好友创建流水线 seam：导入、OCR/转写、说话人区分、分析、低置信度确认、候选记忆显式选择、配置生成等阶段的可观察域状态。
- `AudioSession`、`ASRService`、`TTSService`、`MaterialAnalysisService`、`SleepMateStore` 协议边界；真实适配器属于后续 feature spec。
- 最小 SwiftUI iOS 壳、中文/英文空态、本地化 AI 好友标识和 XCUITest 启动测试入口。
- 7 张 Foundation ticket 已按依赖关系完成并记录在 `.scratch/foundation/issues/`。

## 本地验证

环境：Swift 6.3.3、Xcode 26.6、iOS SDK 26.5；目标最低 iOS 版本当前暂定 iOS 17，待技术 Spike 冻结。

```sh
swift build
swift test
xcodebuild -project SleepMate.xcodeproj \
  -scheme SleepMate \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

`swift test` 当前覆盖 18 个域核心测试。`build-for-testing` 会编译 App 与 XCUITest target；如果机器没有已安装的 iOS Simulator runtime，不能执行真实 UI 测试，只能完成 generic test build。正式发布前必须按 [`docs/test-matrix.md`](docs/test-matrix.md) 在真机执行音频、锁屏、后台、权限、弱网、删除和数据生命周期验收。

## 目录结构

```text
App/                         SwiftUI 壳与本地化资源
Sources/SleepMateCore/       平台无关域模型、状态机、协议
Tests/SleepMateCoreTests/    域核心 XCTest
SleepMate.xcodeproj/         iOS App 与 XCUITest target
.scratch/foundation/         Foundation spec、依赖图与 tickets
docs/                        架构、Agent 约定与真机矩阵
research/                    Apple/隐私/后台音频研究
```

## 下一步

Foundation 之后按以下顺序继续，每一步先形成独立 spec，再拆 tracer tickets：

1. **创建 AI 好友**：接入相册/分享/文件导入、OCR、ASR、说话人分析、声音配置、用户编辑与保留/删除策略。
2. **自动语音会话与睡眠状态机接壳**：接入 VAD/AEC、ASR、LLM、TTS、自然打断、锁屏/后台和起床通知。
3. **数据与合规实现**：本地记录、云端派生数据、逐类删除、导出、供应商不训练保证和 App Privacy/Privacy Manifest。

当前 Foundation 不实现真实 OCR、ASR、LLM、TTS、声音克隆、云服务、麦克风权限请求、后台音频或数据存储；这些边界不能在后续实现中被静默绕过。
