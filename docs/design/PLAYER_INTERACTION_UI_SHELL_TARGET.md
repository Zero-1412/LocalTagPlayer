# 播放器交互 UI 外壳目标

本页是设置首页“播放器交互”的第一轮外壳重构目标。内容仍由设置页提供快照和回调，
本页只负责把两个高频交互主题组织成可辨认的工作区。

| Before | After | 目的 |
| --- | --- | --- |
| 全屏边缘播放列表和快捷键都使用默认 `Card`，层级像一组通用设置项 | 两个独立的实色工作区：`全屏播放列表`、`播放器快捷键` | 让“播放器运行时入口”和“键盘入口”各自拥有清晰边界 |
| 卡片阴影承担主要分组关系，和其它设置页的 Card 壁垒重复 | `librarySurface` 实色底、`libraryBorder` 弱描边、统一圆角和内边距 | 延续 Calm Desktop Media Workspace，减少装饰性浮层，增强长内容扫描 |
| 页面级卡片身份不稳定，视觉差异难以定位 | 保留历史 `settings.fullscreenQueue.card`，新增两个 `workspaceSurface` 和 Semantics 容器 | 保护现有挂载契约，并为页面级截图/可达性检查提供锚点 |
| 开关、恢复默认、录制器和冲突说明的交互顺序容易被外壳改动带偏 | 保留原有顺序、文字、控件 key 和回调 owner；`Esc` 安全出口说明继续显眼 | 视觉重构不改变设置语义、冲突处理和持久化边界 |

## 保护清单

- `CacheSettingsPage` 仍拥有全屏边缘播放列表保存、快捷键冲突校验、录制快照、恢复默认和持久化。
- `FullscreenQueueSettingsCard` 只转发 `onChanged`；`PlayerShortcutsSettingsCard` 只转发 `onReset`、
  `onCaptured`，不创建第二份状态，也不启动播放器命令。
- 保留 `settings.fullscreenQueue.edgeHoverEnabled`、`settings.shortcuts.reset` 以及每个
  `PlayerShortcutRecorder` 的动作绑定和错误反馈。
- 不修改 `PlaybackSettings`、播放队列、`PlayerBackend`、`PlaybackSession`、缩略图/媒体详情队列、
  `FilterQuery`、`TagQueryService`、schema、stable identity 或用户数据。

## 验证目标

- 100% 默认文字缩放下两个工作区、恢复默认和返回设置首页可达。
- 150% 文字缩放下无溢出，快捷键录制器仍能展示并保持冲突说明区域。
- 页面外壳不再产生 `Card`，工作区使用稳定 key 和 Semantics 容器。
- 真实 Debug 窗口检查设置首页进入播放器交互、长内容滚动、返回路径；不触发会改变用户设置的动作。
