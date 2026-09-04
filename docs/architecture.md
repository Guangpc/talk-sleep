# SleepMate 架构

产品行为以 [`../PRD.md`](../PRD.md) 为准，架构取舍见 [`adr/0001-architecture-seams.md`](adr/0001-architecture-seams.md)。当前实现包含 Foundation 与一条真实 iOS 语音会话 tracer。

## 分层

```text
SwiftUI iOS App
  ├─ VoiceSessionView / VoiceSessionViewModel
  ├─ LiveSpeechAudioSession（AudioSession adapter）
  │    ├─ AVAudioSession + AVAudioEngine + voice processing/AEC
  │    ├─ Apple Speech 实时转写
  │    ├─ server gateway LLM/TTS clients
  │    └─ AVAudioPlayer 播放 gateway 音频
  └─ 权限、本地化与设备状态
                         │ Core 公共 interface
                         ▼
SleepMateCore（平台无关 Swift Package）
  ├─ PRD 域类型与产品时长常量
  ├─ FriendCreationPipeline
  ├─ SleepSessionStateMachine
  ├─ VoiceSessionCoordinator：状态 → effects
  ├─ FriendContextAnalysisPipeline：聊天记录 → 可编辑好友画像
  └─ VoiceActivityDetector：RMS 帧 → speech onset/end
```

`SleepMateCore` 的域模块不依赖 AVFoundation、Speech、UIKit 或持久化框架；其中的 gateway edge 仅使用 Foundation URLSession，访问 app-facing gateway，不接触 provider keys。Core 仍只经可观察的状态、事件、effects 和 adapter interface 表达业务；App 执行设备 I/O。

## 真实语音数据流

```text
麦克风
  → AVAudioEngine input tap
      ├─ RMS → VoiceActivityDetector → speech gate
      │                              ├─ 有效帧 → Apple Speech → 实时转写 → SwiftUI
      │                              ├─ userSpeechStarted（朗读中打断）
      │                              └─ speechEnded → endAudio → final transcript
                                           ↓
                                  VoiceSessionCoordinator
                                    ├─ listening → processing（暂停麦克风）
                                    ├─ stopPlayback / listeningResumed
                                    └─ processing → startPlayback(text)
                                           ↓
                                  VoiceReplyPipeline
                                    ├─ OpenAINextGatewayClient（SSE）
                                    └─ MiniMaxGatewayTTSService（音频）
                                           ↓
                                  AVAudioPlayer
```

`AVAudioSession` 使用 `.playAndRecord` + `.voiceChat` 并默认扬声器输出；输入节点启用 voice processing 以降低系统朗读回灌。`VoiceActivityDetector` 先估计环境底噪，再使用相对阈值和连续两帧确认 onset；只在 speech gate 打开后把有效帧送往 Speech，并保留短尾音，静音/校准/结束帧直接丢弃。这样替代容易迫使用户提高音量的固定阈值。检测逻辑是 Core 纯模块，真实音频帧和 AEC 属于 iOS adapter。尾部静音触发 `endAudio()`，优先等待 Apple Speech final transcript；若 1.5 秒内没有 terminal callback，则以 generation-safe fallback 提交最后一个非空 partial 或恢复监听。取得文本后才发出 `responseRequested`；LLM/TTS 失败通过 `responseFailed` 恢复监听，避免麦克风无限保持在 listening。

当前转写使用 Apple Speech；App 不保存原始音频，但识别可能依赖 Apple 网络服务。已配置 gateway 时，`VoiceReplyPipeline` 将同一轮转写和 history 发送到 server-side LLM，再将完整 AI 回复发送到 MiniMax gateway 并由 `AVAudioPlayer` 播放；gateway 未配置时只显示错误，不生成本地 fake 回复。

## 主要域模块

### AI 好友与素材

`AIFriendProfile` 包含用户自定义名称、头像引用、声音配置、可编辑风格摘要、已确认记忆、话题偏好和禁提主题。`FriendCreationPipeline` 接收 `MaterialAnalysisService`，把完整素材流水线表达为可观察阶段。当前文字路径由 `FriendContextAnalysisPipeline` 使用 app-facing LLM 的 profiling `xhigh`，针对指定好友提取内容摘要、风格、口头禅、习惯、重要地点、重要经历和偏好话题，并把结果作为可编辑候选资料；创建好友后该资料成为会话 system context。真实截图 OCR、素材音频 ASR 和可靠说话人区分仍未实现；音频路径继续使用 consent-gated clone → voice ID → TTS。

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

`VoiceSessionCoordinator` 的公共 interface 是 `handle(event) -> [effect]`，状态包括 idle、listening、processing、speaking、paused、ended。语音页进入后请求权限并自动开始 listening；TTS 中的 `userSpeechStarted` 或 pause 会先发出 `stopPlayback`；播放完成回到 listening 并发布 `listeningResumed`；结束后不再响应 resume。

## 测试 seams

- **Core seam**：XCTest 通过事件序列、fake clock 和 RMS 样本验证状态/effects；不测试私有实现。
- **iOS adapter seam**：generic `xcodebuild build-for-testing` 验证 AVFoundation/Speech 接线。
- **设备 seam**：真实权限、麦克风、Apple Speech、扬声器回声、打断、锁屏/后台和系统中断按 [`test-matrix.md`](test-matrix.md) 在真机记录；自动化构建不能替代这一层。

## 明确边界

当前仍不包含本地会话记录/terminal persistence、好友声音授权证明与 provider-side clone 删除传播、preview-confirm、TTS 缓存、完整后台音频、系统中断恢复、图片/音频素材分析、profile 持久化、云端数据、睡眠总结和 App Store 合规材料。后续实现必须保持 Core 纯逻辑 seam 与 iOS adapter seam；gateway 未配置或 provider 失败时不得把本地 tracer 文案描述为真实 AI 回复。
