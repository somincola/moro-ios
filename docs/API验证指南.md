# API 验证指南

本文定义 Mastodon API 层的验证边界，不维护“已实现接口列表”。接口能力以 endpoint、client、model、service 和测试代码共同为准。

## 分层

```text
Feature / ViewModel
        ↓
Domain Service
        ↓
MastodonAPI / MastodonClient
        ↓
MastodonEndpoint / MastodonRequestBuilder
        ↓
URLSession + AuthInterceptor
```

- 页面不得直接拼接 Mastodon 路径或 Authorization header。
- Endpoint 描述 method、path、query/body；Client 负责发送、状态码和解码；Service 负责乐观更新、缓存与跨页面一致性。
- 服务器版本差异通过明确 fallback 表达，不使用静默吞错伪装成功。

## 必测类别

- 请求：method、路径转义、query、form/JSON body、分页参数、幂等 key 和 Content-Type。
- 响应：正常 payload、缺省字段、未知 enum、空 body、分页 link 和兼容 schema。
- 认证：无 token、token 注入、401/403、账号切换后的 client 隔离。
- 错误：非 2xx、Mastodon error body、解码失败、取消、超时与离线。
- 业务服务：乐观更新、失败回滚、迟到响应、重复点击、缓存重校准和 canonical status 同步。
- 写操作：精确验证发出的可见性、语言、媒体 ID、投票、引用策略；定时发布关闭时不得携带 schedule 参数。

## 测试策略

- 使用 URLProtocol 或可注入 transport 捕获请求并返回固定 fixture，不依赖公网实例。
- Fixture 只保存完成当前断言所需字段，敏感数据使用明显的测试值。
- 模型兼容测试覆盖旧字段缺失和服务端新增未知值。
- 实例实测只用于验证服务器差异，并使用专用测试账号；不得放入默认 CI。

## 验证顺序

1. Endpoint/request 单元测试。
2. Client 解码与错误映射测试。
3. Service/ViewModel 状态测试。
4. 需要时在模拟器验证用户可见错误、重试与取消。
5. 只有服务器兼容问题才进行受控实例实测。

## 实现入口

- `moro/Core/API/MastodonAPI.swift`
- `moro/Core/API/MastodonClient.swift`
- `moro/Core/Mastodon/MastodonEndpoint.swift`
- `moro/Core/Mastodon/MastodonRequestBuilder.swift`
- `moro/Core/API/AuthInterceptor.swift`
- `moro/Core/API/APIError.swift`
- `moro/Core/API/MastodonServerError.swift`
- `moroTests/`
