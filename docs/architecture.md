# SleepMate 架构

产品行为以 [`../PRD.md`](../PRD.md) 为准，架构取舍见 [`adr/0001-architecture-seams.md`](adr/0001-architecture-seams.md)。当前实现包含 Foundation 与一条真实 iOS 语音会话 tracer。

## 分层

```text
SwiftUI iOS App
  ├─ VoiceSessionView / VoiceSessionViewModel
  ├─ LiveSpeechAudioSession（AudioSession adapter）
  │    ├─ AVAudioSession + AVAudioEngine + voice processing/AEC
  │    ├─ Apple Speech 实时转写
  │    └─ AVSpeechSynthesizer 本地朗读
  └─ 权限、本地化与设备状态
                         │ Core 公共 interface
                         ▼
SleepMateCore（平台无关 Swift Package）
  ├─ PRD 域类型与产品时长常量
  ├─ FriendCreationPipeline
  ├─ SleepSessionStateMachine
  ├─ VoiceSessionCoordinator：状态 → effects
  └─ VoiceActivityDetector：RMS 帧 → speech onset
```

`SleepMateCore` 不依赖 AVFoundation、Speech、UIKit、网络或持久化框架。Core 只表达可观察的状态、事件、effects 和 adapter interface；App 执行设备 I/O。

## 真实语音数据流

```text
麦克风
  → AVAudioEngine input tap
      ├─ RMS → VoiceActivityDetector → speech gate
      │                              ├─ 有效帧 → Apple Speech → 实时转写 → SwiftUI
      │                              └─ userSpeechStarted（朗读中打断）
                                           ↓
                                  VoiceSessionCoordinator
                                    ├─ stopPlayback
                                    ├─ listeningPaused/Resumed
                                    └─ startPlayback(text)
                                           ↓
                                  AVSpeechSynthesizer
```

`AVAudioSession` 使用 `.playAndRecord` + `.voiceChat` 并默认扬声器输出；输入节点启用 voice processing 以降低系统朗读回灌。`VoiceActivityDetector` 先估计环境底噪，再使用相对阈值和连续两帧确认 onset；只在 speech gate 打开后把有效帧送往 Speech，并保留短尾音，静音/校准/结束帧直接丢弃。这样替代容易迫使用户提高音量的固定阈值。检测逻辑是 Core 纯模块，真实音频帧和 AEC 属于 iOS adapter。

当前转写使用 Apple Speech；App 不保存原始音频，但识别可能依赖 Apple 网络服务。当前回复文本是本地 tracer 文案，朗读使用系统声音；LLM、好友声音 TTS 和声音克隆均未配置。

## 主要域模块

### AI 好友与素材

`AIFriendProfile` 包含用户自定义名称、头像引用、声音配置、可编辑风格摘要、已确认记忆、话题偏好和禁提主题。`FriendCreationPipeline` 接收 `MaterialAnalysisService`，把导入、OCR/转写、说话人区分、分析、确认和 profile 构建表达为可观察阶段。真实素材 OCR/ASR、说话人分析与声音生成尚未实现。

### 睡眠会话

`SleepSessionStateMachine` 是注入 `SleepMateClock` 的纯 reducer：

```text
chatting
  → checkingIn（无有效用户语音 9:30）
  → awaitingWakeConfirmation（再过 30 秒无回应）
  → completed（显式确认或编辑起床）
```

暂停冻结静默计时；超过 10 小时抑制静默自动填充。真实调度、锁屏、通知和中断处理仍在 App 后续切片。

### 语音会话

`VoiceSessionCoordinator` 的公共 interface 是 `handle(event) -> [effect]`，状态包括 idle、listening、speaking、paused、ended。语音页进入后请求权限并自动开始 listening；TTS 中的 `userSpeechStarted` 或 pause 会先发出 `stopPlayback`；播放完成回到 listening 并发布 `listeningResumed`；结束后不再响应 resume。

## 测试 seams

- **Core seam**：XCTest 通过事件序列、fake clock 和 RMS 样本验证状态/effects；不测试私有实现。
- **iOS adapter seam**：generic `xcodebuild build-for-testing` 验证 AVFoundation/Speech 接线。
- **设备 seam**：真实权限、麦克风、Apple Speech、扬声器回声、打断、锁屏/后台和系统中断按 [`test-matrix.md`](test-matrix.md) 在真机记录；自动化构建不能替代这一层。

## 明确边界

当前不包含生产 LLM、好友声音 TTS/克隆、完整后台音频、系统中断恢复、素材导入、云端数据、删除传播、睡眠总结和 App Store 合规材料。后续实现必须保持 Core 纯逻辑 seam 与 iOS adapter seam，并避免将本地 tracer 文案描述为真实 AI 回复。
