# Push 通知与订阅契约

## 当前边界

Push 注册和 Mastodon Web Push 订阅属于生产链路。

- `PushRegistrationCenter` 管理系统通知授权、APNs device token 和 relay endpoint。
- `PushSubscriptionCoordinator` 在登录会话与 device token 可用后自动检查当前订阅；endpoint 不匹配或订阅缺失时重新创建。
- Web Push 的 `p256dh` 与 `auth` 密钥由 `WebPushKeyStore` 提供。
- `moroNotificationService` 从共享 Keychain 读取 Web Push 密钥，解密 relay 转发的 payload，改写通知内容并按 session 聚合 badge。
- `NotificationSettingsView` 读取现有订阅，并把通知类型和 policy 的变化经过防抖同步到服务器；应用内过滤仍即时生效。
- `PushNotificationPayload` 只保留账号会话、通知 ID、类型和可选网页 URL；不会将密文、access token 或系统响应对象带入页面状态。
- `PushNotificationResolver` 使用通知所属账号解析目标；目标不可用时保留收件箱作为回退。
- 自动绑定失败不会阻塞登录或启动，会记录日志并在后续激活时重试。

## API 边界

- `GET /api/v1/push/subscription`：读取当前订阅。
- `POST /api/v1/push/subscription`：创建订阅或替换旧 endpoint。
- `PUT /api/v1/push/subscription`：更新 alerts 与 policy。
- `DELETE /api/v1/push/subscription`：删除订阅。
- `GET /api/v1/notifications/:id`：按通知 ID 获取具体通知及关联帖子/账号。通知 ID 不能作为帖子 ID 使用，也不能只在最新一页通知中查找。

## 生命周期契约

1. App 获取通知授权并注册远程通知。
2. APNs token 转为稳定的十六进制值。
3. 当前会话和 token 共同生成订阅去重 key，并生成对应 relay endpoint。
4. 若服务器订阅已指向该 endpoint，则不重复创建；否则使用当前 Web Push 密钥重新绑定。
5. Notification Service 收到密文后完成本地解密与 badge 聚合，不读取 Mastodon access token。
6. 用户修改通知设置时，仅在订阅存在后同步服务器；同步失败保留本地设置，并等待后续变化或激活重试。

## 点击系统通知

- 使用 `UNUserNotificationCenterDelegate` 的 completion handler 形式。系统回调可来自后台线程，先同步提取轻量字段，再到主线程记录待处理请求并完成系统回调；回调内不等待网络或页面跳转。
- 只处理系统默认点击动作；清除通知和未知自定义动作仅完成回调。
- 每次点击生成一个 UUID 请求。冷启动时先保留请求，等主界面和当前会话就绪、应用激活后再导航。连续点击时，新请求替换旧请求；旧任务不能消费或打开新请求的目标。
- 若存在发帖、设置或添加账号弹窗，等弹窗关闭后再处理，避免打断未完成的输入。
- relay 的 `x` 是 percent-encoded `StoredAccountSession.id`。另一已保存账号的通知先切换账号；账号已移除时只打开收件箱，不使用当前账号请求另一服务器的本地 ID。
- 先切换到收件箱的通知页并清空旧详情，再异步解析。通知未解密、字段缺失、通知已删除、服务端不支持接口和离线均不阻断进入应用。
- 有关联的普通帖子进入帖子详情；关注通知进入关注者主页；关注请求仍留在通知页，以保留批准/拒绝入口。
- 私信仅在会话的最后一条消息 ID 与目标消息完全匹配时进入会话；无法匹配时进入私信列表。不得仅凭发送者猜测会话。
- 推送包含可识别的 Mastodon 帖子 URL 时，通过当前服务器解析完整 URL 后进入原生详情。普通网页、无法解析的链接回退收件箱。
- 解析期间用户切换了页面、打开其他详情或开始编辑，不再强制拉回目标详情。

Mastodon 的标准推送包含 `notification_id`，不保证提供帖子 URL。可选 URL 只是补充，主路径以[通知详情 API](https://docs.joinmastodon.org/methods/notifications/#get-one)为准。

采用显式主线程 completion handler 是针对系统通知生命周期的兼容性加固；[Airship 19.11.0 的修复记录](https://github.com/urbanairship/ios-library/releases/tag/19.11.0)也记录了 async delegate 在后台线程完成所带来的生命周期问题。没有反馈设备的崩溃堆栈时，不将这个风险直接认定为其唯一根因。

## 验证重点

- 新安装、拒绝授权、稍后授权与系统设置重新开启。
- APNs token 变化、账号切换、退出后回退到另一账号。
- 已存在正确 endpoint 时不重复创建；旧 endpoint 能被替换。
- alerts / policy 更新失败不会覆盖本地设置，也不会阻塞应用内通知列表。
- Release 构建具备正确 Push entitlement，relay 服务可用，并能在真机完成端到端到达验证。
- 密文无法解密、重复通知 ID 和 Extension 即将超时时均能安全回退到 best-attempt 内容。
- `PushNotificationTests` 覆盖后台回调、主线程 completion、字段容错、账号请求保存、连续请求、通知详情查询、私信匹配、取消与回退。
- `PushNotificationUITests` 使用隔离的 DEBUG 传输和真实主界面验证启动时排队、跨账号切换、帖子 URL、异常回退，以及后台点击系统通知横幅。
- 本地通知用于验证同一系统点击回调，不替代真机 APNs → relay → 解密 → 点击的端到端验证。

2026-09-10 本地验证：iPhone 17 Pro / iOS 26.4 模拟器构建通过，`Moro-UnitTests` 512 项通过，`PushNotificationUITests` 5 项通过（含启动排队、返回收件箱、跨账号、URL、异常回退和系统横幅点击）。DEBUG 场景的注入由 `StateObject` 保证每次启动只执行一次，避免视图重建干扰返回检查。反馈设备的原始崩溃日志及生产 APNs 冷启动仍需真机复核；详见本地 `build/qa/push-notifications/verification.json`。

## 实现入口

- `moro/Core/Services/PushRegistrationCenter.swift`
- `moro/Core/Services/PushNotificationPayload.swift`
- `moro/Core/Services/PushNotificationResolver.swift`
- `moro/App/MainTabView.swift`
- `moro/App/RootTabCoordinator.swift`
- `moro/Core/Services/PushSubscriptionCoordinator.swift`
- `moro/Core/Services/WebPushKeyStore.swift`
- `moroNotificationService/NotificationService.swift`
- `moro/Modules/Settings/NotificationSettingsView.swift`
- `moro/Core/API/MastodonClient.swift`
