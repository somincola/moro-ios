# Widget 架构与安全边界

Moro 提供四种 Widget。概览、快捷操作和个人资料卡从 App Group 读取快照。治愈花园直接显示扩展内置的插画，可以离线常驻桌面。

## Widget

| Kind | 用途 |
|---|---|
| Overview | 活动账号与 Inbox 未读概览 |
| Quick Actions | Home、Compose、Search、Inbox、Profile 快捷入口 |
| Profile Card | 当前账号身份与基础统计 |
| Comfort | 小号展示「叶下小象」，中号展示「雨林漫步」，轻点进入首页 |

Widget kind 由 `MoroWidgetKind` 统一定义，避免 target 与主 App 使用不同字符串。

## 快照边界

`MoroWidgetDataSnapshot` 只包含 session ID、公开账号资料、合并后的未读数和更新时间。头像缓存单条上限为 3 MB，并校验来源 URL。

- 不保存访问令牌、OAuth client secret、草稿、私信正文或完整通知内容。
- 数据缺失或过期时显示稳定占位/空态，不尝试绕过主 App 更新。
- 多账号切换后，快照必须指向新的活动 session；退出时移除旧账号数据。

## 交互与刷新

- Widget 操作写入 `MoroWidgetHandoff` 或通过 App Intent 打开主 App。
- handoff 由主 App 一次性消费，先恢复目标账号，再路由到目的地。
- Timeline refresh 只用于反映已有快照变化；不得用高频刷新模拟实时客户端。
- Widget 与主 App 使用相同的本地化语义和可访问性标签，但保持适合 Widget 的信息密度。

## 验证

- 无登录、账号切换、退出和共享数据损坏时均不崩溃。
- 小、中尺寸以及浅色、深色、Dynamic Type 下无裁切。
- Quick Action 分别到达正确根入口，重复 handoff 不会二次跳转。
- Extension entitlements 与 App Group identifier 一致。
- 静态检查确认 Widget 目标不链接或读取 Keychain token。

## 实现入口

- `moroWidgetShared/MoroWidgetSharedStore.swift`
- `moroWidgetShared/MoroWidgetIntents.swift`
- `moroWidgets/MoroWidgetsBundle.swift`
- `moroWidgets/MoroWidgetProvider.swift`
- `moroWidgets/MoroOverviewWidget.swift`
- `moroWidgets/MoroQuickActionsWidget.swift`
- `moroWidgets/MoroProfileCardWidget.swift`
- `moroWidgets/MoroComfortWidget.swift`
