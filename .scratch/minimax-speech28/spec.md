# MiniMax Speech 2.8 音色复刻与 TTS

## 目标

使用 MiniMax Speech 2.8 完成从测试音色到经授权的朋友音色复刻，再将生成音频安全地送回 iPhone 播放；该 feature 不负责生成对话文字。

## 官方接口事实

根据 [MiniMax 音色快速复刻官方文档](https://platform.minimax.cn/docs/guides/speech-voice-clone)：

- 待克隆音频支持 `mp3`、`m4a`、`wav`，时长至少 10 秒、最长 5 分钟，大小不超过 20 MB。
- 可选示例音频用于增强克隆效果，时长小于 8 秒，大小不超过 20 MB。
- 流程是上传待克隆音频获取 `file_id`，可选上传示例音频获取 `prompt_audio`，再调用快速复刻接口生成自定义 `voice_id`，最后使用该 `voice_id` 调用语音合成。
- 官方示例出现了 `speech-2.8` 和 `speech-2.8-hd` 两种模型写法，必须以实际账号和 API reference 验证结果为准。
- API Key 只能放服务端环境变量，不能放进 iOS App。

## 隐私和授权边界

- 真实朋友的声音只能在用户确认其有权使用、用途和云端处理后上传；没有授权的录音只能用于本地格式/时长测试，不能调用真实复刻。
- AI 好友必须明确标记为 AI，不声称自己就是现实中的朋友。
- 原始音频、`file_id`、`voice_id`、合成缓存和供应商侧资产必须有生命周期和删除策略；删除能力不明确时不能宣称完整删除。
- 页面必须明确 MiniMax 云端处理、可能的区域/网络传输、保留/训练政策和失败状态。

## 期望数据流

```text
授权确认
  → 音频格式/时长/大小校验
  → 服务端 gateway 上传
  → MiniMax voice_clone
  → voice_id / VoiceConfiguration
  → Speech 2.8 合成
  → iPhone 播放
```

## 当前基线

已有真实麦克风、Apple Speech、VAD gate、voice processing/AEC、系统 TTS、普通音量打断和 `VoiceSessionCoordinator`。MiniMax adapter 必须接入现有 stop/cancel seam，不能绕过打断逻辑。

## 非目标

- 不把 Speech 2.8 当作 LLM；文字回复见独立 `openai-next-llm` feature。
- 不在 iOS 直连 MiniMax 或嵌入 API Key。
- 不在没有授权和删除策略的情况下上线真实朋友音色。
- 不在本 feature 中承诺锁屏/后台持续采集。

## 完成定义

先用测试音色完成真实远端 TTS 播放和打断，再用明确授权的音频完成 voice_id 复刻、预览和可撤销绑定；所有 provider 错误和数据生命周期均可见。
