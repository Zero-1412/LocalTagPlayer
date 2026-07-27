# 依赖与原生运行库审计（2026-07-27）

## 结论

当前 Flutter 工具链、MediaKit Dart 包、`media_kit_video`、平台 lib 包、
ANGLE 供应包和大多数直接 Dart 依赖已处于当前稳定或发布方最新版本。不能把
`pubspec.yaml` 中较低的最小约束误当成实际锁定版本：例如
`media_kit: ^1.1.11` 实际由 `pubspec.lock` 解析为 1.2.6。

本轮不做无关的批量升级。需要单独立项的版本差异只有：

| 依赖 | 当前实际版本 | 最新稳定/发布方最新 | 决策 |
| --- | --- | --- | --- |
| mpv / libmpv | `v0.41.0-908-g48e6c35c0` 固定构建 | 官方稳定版 0.41.0；固定 Windows 构建含后续提交 | 已升级；默认 MediaKit 不切换，HWND 仍受门禁 |
| `file_picker` | 8.3.7 | 11.0.2 | 主版本升级，另做目录选择、取消、Unicode 路径和 Windows 打包回归 |
| `package_info_plus` | 9.0.1 | 10.2.1 | 主版本升级，对本功能收益小；另做关于页和跨平台打包回归 |
| `flutter_lints` | 5.0.0 | 6.0.0 | 只影响开发期；另开纯分析器变更，避免和播放器代码混合 |

`flutter pub outdated --json` 还列出 22 个存在新版本的传递依赖。它们由直接
包和 Flutter SDK 共同约束，不应通过 override 强行升级；随所属直接依赖升级
并重新解析即可。

## 工具链与 Dart 包

- Flutter 3.44.4 stable、Dart 3.12.2；本机稳定通道无待升级提示。
- `media_kit` 实际为 1.2.6，`media_kit_video` 为 2.0.1，均与发布方当前
  推荐组合一致。
- `media_kit_libs_linux` 1.2.1、`media_kit_libs_macos_video` 1.1.4、
  `media_kit_libs_windows_video` 1.0.11 均未被 `flutter pub outdated`
  标记。
- `crypto`、`desktop_drop`、`path`、`path_provider`、
  `sqflite_common_ffi`、`url_launcher`、`window_manager` 均未被标记为
  直接依赖过期。
- `file_picker` 11 和 `package_info_plus` 10 都跨主版本。当前任务没有使用
  它们的新 API，也没有对应缺陷，升级收益不足以抵消 Windows、macOS、Linux
  插件注册和打包回归范围。

## Windows 原生依赖

### mpv

正式构建已固定升级到 `zhongfly/mpv-winbuild` 2026-07-26 开发归档，对应
`v0.41.0-908-g48e6c35c0`；上游稳定基线为 0.41.0。归档、DLL、GPL/LGPL
许可证均固定摘要，Debug bundle 已通过 P/Invoke 读回相同版本。新版进入
MediaKit 的 `MPV_RENDER_API_TYPE_OPENGL` 纹理边界仍不能产生非 copy
D3D11VA；显式 child HWND 路径则已确认 `hwdec-current=d3d11va`。

升级收益包括较新的解码/渲染修复、`gpu-next` 默认策略和 NVIDIA scaling
mode；已接受的代价包括较大的 DLL、许可证清单和 Windows 构建下载变化。
该依赖升级不等于后端切换：MediaKit 默认路径、硬解回退与滤镜门禁保持原样，
child HWND 仍需真实跨 DPI 和后续 A/B 才能讨论默认启用。

### ANGLE

项目使用 `flutter-windows-ANGLE-OpenGL-ES` v1.0.1；这是该供应仓库的最新
Release，但其底层 Chromium 5359 ANGLE 代码并不新。这里没有可直接安全升级的
后续发布包。若要继续解决 D3D11VA interop，必须自建并固定新版 Google ANGLE，
重新验证 EGL 扩展、共享句柄、纹理同步、活动 LUID、退出竞态与 Flutter GPU
descriptor；不能只替换 DLL。

### FFmpeg

项目固定 BtbN 2026-07-12 的 `n8.1.2-22-g94138f6973` LGPL shared 构建；
官方 8.1.2 已发布，BtbN 的自动构建仍每日滚动。当前固定包已经位于 8.1.2
之后，没有已知任务缺陷要求追逐 2026-07-26 的浮动构建。保持 SHA-256 固定更
有利于可复现构建；只有明确的安全或解码修复需要时再升级，并重跑 FFprobe、
缩略图、异常媒体、取消与 Windows 安装包许可证验证。

### 其它

- GitHub Actions 已使用 `checkout@v7`、artifact v7/v8 和
  `softprops/action-gh-release@v3`；Flutter action v2 与 Rust stable 是发布方
  当前维护入口。
- `windows/rust_library_scan` 没有第三方 crate 依赖，不存在 Cargo 升级项。
- 所有原生归档继续由 URL 与 SHA-256 固定；不改用浮动 `latest` URL。

## 推荐升级顺序

1. mpv 已独立升级并固定；继续保持默认 MediaKit，不把版本升级等同于渲染边界
   通过。
2. child HWND 完成真实跨 DPI 后，才运行三类片源六组 A/B、掉帧、退出和回退
   测试，并重新评估 Windows 默认后端。
3. `file_picker`、`package_info_plus`、`flutter_lints` 分成三个小提交升级，
   每个提交保留完整跨平台构建与对应 UI/功能回归证据。
4. 传递依赖随直接依赖自然解析，不增加 dependency overrides。
