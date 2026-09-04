# SleepMate 本地 Gateway Runbook

## 快速启动

1. 确认本地 `.env.local` 权限为 `600`，且未被 Git 跟踪；不要在终端打印其内容。
2. 从仓库根目录运行 `node server/index.mjs`。
3. 另开终端执行 `curl --fail http://127.0.0.1:8787/health`，只确认 `{"ok":true}`。
4. 在 Xcode Scheme 中只注入 `SLEEPMATE_GATEWAY_URL`、`SLEEPMATE_GATEWAY_TOKEN`、可选 model/reasoning/voice 配置。

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
- App 显示 gateway unavailable：检查 URL、App token、voice binding；未知 model/profile、live `xhigh` 和缺少 voice binding 都会拒绝启用。
- 音频无法播放：确认 gateway 返回非空 MP3，并检查 `AVAudioSession` route；这项需要真机补验。

## 发布前仍需人工执行

在连接的 iPhone 上补做：授权音频真实导入、clone 成功后的 TTS、重复 turn、普通音量打断、系统来电/耳机/锁屏/后台、超时重试、删除传播和无 provider key 的 bundle 检查。当前自动 build 不能替代这些门。
