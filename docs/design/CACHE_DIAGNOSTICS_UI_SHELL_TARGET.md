# 缓存诊断 UI 外壳 Before / After 目标

## 视觉方向

缓存诊断是设置工作区中的维护型叶页面。它的任务不是展示“缓存实现细节”，而是让用户快速
回答三件事：当前缓存是否健康、后台任务是否在推进、出现失败时下一步能否安全恢复。目标是
把它做成一个稳定的诊断工作区，而不是继续堆叠通用设置卡片。

| Before | After | Why |
| --- | --- | --- |
| 二级页中用通用 `Card` 包住一串诊断区，外层和内层 surface 层级重复 | 用带稳定边界的“缓存诊断工作区”结构表面承载 loading/error/snapshot 三种状态 | 让诊断内容有单一空间锚点，降低卡片墙感并保持状态切换不跳位 |
| 标题、健康状态、覆盖率、指标、后台任务、失败详情和动作虽已存在，但整体更像连续设置项 | 保留既有信息顺序，并明确“状态摘要 → 覆盖率 → 指标 → 后台任务 → 失败语义/详情 → 恢复动作” | 先读健康与进度，再处理失败；符合诊断而非配置的阅读路径 |
| 缓存重试、清除和缺失补全使用默认 Snackbar 表面 | 使用维护工作区共享 Snackbar，保留原文案、显示时机和页面 owner | 恢复反馈与其它维护页面一致，不改变命令结果或替换策略 |
| 诊断内容缺少独立的页面级语义和挂载证据 | 工作区使用 `Semantics(container: true)` 与稳定 `settings.cache.workspaceSurface` key | 让视觉边界、辅助技术上下文和测试挂载证据一致 |

## 明确保护

- `CacheDiagnosticsController` 的 latest-only 读取、dispose 生命周期和错误快照；
- `CacheDiagnosticsMaintenanceController` 的重试、清除失败标记、缺失补全互斥状态；
- `ThumbnailService` 的可见优先、后台限流、取消、有效 JPEG 判断和缓存队列；
- “失败属于缺失子集”的统计语义、失败原因展示和最多 50 条详情；
- 缓存统计中的总数、有效缓存、缺失、失败、后台任务与耗时计算；
- `settings.cache.*` ValueKey、刷新/返回路径、loading/error/empty/failure 状态与原文案。

## 验收重点

- loading、读取失败、无失败项、有失败项和后台补全中均使用同一工作区边界；
- 100%、125%、150% 文字缩放下标题、指标、失败详情和动作自然换行，不依赖固定高度；
- high contrast 使用实色 surface 和可见描边，reduced motion 不新增持续动画；
- 重试、清除失败标记、生成缺失缓存仍由页面 owner 派发，UI 不发起新 I/O 或查询；
- focused/widget、架构契约、全量测试、analyze、Windows build 与真实窗口设置入口检查全部通过。
