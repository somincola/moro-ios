# 三款新图标

新增苹果软糖、斑马印刷、还没醒，共九款可选图标。三款均含 1024 × 1024 的 Any / Dark，以及设置页使用的 240 × 240 明暗预览。

| 图标 | 选定原版 | Dark 背景 |
| --- | --- | --- |
| 苹果软糖 | 第二轮青苹果软糖，保留原耳形、卷鼻与位置 | 黑樱桃色 |
| 斑马印刷 | 第二轮黑白旋纹大象，保留原身形与印刷颗粒 | 暗红棕纸底 |
| 还没醒 | 第三轮犯困的蓝色漫画大象，保留神态与粗线条 | 暖棕纸底 |

Any 与选定 PNG 逐字节一致。Dark 直接处理背景像素，保留主体核心像素、位置和比例，不使用 AI 重绘。原图位于 [`source-originals/`](../source-originals/README.md)，SHA-256 与主体边界见 [metrics.json](metrics.json)。

三款已接入图标选择、Debug / Release 替换图标配置，以及现有九种语言的名称。iOS 按同一图标集中的 `luminosity: dark` 选择深色资源；设置页预览按应用外观加载。图片不预绘圆角。

## 验证

2026-09-18，iPhone 17 Pro / iOS 26.5：构建与 `AppIconChoiceTests` 7 项测试通过，0 警告、0 错误。编译产物包含全部八款替换图标，三款新图标均含 1024 的 Any / Dark 和 240 的明暗预览。

三款 Any 与选定原图逐字节一致；12 张正式图片重复生成结果一致。设置页显示九款图标，三款新增图标均验证了系统切换和桌面明暗外观。

## 重新生成

```sh
python3 scripts/generate-character-app-icons.py
```

需要 Pillow、NumPy；始终从保留原图开始。应用内的预览图片属于正式资源；过程中的探索稿和挑选页面可直接清理，不影响重新生成。

可按需生成对照图（另需 macOS 黑体），无需提交到仓库：

```sh
python3 scripts/generate-character-app-icons.py --preview /tmp/moro-character-icons.png
```
