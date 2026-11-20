# Moro 默认应用图标

默认标识保留向右的象鼻、短象牙和独立蓝耳。纯黑背景由母版绘制，圆角交给系统裁切。蓝耳与头部的接缝保留黑色，让两块轮廓在小尺寸下仍容易区分。

| 部分 | sRGB |
| --- | --- |
| 背景 | `#000000` |
| 象身和象牙 | `#FFFFFF` |
| 耳朵 | `#668CFF` |

1024 px 的主图供系统和 App Store 使用。应用内 240 px 的预览来自同一次导出，供设置、注册和「关于 Moro」使用。关于页固定展示产品标识，主屏幕按用户所选的图标呈现。iOS 的着色外观由系统渲染。

2026 年 11 月 19 日取样美国商店 1.4.0 的 512 px JPEG，面积最大的背景色是偏蓝的 `#020228`。新版经 Xcode 按 iPhone 配置编译，主图标目录中包含浅色和深色两份 1024 px 资源，系统导出的主屏幕图标可测得上表三种主色。线上商店图标随包含新资源的应用版本审核发布后更新。 [美国商店页](https://apps.apple.com/us/app/moro-for-mastodon/id6776115614) · [Apple 图标更新说明](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/)

以[矢量母版](moro-default.svg)为准，在仓库根目录使用 ImageMagick 7 重新导出。命令会生成主图、浅色和深色资源、应用内预览及品牌 PNG。

```sh
bash scripts/export-default-app-icon.sh
```

母版制作时，以既有 Moro 侧脸为参考，保留朝向、象鼻与象牙，分离蓝耳轮廓，随后将三个纯色区域定为矢量。产品页动态创意使用这份轮廓制作纸雕，材料受光后的色阶仅用于影片。
