# SleepMate 最小 AI 好友闭环接入指南

这份指南描述当前可运行的最小闭环：用户在 iOS 端输入好友文字资料，或在明确授权后选择一段朋友声音；App 只把 app-to-gateway token 发送给本地/部署 gateway，gateway 再访问 OpenAI-compatible LLM 和 MiniMax Speech 2.8。provider API keys 永远留在 server runtime。

## 1. 启动 gateway

从仓库根目录执行：

```sh
node server/index.mjs
```

server 从环境变量或被 Git 忽略的 `.env.local` 读取：

```text
OPENAI_NEXT_API_KEY=<server only>
MINIMAX_API_KEY=<server only>
SLEEPMATE_GATEWAY_TOKEN=<app-to-gateway token>
```

不要把 `.env.local` 复制到 App bundle、Xcode scheme、日志或 GitHub。新 token 应使用本地 secrets wizard 生成/轮换。

## 2. App gateway 配置

App 在“文字与文件”页面直接提供 Gateway 配置卡。填写：

```text
Gateway URL=http://127.0.0.1:8787
App token=<与 server runtime 的 SLEEPMATE_GATEWAY_TOKEN 一致>
```

保存后 URL 放入 UserDefaults，App token 放入 Keychain（`AfterFirstUnlockThisDeviceOnly`），页面不会回显 token。后续画像分析、好友创建、voice clone 和对话都会从同一配置快照创建 gateway client。

Xcode Scheme 环境变量仍作为开发备用：

```text
SLEEPMATE_GATEWAY_URL=http://127.0.0.1:8787
SLEEPMATE_GATEWAY_TOKEN=<app-to-gateway token>
SLEEPMATE_LLM_MODEL=gpt-5.6-sol
SLEEPMATE_LLM_REASONING=medium
SLEEPMATE_VOICE_ID=<可选 stock/test 或已绑定 voice id>
```

文字-only 好友创建默认使用 stock/test voice reference，不要求先克隆声音。`OPENAI_NEXT_API_KEY` 与 `MINIMAX_API_KEY` 只能存在于 gateway server runtime。

## 3. iOS 导入顺序

1. 输入好友名称。
2. 在文字框输入聊天记录/说明，或导入 UTF-8 text file。
3. 点击“总结聊天风格与记忆”；profiling `xhigh` 针对指定好友提取内容摘要、风格、口头禅、习惯、重要地点、重要经历和偏好话题。
4. 检查并编辑候选好友画像；点击创建即确认把编辑后的内容作为对话 context。原始文字或目标好友名称改变时旧分析自动清除，需重新总结。
5. 可选选择 `mp3`、`m4a` 或 `wav`；选择只在本地读取和测量，不要求事先授权，也不会上传。
6. 仅当音频为 10 秒至 5 分钟且不超过 20 MiB 时才通过本地校验。上传前必须阅读说明并明确确认有权使用该声音。
7. 点击创建：有音频时 App 先上传 `voice_clone` 文件，再调用 clone route；成功后才绑定返回的 voice ID。
8. 点击开始 AI 对话：Apple Speech ASR 在尾部静音后结束当前 input → OpenAI SSE → MiniMax TTS → AVAudioPlayer。

没有 audio 时，文字资料只作为 context/style 素材，并使用预配置的 stock/test gateway voice ID；文字本身不会也不能假装生成 custom voice ID。没有任何文字或 voice binding 时，创建会被拒绝。

## 4. App-facing route contract

所有以下 POST 请求都必须带：

```http
Authorization: Bearer <SLEEPMATE_GATEWAY_TOKEN>
Content-Type: application/json
```

### LLM

`POST /v1/llm/chat`

```json
{
  "model": "gpt-5.6-sol",
  "reasoningEffort": "medium",
  "messages": [{"role": "user", "content": "你好"}]
}
```

响应是 normalized SSE；客户端消费 `type=text`，只有收到 `type=done` 才会进入 TTS。

### TTS

`POST /v1/tts/synthesize`

```json
{"model":"speech-2.8-hd","voiceId":"<bound voice id>","text":"你好"}
```

响应只包含 gateway 音频 base64、格式和可选 sample rate，不包含 provider response。

### voice source upload

`POST /v1/tts/upload`

```json
{
  "purpose": "voice_clone",
  "filename": "friend.m4a",
  "durationSeconds": 12,
  "audioBase64": "<bounded base64>"
}
```

gateway 只接受 `voice_clone` / `prompt_audio`，校验扩展名、base64、大小和已验证时长；成功只返回 `{ "fileId": "..." }`。

### voice clone

`POST /v1/tts/clone`

```json
{
  "fileId": "<uploaded file id>",
  "voiceId": "<requested binding id>"
}
```

成功只返回 `{ "voiceId": "..." }`。MiniMax 的 provider-specific `clone_prompt`、provider file IDs 和 credentials 不经过 App-facing interface。

## 5. 稳定错误与取消

客户端只依赖稳定错误码，例如 `gateway_unauthorized`、`invalid_request`、`provider_timeout`、`provider_rate_limit`、`provider_unavailable`、`provider_malformed_response` 和 `cancelled`。provider 原始 body 不会返回给 App。用户打断、暂停、结束或网络取消时，pending LLM/TTS 不应继续播放或覆盖新 turn。

## 6. 现在不宣称的能力

当前没有完成声音来源的真实授权证明、provider-side 删除传播、好友 profile/确认记忆持久化、离线重试策略、句子级流式 TTS、锁屏/后台音频和本轮 picker/静默结束修复的真机回归。真机验证步骤留给设备可用时执行；自动测试结果见 [`test-matrix.md`](test-matrix.md)。
