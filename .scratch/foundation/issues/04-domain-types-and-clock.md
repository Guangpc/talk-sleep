# 04: 域类型与可注入常量

What to build: 定义 PRD §6 域类型（AI 好友配置/素材条目/转写片段/会话 Turn/睡眠记录/风格摘要/记忆）、Clock 协议与集中常量表（9:30/0:30/10h/30 天/3 分钟单段），时间相关验收可用 fake clock 测试。

Blocked by: 02 (域核心 Swift Package 脚手架)

Status: resolved

- [x] 新增类型编译通过
- [x] Clock 协议与常量表可注入
- [x] swift test 覆盖常量默认值

## Answer

已实现域类型、Clock 协议与产品时长常量，并通过 6 个域类型测试。
