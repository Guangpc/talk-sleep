# 03: iOS 壳工程

What to build: Xcode app target 链接域核心，SwiftUI 启动到空'AI 好友'列表（AI 徽标占位，zh-Hans/en 本地化壳），作为 PRD §7.3 列表表面的起点。

Blocked by: 02 (域核心 Swift Package 脚手架)

Status: resolved

- [x] 模拟器 destination 下 xcodebuild 编译通过
- [x] App 实现空'AI 好友'列表与 AI 徽标占位，并接入 XCUITest 启动断言（实际 UI launch 待 simulator runtime）
- [x] zh-Hans/en 本地化壳存在且默认随系统语言

## Answer

已创建 SwiftUI iOS 壳、共享 SleepMate scheme、本地化资源、AI 好友空态和 XCUITest 启动断言；`xcodebuild` 的 generic iOS Simulator test build 通过。当前机器没有可启动的 Simulator runtime，因此 UI launch 尚未实际运行。
