# AXTree 最小复现与 Flutter SDK/engine A/B（2026-08-15）

## 目的

把主应用大 profile 中带桌面控制 observer 的 188 条
`Failed to update ui::AXTree` 与 Flutter SDK/engine 版本解耦，先验证一个不依赖
Local Tag Player 数据库、播放器或用户 profile 的最小 Windows harness。

## Harness

临时工程位于 `artifacts/ax_tree_repro_20260815/app/`，不进入产品代码。它只包含：

- 一个 `MaterialApp` 和单个窗口；
- 800 个全部挂载的 `Semantics(container: true)` 节点，交替切换为 6 个节点；
- 首帧后每 260ms 使用无动画 `Navigator.pushReplacement` 切换 route，共 24 代；
- 独立的 `LOCAL_TAG_PLAYER_DATA_DIR`、stdout/stderr 和构建目录。

这样同时覆盖了语义树 hydration、route 替换和外部 observer 读取，但没有引入真实媒体、SQLite、
`PlayerBackend` 或应用业务队列。

## SDK/engine 矩阵

| SDK | engine | Debug 构建 | 桌面 observer | 无 observer | 结论 |
|---|---|---:|---:|---:|---|
| Flutter 3.44.4 | `a10d8ac38de835021c8d2f920dbf50a920ccc030` | 通过 | AXTree 0 / stderr 0 | AXTree 0 / stderr 0 | 未复现 |
| Flutter 3.41.9 | `42d3d75a56` | 通过 | AXTree 0 / stderr 0 | AXTree 0 / stderr 0 | 未复现 |

桌面 observer 条件通过 Computer Use 读取同一窗口的 accessibility state；无 observer 条件只启动
隔离 exe 并等待相同周期后关闭。四组进程均正常退出，日志只做关键错误检索，没有发现
`ERROR`、`Exception`、`failed` 或 `undefined symbol`。

原始运行目录：

- `artifacts/ax_tree_repro_20260815/runs/3.44.4-cua-full/`
- `artifacts/ax_tree_repro_20260815/runs/3.44.4-no-cua/`
- `artifacts/ax_tree_repro_20260815/runs/3.41.9-cua-full/`
- `artifacts/ax_tree_repro_20260815/runs/3.41.9-no-cua/`

## 结论与边界

该最小 harness 在两个 engine 上都没有复现，因此目前不能把升级 Flutter SDK/engine 作为已验证修复，
也不能把主应用 188 条告警归因到某个版本回归。它排除了“任意小型 route replacement 都会触发 AXTree 错误”，
但没有排除真实大库的语义节点规模、媒体库 hydration、播放器页面切换和桌面 observer 的组合时序。

下一轮应保持当前 SDK 不变，逐步增加应用形状而不是删除语义节点：先增加可见媒体卡片与分页/滚动，
再叠加播放器 `BlockSemantics` 和 route 返回；每一步继续保留 3.44.4/3.41.9 双版本及 observer/no-observer
对照。只有在某个层级能稳定复现且只在某个 engine 消失时，才评估隔离升级并回到 Local Tag Player 门禁。

## 跨 DPI 状态

本机只有 `DISPLAY1`（2560×1440），没有第二显示器，因此真实跨物理 DPI 门禁仍为
`pending-physical-cross-dpi`。不能仅传入 runner 的 `-PhysicalCrossDpiStatus passed`；必须在两块缩放比例
不同的物理显示器上实际移窗，并记录移入/移出、全屏、返回和播放器释放结果。

schema、`FilterQuery`、`TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体队列和用户数据均未改变。
