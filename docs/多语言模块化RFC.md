# 多语言模块化 RFC

## 决策

多语言能力继续作为仓库根目录 `Package.swift` 定义的 local Swift Package 产品 `MoroLocalization` 维护，不拆成独立仓库或 Git submodule。

## 当前边界

Package 内包含：

- `MoroL10n` 的类型安全 key 入口。
- 发帖语言的标准化与展示数据。
- 翻译服务的共享协议与实现。
- `moro/Resources/Localizations/Moro.xcstrings`。

App 目标继续负责：

- 设置页面、当前语言偏好和环境注入。
- Mastodon API 客户端、账号/实例状态和页面路由。
- 用户生成内容、服务器正文和实例返回文案的展示。

用户内容与服务器正文不是本地化资源，不能进入 String Catalog。API 错误应先映射为稳定的产品语义，再由资源 key 呈现。

## 依赖规则

- Package 不依赖 App target，也不读取 `AppState`、Keychain 或页面类型。
- App 通过 `MoroLocalizationExports` 等薄适配层消费 Package，避免复制 key。
- 新文案先定义语义 key，再补齐支持语言；不使用英文原文作为业务唯一标识。
- 发帖语言代码遵循协议值，展示名称和当前 UI 语言分离。

## 何时重新评估拆仓

只有同时出现多个独立产品消费、独立发布节奏或独立维护团队，并且跨仓版本治理收益大于集成成本时，才评估拆仓。单纯减少目录数量不构成理由。

## 验证

- String Catalog 不存在缺失 key、空翻译和意外回退。
- `MoroL10n` 引用与 catalog key 一致。
- 支持的发布语言代码去重且排序稳定。
- Package 可单独解析，App 与 Extension 构建不会隐式依赖未声明资源。

## 实现入口

- `Package.swift`
- `moro/Core/Localization/`
- `moro/Resources/Localizations/Moro.xcstrings`
- `moro/Core/Services/TranslationService.swift`
