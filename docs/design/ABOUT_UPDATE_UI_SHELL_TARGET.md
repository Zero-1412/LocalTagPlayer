# 关于 / 更新 UI 外壳 Before/After 目标

## 页面定位

这是设置中的版本与正式更新详情页。它负责展示当前版本、更新渠道、主动检查和更新结果；下载、
校验、安装器启动及更新网络均由 `AppUpdateService` 与更新 Dialog 保持拥有，不把更新动作扩展到媒体库。

## Before / After

| Before | After | 目的 |
| --- | --- | --- |
| 版本、产品说明、更新按钮和状态全部包在通用 `Card` 中 | 收敛为带 Semantics 的“版本与更新工作区”实色 surface | 形成设置详情的稳定边界，减少卡片墙感 |
| logo、版本、渠道和更新动作主要依赖留白分隔 | 保留原内容和顺序，使用结构 surface、弱描边和明确间距建立层级 | 先确认当前版本，再理解更新动作 |
| 更新结果是按钮下方普通文本 | 保留 `settings.about.updateStatus` 文案与 key，使用低干扰状态 surface | 最新、发现新版本和失败状态紧邻动作显示 |
| 页面没有内容面挂载锚点 | 新增 `settings.about.workspaceSurface` 和 Semantics container | 支持页面级可达性、截图和后续视觉 diff |

## 保护边界

- 保留 `settings.about`、logo、version、checkUpdate 和 updateStatus key，以及原有文案和按钮回调。
- `AppUpdateService` 仍是版本读取、Release 查询、下载和安装器执行的唯一边界。
- 保留 loading、最新、发现新版本、检查失败、更新 Dialog、下载进度和安装器恢复路径。
- 不新增自动检查、网络请求、下载副作用、动画或媒体库 rebuild；不修改代理、播放器、筛选、队列、缓存、stable identity 或用户数据。

## 验收条件

- 100%、125%、150% 文字缩放下，版本、渠道说明、更新按钮和状态文本完整可读。
- 实色 surface 与弱描边在 high contrast 下仍能表达边界；reduced motion 不新增移动或持续动画。
- 主动检查的最新/失败状态仍就地反馈；发现新版本仍进入原更新 Dialog。
- 设置首页 → 关于 → 返回路径可达；focused、全量测试、analyze、Windows debug build 和真实窗口检查通过。
