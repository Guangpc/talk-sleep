# SleepMate Foundation 架构

这是 Foundation 阶段的实现说明；产品行为以 [`../PRD.md`](../PRD.md) 为准，架构取舍详见 [`adr/0001-architecture-seams.md`](adr/0001-architecture-seams.md)。

## 分层

```text
SwiftUI iOS App 壳
  ├─ UI / 本地化 / 权限 / AVAudioSession / 锁屏 / 通知（后续接入）
  └─ 适配器：AudioSession、ASRService、TTSService、MaterialAnalysisService、SleepMateStore
                         │ 显式协议边界
                         ▼
SleepMateCore（平台无关 Swift Package）
  ├─ PRD 域类型与产品时长常量
  ├─ FriendCreationPipeline：素材创建流程策略
  └─ SleepSessionStateMachine：会话、静默询问、可能入睡与起床策略
```

`SleepMateCore` 不依赖 AVFoundation、Speech、UIKit、网络或持久化框架。它只通过公共类型、事件和协议表达可观察行为；iOS 壳或后续服务适配器负责真实设备、网络和存储。

## 主要域边界

### AI 好友与素材

`AIFriendProfile` 包含用户自定义名称、头像引用、声音配置、可编辑风格摘要、已确认记忆、话题偏好和禁提主题。`SourceMaterialBatch` 与 `SourceMaterial` 描述截图、文本、音频和说话人归属；`MaterialProcessingStage` 描述 imported、OCR/transcription、speaker separation、analysis、awaiting confirmation、ready 等阶段。

`FriendCreationPipeline` 接收 `MaterialAnalysisService`（当前以同步 fake 适配器测试），将分析结果变成可观察的阶段事件。低置信度或冲突先停在确认态；只有用户明确选择的候选记忆才进入 `AIFriendProfile.memories`。OCR、ASR、说话人分析和声音生成的真实实现不属于 Foundation。

### 睡眠会话

`SleepSessionStateMachine` 是注入 `SleepMateClock` 的纯逻辑 reducer。关键状态：

```text
chatting
  → checkingIn（无有效用户语音达到 9:30，发出 askIfAwake）
  → awaitingWakeConfirmation（再过 30 秒无回应，创建推测睡眠记录）
  → completed（锁屏/App/手动显式确认起床）
```

暂停只允许发生在 chatting 或 checkingIn，并冻结该阶段静默计时；恢复时补偿暂停时长。打开 App 不会静默填写起床时间，超过 10 小时还会发出 `wakeAutofillSuppressed`。真实音频检测、系统时钟调度和通知动作由壳层负责。

## 测试 seam

- **主 seam**：SleepMateCore 公共类型、事件和协议。XCTest 通过事件序列、fake clock 和 fake adapter 观察外部状态与 effect，不测试私有实现。
- **设备 seam**：AVAudioSession、麦克风、扬声器回声、锁屏/后台、系统中断、权限和网络。Foundation 只提供协议与清单；真实行为按 [`test-matrix.md`](test-matrix.md) 在真机验收。

## Foundation 之外

真实 OCR/ASR/LLM/TTS、声音克隆、VAD/AEC、素材导入 UI、云端数据、删除传播、权限请求、后台音频、睡眠总结和 App Store 合规接线，必须在后续独立 spec 中实现，并继续保持上述协议与 seam 边界。
