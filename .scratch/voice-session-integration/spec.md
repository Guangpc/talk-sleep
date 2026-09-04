# Real AI voice-session integration

## 目标

将两个已独立验收的 provider feature 组装成完整的 AI 好友语音会话：真实 ASR、真实 LLM、MiniMax Speech 2.8 TTS 和现有普通音量打断能力贯通。

## 依赖

- `openai-next-llm` 完成真实 LLM 文字回复、上下文、持久化和取消边界。
- `minimax-speech28` 完成 MiniMax TTS 播放、授权 voice_id、缓存和打断边界。

## 期望数据流

```text
有效麦克风语音
  → Apple Speech ASR
  → openai-next-llm
  → AI 文字回复
  → minimax-speech28 voice_id
  → MiniMax Speech 2.8
  → iPhone 播放
  → 普通音量打断
```

## 非目标

- 不重新实现任一 provider feature 内部逻辑。
- 不绕过服务端密钥隔离、授权确认、AI 标识或删除策略。
- 不在本票中增加锁屏/后台持续采集。
