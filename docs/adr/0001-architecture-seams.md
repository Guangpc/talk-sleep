# ADR-0001: 域核心平台无关 + 双测试 seam

状态：Accepted（由 Foundation spec 决策）。

## 背景

PRD §9.1 推荐"本地轻量 VAD/AEC + 有效语音片段上传 + 云端 ASR/LLM/TTS"。产品核心可测逻辑（素材流水线、睡眠状态机、10 小时/30 天/3 分钟规则）不应与 iOS 音频硬件耦合；否则 PRD 的 F-1xx/F-2xx 验收只能靠真机人工验证。

## 决策

1. **分层**：iOS App 壳（SwiftUI，承载权限/音频/UI/锁屏/通知 seam）与平台无关的域核心 Swift Package（不 import AVFoundation/Speech/UIKit）。
2. **通信**：壳与域核心只经显式协议接口（AudioSession / ASR / TTS / 素材分析 / 存储）通信；域核心定义契约，真实实现由壳或后端注入。
3. **gateway edge**：OpenAI/MiniMax gateway clients may live beside Core contracts as Foundation-only edge adapters for deterministic injection, but they call only the app-facing gateway and carry no provider API keys. Device frameworks remain outside Core, and provider adapters remain server-only.
4. **时间**：域核心所有时间规则经注入 Clock 驱动，禁用真实 sleep。
5. **双 seam（折中记录）**：理想是一个 seam；但音频是设备绑定能力无法并入纯逻辑 seam，故：
   - Seam 1（主）：域核心纯逻辑接口 —— 单元测试处。
   - Seam 2：真机音频/系统矩阵 —— 以 `docs/test-matrix.md` 文档化手动发布门，不做单测伪装。
6. **常量集中**：9:30/0:30/10h/30 天/3 分钟等集中为可注入常量表，测试可覆盖默认值。

## 后果

- 正面：状态机可无设备全量测试；后端/壳可替换；gateway edge 可用 fake transport 测试；后续 feature spec 复用 seam 与类型。
- 代价：壳层启动验收仍需 xcodebuild + 真机；域核心与壳之间需要少量适配代码；Foundation gateway edge 仍需严格保持 app-token-only，未来可按构建规模拆成独立 target。
- 后续若增加"素材分析远程化"，契约扩展只在协议层，不侵入状态机。
