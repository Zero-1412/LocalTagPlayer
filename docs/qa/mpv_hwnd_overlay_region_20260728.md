# MPV child HWND 视口与弹层 region 门禁（2026-07-28）

## 单侧黑边与右键暗框复测

- child HWND 外框始终覆盖完整视频占位区；控制条可见时
  `native-overlay-bottom=128`，自动隐藏后为 `3`。
- 初次进入和快速切换后未再出现画面错位或底部重复条带。
- 设置与右键菜单均只裁剪真实覆盖矩形，菜单外视频继续推进；真实窗口截图未见暗框。
- integration test 记录 `hwdec=d3d11va`、`native-texture-copies=0`、
  `frame-drop-count=0`，弹层打开和关闭期间播放时间持续前进。
- 真实窗口检查覆盖进入播放器、控制条自动隐藏、右键打开/关闭和更多播放设置。

## 目标

修复 Windows MPV 原生后端的两个真实窗口问题：

1. 普通窗口仍预留全屏顶部控制区，导致自动比例画面偏小。
2. 设置或右键菜单出现时隐藏整个 child HWND，导致视频区域变黑。

不改变“铺满”模式的等比裁边语义，不退回截图、冻结帧或 Flutter 纹理复制。

## 实现边界

- 普通窗口顶部 airspace 为 0；全屏顶部语境为 64，底部控制区始终为 128。
- `PlayerOverlaySurfaceBoundary` 接收弹层逻辑矩形和 Flutter view 尺寸。
- runner 按父 HWND 客户区换算物理坐标，对外层视频宿主执行
  `SetWindowRgn` 差集；libmpv 内层窗口和播放时钟不暂停。
- 设置面板回报真实动态尺寸，右键菜单以真实菜单项矩形收紧首帧估算。
- 未提供矩形的模态弹窗继续完整隐藏，嵌套路由按栈恢复上一层策略。

## 自动验证

- `test/windows_native_hwnd_surface_test.dart`
  - 普通 800×600：`top=0`、`height=472`。
  - 全屏避让：`top=64`、`height=408`。
  - 模拟 DPR 1.5 仍触发原生矩形同步。
  - 设置矩形通过 `partial=true` 和逻辑坐标送入 runner。
- `integration_test/player_hwnd_airspace_test.dart`
  - 匿名真人低码率 1080P。
  - 设置与右键期间 `native-surface-occluded=true` 且
    `native-surface-visible=true`。
  - 设置停留期间播放头继续推进。
  - `hwdec-current=d3d11va`、`native-texture-copies=0`、总掉帧 0。

验证命令：

```powershell
flutter test test/windows_native_hwnd_surface_test.dart
flutter test test/player_service_architecture_test.dart test/player_rename_playback_smoke_test.dart
flutter test test/widget_test.dart --plain-name "player settings use compact primary and advanced pages"
flutter analyze
flutter build windows --debug
flutter test integration_test/player_hwnd_airspace_test.dart -d windows
```

## 真实点击与截图复核

真实 Debug 窗口使用用户已选择的 MPV 后端打开 1920×1080 视频，依次检查：

- 普通自动比例：画面利用取消的顶部 64 像素，完整显示且没有进入“铺满”裁边。
- 主设置：面板浮在实时画面上，视频在面板外持续变化，控制条和右侧队列可见。
- 更多设置：面板高度变化后 region 同步收紧，无旧矩形残留或额外黑块。
- 右键菜单：菜单矩形准确让出，四周视频继续播放，关闭后完整恢复。

截图检查未发现位置错位、文字截断、控件遮挡、队列穿透或整面黑屏。

## 未改变

- SQLite schema、`FilterQuery`、`TagQueryService`。
- filtered queue 来源、顺序、当前 index 和返回状态。
- MediaKit 后端及 macOS/Linux 行为。
- NVIDIA VSR/HDR、压缩增强、插件 ABI、缓存与用户数据。
