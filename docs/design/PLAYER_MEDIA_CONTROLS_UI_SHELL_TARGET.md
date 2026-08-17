# 播放器媒体控制 UI 外壳目标

本页是播放器 Phase 2 进入下一处页面外壳重构的第一轮目标。媒体控制仍由当前播放器会话读取快照并转发既有回调；本轮只替换弹窗内四个内容分组的展示表面。

## Before / After

| Before | After | 目的 |
| --- | --- | --- |
| 音轨、字幕、音画同步和章节直接使用默认 `Card`，材质依赖全局卡片主题 | 四个分组使用播放器嵌套工作区表面：实色、弱描边、固定圆角、内容裁切 | 让媒体控制与播放器画布、队列和弹窗保持同一层级语言 |
| 弹窗通过 Route context 打开，可能退回全局主题 | `PlayerMediaControlsDialog` 显式应用 `playerWorkspaceTheme`，并读取已有 high contrast 策略 | 保证播放器深色表面、对话框、焦点和描边在路由切换后仍连续 |
| 分组边界与无障碍定位弱，难以做页面级挂载检查 | 分组保留原有标题和控件顺序，增加稳定 surface key 与容器语义 | 让视觉层级、自动化验证和键盘/读屏结构一致 |

## 保护边界

- `PlayerMediaControlsDialog` 仍在每次打开时调用 `read`，操作后只刷新当前媒体控制快照。
- 音轨、字幕、章节、音频/字幕延迟的 key、文案、点击回调和关闭/刷新动作保持可达。
- 不修改 `PlayerService`、`PlayerBackend`、当前来源 `filtered playback queue`、播放会话、媒体详情/缩略图队列或播放器资源生命周期。
- 不新增设置持久化、查询、I/O、预取或持续动画；high contrast 只复用已有 `AppAccessibilityScope`。

## 验收重点

- 播放器控制栏的媒体控制入口仍可达，打开后四个分组均可定位；关闭和刷新仍保持原结果。
- 选音轨、选字幕、关闭字幕、章节跳转和延迟增减仍按当前会话回调，不写入队列或全局设置。
- 100%、125%、150% 文字缩放与 high contrast 下，表面边界、标题、空态、按钮和滚动内容不溢出；不依赖 blur 或动画。
- 完成 focused/widget、架构、全量测试、`flutter analyze`、Windows debug build 和真实播放器窗口检查。
