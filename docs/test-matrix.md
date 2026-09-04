# 真机验收矩阵（Seam 2 发布门）

来源：PRD §15.1 / §15.2。任何含音频/麦克风/后台行为的版本在发布（含 TestFlight）前，必须在此矩阵上人工跑通并记录结果。本清单是 seam 2 的验收证据，不做单测伪装。

## 运行说明

- 每行一场景；结果列填 `PASS` / `FAIL` / `N/A`，FAIL 需附缺陷号。
- 覆盖设备：新款 iPhone + 最低支持机型各一台；iOS：当前 + 最低支持版本。
- 记录日期/设备/系统版本/构建号。

## 已执行记录

### 2026-09-03 · iPhone 12（iPhone13,2）· iOS 18.5

- **安装与启动：PASS**：`com.sleepmate.app` 使用 Team `CBDC2P58X3` 签名，`devicectl` 安装和启动成功。
- **麦克风允许：PASS**：系统权限弹窗可通过，App 显示“正在聆听”。
- **Speech 转写：PASS**：中文正常完成实时转写。
- **本地语音回复：历史 PASS（已替换）**：旧 tracer 曾用 `AVSpeechSynthesizer`；当前实现改为 gateway 返回音频后由 `AVAudioPlayer` 播放，尚未完成真机 AI 回归。
- **普通音量打断：PASS（3/3）**：自适应 RMS speech gate + voice processing/AEC 修复固定阈值问题，用户以平时音量在朗读中发言，3 次均立即停止朗读并继续转写。
- **Speech 输入 gate：已实现，设备复测待补**：校准/静音帧不送 Apple Speech；有效语音帧和短尾音才进入识别请求。
- **自动化限制**：同一设备上的 XCUITest Runner 曾因 `Timed out while enabling automation mode` 失败；这不影响上述签名构建、安装和手动设备 smoke，后续需单独恢复 automation mode 后再跑 UI 矩阵。

以下结果只代表本条记录实际执行过的场景；其余矩阵项仍保持未验证。

## 当前导入闭环自动验证（2026-09-04）

- `server`：`npm test` 49/49；包含真实 `createServerFromEnv` 的 MiniMax upload→clone composition test；另有一次真实本地 gateway smoke，OpenAI SSE 与 MiniMax TTS 均 HTTP 200，未输出 provider key。
- `SleepMateCore`：`swift test` 49/49；覆盖 LLM SSE client、MiniMax gateway TTS、授权 source validator、upload→clone client、LLM→TTS reply pipeline、空/不完整回复防 fake success。
- iOS 工程：`xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 与 generic `build-for-testing` 成功；真实 iPhone AI 会话、实际文件 picker/clone、锁屏/中断和 provider-side 声音生命周期仍是发布门。


## 设备与系统矩阵

| 场景 | 通过标准 | 结果 |
|---|---|---|
| 新款 iPhone · 前台会话 | 自动监听→ASR→AI 朗读 正常 | 部分 PASS：真实麦克风→Apple Speech→待配置 gateway 的 AI pipeline；真实 iPhone LLM→MiniMax 回归待补 |
| 最低支持 iPhone · 前台会话 | 同上，无卡顿/过热 | ☐ |
| 锁屏（播放继续） | AI 朗读在锁屏后继续 | ☐ |
| 锁屏（采集/监听） | 锁屏后仍能检测到用户发言 | ☐ |
| App 退到后台 | 在允许的系统条件下，主动会话状态与播放/监听行为符合设计；被系统中断时可理解提示 | ☐ |
| 进程被系统回收后恢复 | 提示会话被中断，已完成文字保留，可重新开始 | ☐ |
| 来电 / 闹钟 / 系统音频抢占 | 中断被处理，恢复不丢已确认文字 | ☐ |
| 低电量 | 无崩溃，状态可恢复 | ☐ |

## 音频与场景矩阵

| 场景 | 通过标准 | 结果 |
|---|---|---|
| 扬声器低/中/高音量 | 播放正常，无爆音 | ☐ |
| 安静房间 | 无 VAD 误触发 | ☐ |
| 风扇 / 电视 / 空调噪声 | 不当作有效用户语音上传 | ☐ |
| 室友/他人说话 | 不重置 9:30 睡眠计时（需结合 AEC+说话人判定实测） | ☐ |
| 咳嗽 / 翻身 / 清嗓 | 不重置计时、不触发 ASR | ☐ |
| AI 播放中用户打断（开头/中段/结尾） | 立即降音停止 TTS，保留已显示文字，优先处理新发言 | 代码路径已接入 `AVAudioPlayer.stop` + pipeline cancellation；真机开头/中段/结尾及普通音量回归待补 |

## 语言与交互矩阵

| 场景 | 通过标准 | 结果 |
|---|---|---|
| 中文 / 英文 / 中英混合 | 均可识别与回复 | 部分 PASS：中文；英文/混合待测 |
| 口音 / 轻声说话 | 可识别或优雅失败并可重试 | ☐ |
| 语音指令"用中文回答/用英文回答" | 仅改变 AI 回答语言 | ☐ |

## 网络矩阵

| 场景 | 通过标准 | 结果 |
|---|---|---|
| Wi-Fi / 蜂窝 | 会话正常 | ☐ |
| 弱网 | 保留会话、可重试、不生成假装听懂的回复 | ☐ |
| 断网→恢复 | 会话状态保留并可继续 | ☐ |

## 权限矩阵

| 场景 | 通过标准 | 结果 |
|---|---|---|
| 麦克风允许/拒绝/撤回 | 拒绝时提示并引导系统设置；不切换到点击说话 | 部分 PASS：允许；拒绝/撤回待测 |
| Speech 允许/拒绝/撤回 | 与麦克风独立处理 | ☐ |
| 相册权限 | 只读所选内容，遵循系统选择器行为 | ☐ |
| 录音指示 | App 内显示"正在聆听/已暂停/已结束"；系统麦克风指示可见 | 部分 PASS：App 状态与采集已验证；系统指示未单独记录 |

## 数据与合规抽查

| 场景 | 通过标准 | 结果 |
|---|---|---|
| 抓包 | 静音帧与无效环境音未上传 | ☐ |
| 改进产品授权撤回 | 不再上传训练数据 | ☐ |
| 删除 AI 好友 | 派生配置/索引/缓存删除状态可验证 | ☐ |
| 30 天自动过期 | 聊天文字与总结按默认保留期限过期，过期后不可从历史恢复 | ☐ |
| 重装 App / 恢复本地状态 | 按产品设计验证本地记录与删除状态，不意外恢复已删除内容 | ☐ |
| 导出 | Markdown/纯文本可用 | ☐ |
