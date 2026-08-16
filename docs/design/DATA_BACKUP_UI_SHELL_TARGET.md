# 数据备份 UI 外壳 Before / After 目标

## 视觉方向

数据备份是设置工作区中的数据保护叶页面。它需要让用户先知道备份保护什么，再判断同步是否
正常，最后安全地执行立即备份、完整性检查或导出；它不是一组可以任意切换的普通偏好开关。

| Before | After | Why |
| --- | --- | --- |
| 通用 `Card` 包住开关、保护范围、同步指标和维护按钮 | 使用带稳定边界的“数据保护工作区”实色 surface 承载同一内容 | 建立页面锚点，减少通用设置卡片感并与其它维护页统一 |
| 保护范围、同步状态和维护动作连续排列但页面身份较弱 | 保留原有顺序，并明确“保护范围 → 同步状态 → 维护动作”三段阅读路径 | 用户先理解覆盖边界，再决定是否需要执行动作 |
| 页面只有历史 `settings.dataBackup.card` 挂载 key | 保留历史 key，同时增加 `settings.dataBackup.workspaceSurface` 和工作区 Semantics | 不破坏既有入口与测试，同时提供页面级视觉/辅助技术证据 |
| 维护按钮依赖普通卡片的底部边界 | 保留按钮、禁用条件、焦点顺序和页面 owner，仅替换外壳材质 | 直接动作保持可见，备份/检查/导出语义和安全时序不变 |

## 明确保护

- `DataBackupSettingsWorkspace` 的 `SerialSettingsController`、状态订阅和 dispose 生命周期；
- `DataBackupMaintenanceController` 的立即备份、完整性检查、导出互斥与取消结果；
- 备份设置持久化、独立备份数据库、Repository 与平台文件选择器边界；
- “只备份稳定身份与用户维护数据、不复制视频文件、不导出本地路径”的原有说明；
- `settings.dataBackup.card`、`settings.dataBackup.toggle`、`settings.dataBackup.runNow`、
  `settings.dataBackup.checkIntegrity`、`settings.dataBackup.export` 及返回路径；
- 备份状态阶段、进度、待同步数量、最近完成时间、失败反馈和完整性检查 Dialog。

## 验收重点

- 开关、范围说明、同步指标、进度和维护动作在同一工作区边界内，loading/运行/失败状态不改变页面锚点；
- 100%、125%、150% 文字缩放下指标、长说明、按钮和完整性检查入口自然换行，不依赖固定高度；
- high contrast 使用不透明 surface 与可见描边；reduced motion 不新增持续动画；
- 立即备份、完整性检查、导出仍由页面 owner 派发，UI 不新增 I/O、查询、备份任务或数据库操作；
- focused/widget、架构契约、全量测试、analyze、Windows build 与真实设置入口检查全部通过。
