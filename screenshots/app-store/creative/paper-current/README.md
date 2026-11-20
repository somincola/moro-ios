# Moro 商店页头

纸雕白象第二版用于十种商店语言。斜光掠过折纸，蓝耳微微抬起，投影随光线回落。原片为 3840 × 1646、30 fps、15 秒的静音 H.264 视频。[页头原片](moro-header-v2-3840x1646.mp4) · [页头和搜索结果预览](review.html)

页头使用 Moro 默认图标的轮廓和折纸底片。Metal 分别渲染象身、蓝耳和投影。搜索位使用四页直切短片，各语言的成片与导出方式见搜索短片说明。[品牌母版](../../../../docs/design/brand/moro-default.svg) · [美术底片](source/art-direction.md) · [搜索短片说明](../four-views/README.md)

## 重新导出

在支持 Metal 的 Mac 上安装 Xcode、ImageMagick 7 和 FFmpeg，然后从仓库根目录运行。设置 `MORO_FILM_OUTPUT` 可把新导出写入单独目录。

```sh
bash screenshots/app-store/creative/paper-current/source/render.sh header
```
