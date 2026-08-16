# 文件删除设置 UI 外壳 Before / After 目标

## 视觉方向

文件删除设置是“数据与维护”中的高风险叶页面。它的首要任务不是让用户快速点击开关，
而是让用户在动作发生前看清楚：哪些设置只改变提示、哪些设置只清理数据库记录、哪些
视频文件一定会进入系统回收站。目标是一个稳定的文件删除安全工作区。

| Before | After | Why |
| --- | --- | --- |
| 通用 `Card` 连续包住两个开关、回收站规则和危险提示 | 使用带稳定边界的“文件删除安全工作区”实色 surface 承载同一信息 | 高风险页面拥有清晰上下文，不被误认作普通播放偏好 |
| 删除策略和风险说明主要依赖连续文字建立关系 | 保留原有内容、阅读顺序和显隐条件，用工作区边界与 Semantics 建立页面锚点 | 让用户先核对影响范围，再决定是否关闭确认或开启自动清理 |
| 页面只有历史 `settings.fileDeletion.card` key，ListTile 的 Material 由 Card 隐式提供 | 保留历史 key，同时增加 `settings.fileDeletion.workspaceSurface`；透明 `Material` 保住 ListTile 的 ink/focus 绘制 | 外壳替换不破坏测试挂载、键盘焦点或桌面即时反馈 |
| 删除设置保存失败和自动清理结果使用页面临时 Snackbar | 使用维护工作区共享 Snackbar，保留文案、触发时机和页面 owner | 与备份、缓存诊断的恢复反馈一致，不改变清理或删除语义 |

## 明确保护

- `CacheSettingsPage` 对播放设置、删除偏好和自动清理 Future 的唯一 owner 职责；
- `settings.fileDeletion.card`、`settings.fileDeletion.workspaceSurface`、
  `settings.fileDeletion.confirm` 和 `settings.fileDeletion.autoRemoveMissingOrUnreadable`；
- 关闭确认只改变提示偏好；视频文件删除仍先进入系统回收站；
- 自动移除缺失/不可读视频只清理数据库记录，不操作磁盘文件；
- `onAutoRemoveMissingOrUnreadableChanged == null` 时的清理运行中禁用态；
- 删除菜单、播放器队列、扫描、stable identity、标签关系和用户数据的既有页面 owner 与返回路径。

## 验收重点

- 确认开启、确认关闭、自动清理开启/禁用和危险提示四种状态共享同一工作区边界；
- 100%、125%、150% 文字缩放下开关副文案、回收站规则和危险说明自然换行，不依赖固定高度；
- high contrast 使用不透明 surface 与可见描边；reduced motion 不新增持续动画；
- 保存失败、自动清理完成和自动清理失败继续由页面 owner 触发共享维护 Snackbar；
- focused/widget、架构契约、全量测试、analyze、Windows build 与真实设置入口检查全部通过。
