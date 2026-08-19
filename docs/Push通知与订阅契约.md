# Push 通知与订阅契约

## 当前边界

Push 注册和 Mastodon Web Push 订阅属于生产链路。

- `PushRegistrationCenter` 管理系统通知授权、APNs device token 和 relay endpoint。
- `PushSubscriptionCoordinator` 在登录会话与 device token 可用后自动检查当前订阅；endpoint 不匹配或订阅缺失时重新创建。
- Web Push 的 `p256dh` 与 `auth` 密钥由 `WebPushKeyStore` 提供。
- `moroNotificationService` 从共享 Keychain 读取 Web Push 密钥，解密 relay 转发的 payload，改写通知内容并按 session 聚合 badge。
- `NotificationSettingsView` 读取现有订阅，并把通知类型和 policy 的变化经过防抖同步到服务器；应用内过滤仍即时生效。
- 自动绑定失败不会阻塞登录或启动，会记录日志并在后续激活时重试。

## API 边界

- `GET /api/v1/push/subscription`：读取当前订阅。
- `POST /api/v1/push/subscription`：创建订阅或替换旧 endpoint。
- `PUT /api/v1/push/subscription`：更新 alerts 与 policy。
- `DELETE /api/v1/push/subscription`：删除订阅。

## 生命周期契约

1. App 获取通知授权并注册远程通知。
2. APNs token 转为稳定的十六进制值。
3. 当前会话和 token 共同生成订阅去重 key，并生成对应 relay endpoint。
4. 若服务器订阅已指向该 endpoint，则不重复创建；否则使用当前 Web Push 密钥重新绑定。
5. Notification Service 收到密文后完成本地解密与 badge 聚合，不读取 Mastodon access token。
6. 用户修改通知设置时，仅在订阅存在后同步服务器；同步失败保留本地设置，并等待后续变化或激活重试。

## 验证重点

- 新安装、拒绝授权、稍后授权与系统设置重新开启。
- APNs token 变化、账号切换、退出后回退到另一账号。
- 已存在正确 endpoint 时不重复创建；旧 endpoint 能被替换。
- alerts / policy 更新失败不会覆盖本地设置，也不会阻塞应用内通知列表。
- Release 构建具备正确 Push entitlement，relay 服务可用，并能在真机完成端到端到达验证。
- 密文无法解密、重复通知 ID 和 Extension 即将超时时均能安全回退到 best-attempt 内容。

## 实现入口

- `moro/Core/Services/PushRegistrationCenter.swift`
- `moro/Core/Services/PushSubscriptionCoordinator.swift`
- `moro/Core/Services/WebPushKeyStore.swift`
- `moroNotificationService/NotificationService.swift`
- `moro/Modules/Settings/NotificationSettingsView.swift`
- `moro/Core/API/MastodonClient.swift`
