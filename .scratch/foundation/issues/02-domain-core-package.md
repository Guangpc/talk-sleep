# 02: 域核心 Swift Package 脚手架

What to build: 建立平台无关的域核心 Swift Package，能 swift build 与 swift test，并提供本地命令文档，让所有后续域逻辑有可测试落点。

Blocked by: None (can start immediately)

Status: resolved

- [ ] swift build 通过
- [ ] swift test 通过（含一个冒烟测试）
- [ ] 本地命令（build/test）写入 AGENTS.md 供 agent 复用

## Answer

已创建 SleepMate Swift Package，完成冒烟测试的 red→green，并验证 swift build 与 swift test。
