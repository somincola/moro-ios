# 1.4.1 商店关键词

十个本地化版本共用名称 Moro for Mastodon。英文把重复覆盖的通用词换成能描述已上线能力的词，包括按时间阅读、收藏、离线阅读、话题和草稿。中文保留社区惯用的「长毛象／長毛象」，日文保留本地书写的「マストドン」。阿拉伯语的关键词由英文改为阿拉伯文。可直接交给 ASC 的完整字段见[十种语言词表](1.4.1.json)。

| 商店语言 | UTF-8 字节 | 主要覆盖 |
| --- | ---: | --- |
| ar-SA | 96 | 联邦宇宙、微型博客、列表、草稿与已保存内容 |
| de-DE | 98 | 联邦宇宙、时间线、书签、离线阅读与帖子 |
| en-US | 99 | fediverse、chronological、timeline、bookmark、offline |
| es-ES | 96 | cronología、marcadores、sin conexión、borradores |
| fr-FR | 95 | fédivers、fil chronologique、signets、hors ligne |
| it | 95 | cronologia、segnalibri、conversazioni |
| ja | 95 | マストドン、時系列、ブックマーク、下書き |
| pt-PT | 96 | cronologia、marcadores、leitura offline |
| zh-Hans | 91 | 长毛象、联邦宇宙、离线阅读、多账号、草稿箱 |
| zh-Hant | 94 | 長毛象、時間軸、主題標籤、稍後閱讀 |

提交口径采用 Apple 在版本字段说明中给出的 **100 字节**。检查包括 UTF-8 长度、组内去重、逗号分隔和与商店名称的重复。各语言使用本地化查询抽样验证语义。美国的 fediverse 与日本的 マストドン 能找到相关客户端，台湾的「長毛象」也返回动物题材产品，因此保留「聯邦宇宙」「時間軸」补充语境。抽样检索无法给出搜索量或预测排名。 [Apple 字段说明](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) · [美国样本](https://itunes.apple.com/search?country=us&term=fediverse&entity=software&limit=10) · [日本样本](https://itunes.apple.com/search?country=jp&term=%E3%83%9E%E3%82%B9%E3%83%88%E3%83%89%E3%83%B3&entity=software&limit=10) · [台湾样本](https://itunes.apple.com/search?country=tw&term=%E9%95%B7%E6%AF%9B%E8%B1%A1&entity=software&limit=10)

已在 1.4.1 草稿按语言逐字读回，仓库下次发布从[版本资料目录](../version/1.4.1/)读取相同的词表。上架后建议以 28 天为一个观察窗，按商店地区和 App Store Search 来源比较展示、产品页浏览及首次下载，记录关键词生效与视觉素材替换的各自日期。两者同时生效时，整体变化无法单独归因于关键词。
