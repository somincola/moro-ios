# App Store 自定义产品页

每个 JSON 是一页：内部名称（`name`）、面向人群、截图顺序（引用 `build/qa/showcase/frame/out/<locale>/NN.png`
的编号）和各语言的宣传文本（≤170 字符）。页面只做 en-US（应用主语言）和 zh-Hans，其他语言回落到英文。

上传时把截图按顺序放到 `build/qa/cpp/<slug>/<locale>/01.png…`，再用
`asc product-pages custom-pages localizations screenshot-sets upload --device-type IPHONE_69` 上传。
各页的 App Store Connect ID 与链接记录在 `pages.md`。
