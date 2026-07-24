# 第三方组件与再分发说明

本文件说明 Local Tag Player 二进制分发中主要第三方组件的许可证承载位置。它不替代项目自身的 `LICENSE`，也不构成法律意见。

## Flutter 与 Dart 依赖

Flutter 构建会把 Dart、Flutter 与插件依赖的许可证汇总到应用包中的：

```text
data/flutter_assets/NOTICES.Z
```

公开安装包必须保留该文件，不得在打包或精简产物时删除。

## media_kit、libmpv、ANGLE 与 FFmpeg

- 默认播放器基于 `media_kit` / `media_kit_video`，各 Flutter 包的声明由 `NOTICES.Z` 承载。
- Windows 原生播放器实验后端会安装 libmpv、ANGLE 与 FFmpeg 相关许可证及来源说明到 `data/licenses/native_player/`。
- libmpv 预编译包及其链接的编解码组件可能触发 GPL 或 LGPL 再分发义务；发布前必须按最终实际使用的二进制构建配置核对。
- Windows 媒体探测桥当前使用 BtbN 的 LGPL shared FFmpeg 变体；对应许可证随原生模块安装。

更具体的固定版本、上游来源与边界见 [`windows/native_player/THIRD_PARTY_NOTICES.md`](windows/native_player/THIRD_PARTY_NOTICES.md)。

## Rust 目录扫描器

Windows Rust 目录扫描器采用 MIT 许可证。其许可证文本随安装包放置在：

```text
data/licenses/rust_library_scan/LICENSE
```

## 发布检查

对外发布前至少确认：

1. `NOTICES.Z` 仍在 Flutter assets 中。
2. `data/licenses/native_player/` 与 `data/licenses/rust_library_scan/` 未被安装器过滤。
3. 最终 bundle 中新增的原生二进制已补充来源、版本和许可证。
4. 若实际分发的 libmpv/FFmpeg 构建配置变化，重新评估 GPL/LGPL 源码提供、动态链接与替换库要求。
