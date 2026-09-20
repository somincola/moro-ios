# 构图调整前的原始图片

此目录保留液态玻璃、泼彩、故障和拼贴的原始 1024 × 1024 PNG，内容与分支起点 `57745b6` 中相应的 Any 图片一致。

`scripts/generate-dark-app-icons.py` 始终读取这里的四张原图，输出正式图标及设置页预览。请勿用生成结果覆盖这些源图，否则会导致下次运行再次累计缩放。

默认和彩虹没有构图调整，继续读取各自图标集内的 Any 图片。

## 三款新图标的选定原版

2026-09-18 新增 `appicon-applegummy-1024.png` 与 `appicon-zebraprint-1024.png`，分别复制自图标探索第二轮的 `01-apple-chew.png`、`02-zebra-print.png`。这两张是用户最终选定的日间成图，正式 Any 资源与其逐字节一致。

`appicon-notawake-1024.png` 复制自第三轮 `03-not-awake.png`，保留漫画大象原版。

`scripts/generate-character-app-icons.py` 从这里读取三张图，只为 Dark 调整背景，同时生成应用内预览。原始 Any 图片均逐字节保留。[处理说明与校验记录](../character-icons/README.md)。探索稿与挑选预览不作为脚本输入。
