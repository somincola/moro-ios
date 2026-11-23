# Moro 搜索结果短片

[四页静态图](pages/exports/zh-Hans/four-pages.jpg) · [播放简中搜索卡片](pages/exports/zh-Hans/search-card.mp4) · [十种语言审片](review.html) · [简中 4K 原片](pages/exports/zh-Hans/moro-search-zh-Hans-3840x2560.mp4)

第一帧直接展示首页，随后切换通知、个人中心和外观设置。每一页都是静态构图。左侧页名前使用 Moro 的白象蓝耳图标，「Moro for Mastodon」固定在左下角，与说明文字左缘对齐。[品牌标志](../../../../docs/design/brand/moro-default.svg)

右栏使用各语言的 iPhone 模拟器截图。个人中心同时展示封面、资料和简介。外观设置按各语言实际布局取景，字号滑块和主题色均在画面内。阿拉伯语版使用阿拉伯语文案和英文应用界面。[简中截图](../../zh-Hans/iphone) · [演示图片来源](../../showcase-assets/CREDITS.md) · [各语言文案](source/copy.json)

原片为 3840 × 2560、30 fps、12 秒的静音 H.264 视频，使用 Rec. 709 色彩。连续播放时每页停留 3 秒，首页跨首尾衔接。中央 2168 × 1030 裁切保留图标、署名和完整页面窗口。审片页支持按页面跳转、切换商店语言和查看四页静态图。[成片校验清单](pages/exports/manifest.json)

## 重新导出

在有 Xcode、FFmpeg 和 ImageMagick 的 Mac 上，从仓库根目录运行。

```sh
python3 -B screenshots/app-store/creative/four-views/pages/export.py
python3 -B screenshots/app-store/creative/four-views/pages/check.py
```
