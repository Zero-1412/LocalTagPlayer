# 维护反馈组件族 Before / After 目标

## 视觉与交互目标

| Before | After | Why |
| --- | --- | --- |
| 维护页面各自直接调用 `showDialog`、`SnackBar` 和 `Tooltip`，同一类反馈容易退回不同主题或材质 | 通过 `maintenance_feedback.dart` 统一弹层、菜单、sheet、非阻塞反馈和 tooltip 入口 | 保持维护工作区在确认、恢复和状态反馈中的空间与语义一致 |
| Dialog 已有个别主题包裹，但调用方需要重复记住 Route context 与局部 Theme 的边界 | `showMaintenanceDialog` 自动包回维护主题，页面仍拥有 builder、返回值和动作 | 消除浅色回退风险，不改变确认结果或业务 owner |
| SnackBar 的显示、替换和消息长度由每个页面临时决定 | `showMaintenanceSnackBar` 默认不截断当前消息，只有明确要求时才替换 | 连续错误、重试和导出结果更容易读完，恢复反馈不互相覆盖 |
| 菜单和 sheet 缺少维护工作区的统一实色浮层基线 | `showMaintenanceMenu` 与 `showMaintenanceModalBottomSheet` 提供相同深色、描边、圆角和安全区入口 | 为后续标签菜单、紧凑维护页和小窗口 sheet 建立单一基础，不引入 blur |
| 图标动作虽有 tooltip，但等待时间、表面和主题可能随页面变化 | `MaintenanceTooltip` 与 `maintenanceFeedbackTheme.tooltipTheme` 统一提示表面，同时保留 Tooltip 语义 | 在桌面高密度操作中提供稳定说明、焦点和键盘可达性 |

## 本轮迁移范围

- 标签中心：新建标签、批量添加/移除、保存、manual-only 说明和高风险只读反馈；标签分组提示使用共享 tooltip。
- 设置备份：开关保存失败、完整性检查、立即备份、导出成功/失败反馈。
- Missing / Relink：单条 relink、批量路径替换确认、审计摘要复制反馈。
- 目录管理与媒体库：解除目录管理、清空继续观看进度确认。
- 新组件只编排展示层，不读取磁盘、SQLite、扫描结果或播放队列。

## 明确不改

- `FilterQuery`、`TagQueryService`、搜索 controller、排序和网格/列表结果语义；
- filtered playback queue、`PlayerBackend`、缩略图与媒体详情队列；
- `videoId`、fingerprint、missing/relink、root/detached 语义和用户数据；
- 标签来源、一级/二级 folder 层级、批量 manual 标签边界；
- 文件选择器、Repository、设置 controller 和备份/扫描服务的业务命令。

## 验收重点

- Dialog 继续返回原有 `bool`/结果值；取消、确认、关闭、默认焦点和危险动作颜色保持可达；
- 菜单保留调用方的 anchor、`value`、选择结果和键盘语义；sheet 保留 route result、safe area 与滚动内容；
- SnackBar 成功、错误、重试和复制反馈文案不丢失；只有显式 `replaceCurrent` 才隐藏当前消息；
- tooltip 继续提供完整文案；100%、125%、150% 文字缩放、high contrast 和 reduced motion 不依赖动态 blur；
- 不新增查询、列表重算、I/O、缓存预取或持续动画；完成 focused widget、架构、全量测试、analyze、Windows build 和真实窗口检查。
