# SleepMate 本地 Gateway Runbook

## 快速启动

1. 确认本地 `.env.local` 权限为 `600`，且未被 Git 跟踪；不要在终端打印其内容。
2. 从仓库根目录运行 `node server/index.mjs`。
3. 另开终端执行 `curl --fail http://127.0.0.1:8787/health`，只确认 `{"ok":true}`。
4. 在 App“文字与文件”页的 Gateway 配置卡中填写 URL 与 App token，或在 Xcode Scheme 中注入同名环境变量；App token 会保存在 Keychain，provider keys 绝不进入 App。

## 自动验证

```sh
(cd server && npm test)
swift test
xcodebuild build-for-testing \
  -project SleepMate.xcodeproj \
  -scheme SleepMate \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## 最小 gateway smoke

不要把 key/token 写进 shell history。使用本地安全环境加载后，只打印 HTTP status 和脱敏结果字段：

- `/v1/llm/chat`：HTTP 200、至少一个 normalized text event、done event。
- `/v1/tts/synthesize`：HTTP 200、音频存在、格式为 `mp3`、sample rate 合法。
- `/v1/tts/upload`：只用专门的测试音频，HTTP 200 后只保留 file ID。
- `/v1/tts/clone`：只用已获授权的测试素材，HTTP 200 后只保留 voice ID。

## 故障排查

- `401 gateway_unauthorized`：检查 App token 是否与 server runtime 的 `SLEEPMATE_GATEWAY_TOKEN` 完全一致；不要尝试把 provider key 放入 App。
- `400 invalid_request`：检查 model/reasoning、消息格式、音频扩展名、base64、大小和时长。
- `502 provider_*`：只根据稳定 code 判断；查看 server 运行状态和 provider 控制台，不打印 provider body。
- App 显示 gateway unavailable：先确认 `curl --fail http://127.0.0.1:8787/health` 成功，再检查 Gateway 配置卡中的 URL 和 App token 是否与 `.env.local` 的 `SLEEPMATE_GATEWAY_TOKEN` 一致。文字-only 创建不要求自定义 voice ID。
- 点击“选择朋友声音”没有 picker：选择本地文件不再要求预先勾选授权；确认运行的是包含 `friend-audio-import-button` 的新构建。授权仍在上传/clone 前强制校验。
- 导入聊天记录后没有画像：点击“总结聊天风格与记忆”，检查 gateway 可达；该请求使用 profiling `xhigh`，结果成功后会显示可编辑摘要。
- 停止说话仍一直监听：确认 VAD `speechEnded` 已触发 Apple Speech `endAudio()`；若 terminal callback 缺失，1.5 秒 fallback 应使用最后一个非空 partial。随后 UI 应进入 processing 且麦克风暂停；失败后应恢复 listening。本轮代码修复仍需真机复测。
- 音频无法播放：确认 gateway 返回非空 MP3，并检查 `AVAudioSession` route；这项需要真机补验。

## 发布前仍需人工执行

在连接的 iPhone 上补做：无预授权点击后 document picker 呈现、聊天摘要预览、尾部静音触发回复、授权音频真实导入、clone 成功后的 TTS、重复 turn、普通音量打断、系统来电/耳机/锁屏/后台、超时重试、删除传播和无 provider key 的 bundle 检查。当前自动 build 不能替代这些门。
