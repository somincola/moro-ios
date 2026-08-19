# 认证与 URL 回调

Moro 使用 Mastodon OAuth、`ASWebAuthenticationSession`、PKCE 和 CSRF state 完成登录。默认回调为 `moro://oauth/callback`。

## 登录流程

```text
输入实例
  -> HTTPS 标准化并校验实例
  -> 复用或注册 OAuth App
  -> 生成 state + PKCE verifier/challenge
  -> ASWebAuthenticationSession
  -> 校验 moro://oauth/callback 的 code + state
  -> 使用 code + verifier 换取 token
  -> verify_credentials
  -> AccountSessionStore / Keychain 持久化并激活账号
```

- OAuth app 按实例缓存；redirect URI 或 scopes 改变时重新注册。
- 浏览器会话使用临时模式，用户取消属于可恢复结束，不显示伪造的认证失败。
- token 交换成功但 `verify_credentials` 失败时，不得保存不完整 session。

## URL Scheme 所有权

- Xcode target 的 URL Types 必须声明 scheme `moro`。
- OAuth callback 只由 `MastodonAuthenticationController` 的 `ASWebAuthenticationSession` 消费。
- 普通内部导航、Widget 与 Push handoff 通过各自的结构化入口进入 `RootTabCoordinator` / `AppRouter`，不把 OAuth callback 当通用深链路由。
- callback 缺少 code、state 不匹配或 scheme/path 不正确时安全终止，不继续 token 交换。

## 安全规则

- 实例输入默认提升为 HTTPS；不允许把 token 发往回调中提供的任意 host。
- `state` 每次授权生成并严格匹配，PKCE 使用 S256；verifier 在交换后立即清理。
- access token、client secret、authorization code、state 和 verifier 不进入日志、文档或 UserDefaults。
- token 与每个账号 session 绑定并保存在 Keychain；账号切换不得复用错误实例的 client。
- scopes 当前为 `read write follow push`，变更时同时检查功能、缓存的 OAuth app 和 App Review 说明。

## 恢复与错误

- 启动恢复逐个验证 Keychain session 的可解码性，活动账号失效时选择安全回退。
- 用户取消、网络失败、服务器拒绝、state 不匹配和凭证验证失败应呈现不同的可恢复结果。
- 移除账号时清理其 token、共享快照、未读状态和账号级缓存。

## 验证

- 合法域名、带 scheme 域名、非法输入和不可达实例。
- 首次注册、缓存复用、scopes/redirect 改变后的重新注册。
- 用户取消、callback 缺 code、state 不匹配、token 交换失败、verify credentials 失败。
- 多账号登录、冷启动恢复、切换和移除。
- 发布配置中的 URL Types、Associated targets 和 Keychain/App Group entitlements。

## 实现入口

- `moro/Core/API/AuthService.swift`
- `moro/Core/API/MastodonAuthenticationController.swift`
- `moro/Core/Store/AccountSessionStore.swift`
- `moro/Core/Store/KeychainService.swift`
- `moro/Core/Models/OAuthModels.swift`
- `moro/Modules/Auth/`
