# 06: 状态机 A 素材流水线（纯逻辑）

What to build: 实现素材处理流水线：导入→OCR/转写→说话人区分→低置信度确认挂起→生成声音配置/风格摘要/候选记忆→可聊天；注入处理器协议 + fake，可追溯 F-003/F-004/F-006。

Blocked by: 04 (域类型与可注入常量)

Status: resolved

- [x] swift test 覆盖 素材→可聊天 完整路径（F-003）
- [x] swift test 覆盖 低置信度时挂起等待用户确认（F-004）
- [x] swift test 覆盖 生成结果含声音配置/风格摘要/候选记忆

## Answer

已实现唯一 `MaterialAnalysisService` seam、可观察素材阶段、低置信度确认、候选记忆显式选择和 AI 好友生成路径，并通过 4 个流水线测试。
