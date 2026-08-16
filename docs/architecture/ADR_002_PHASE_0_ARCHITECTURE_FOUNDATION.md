# ADR-002：架构演进 Phase 0 基础门禁

状态：已接受
日期：2026-08-16
对应路线：Phase 0

## 背景

Local Tag Player 已经拥有组合根、应用 controller、领域合同、Repository 端口、SQLite
持久化和平台 adapter。下一阶段将逐步把稳定身份、数据库、后台资源调度和播放器渲染边界
收敛为更清晰的模块化单体，但不能以一次性重写破坏当前媒体库、标签、filtered queue、
播放器和用户数据。

Phase 0 的目标不是改变业务行为，而是先建立可以阻止架构倒退的证据：

1. 记录依赖方向和允许的例外；
2. 固定当前代码规模与关键性能指标的采集入口；
3. 提供不含用户路径和媒体内容的旧库 fixture；
4. 让后续 Phase 1/2 的 stable-ID 和 schema migration 在可重复输入上验证。

## 决策

### 1. 目标依赖方向

```text
composition root
  -> app shell / feature presentation
    -> feature application
      -> domain models / policies / ports
        <- data adapters / platform adapters
```

- `features/*/domain` 不依赖 Flutter、SQLite、`dart:io`、Repository、具体 service 或平台
  adapter；允许依赖纯 Dart、`core` 和领域模型兼容导出。
- `features/*/application` 不持有 `BuildContext`、`Navigator`、`Route`、Widget、texture、
  HWND、SQLite 连接或 `dart:io`；跨边界通过命令、不可变快照和端口完成。现有
  `package:flutter/foundation.dart` 仅作为 `Listenable`/`ChangeNotifier` 状态承载的批准例外，
  不得扩大到 Material、Widgets 或具体渲染对象。
- feature presentation 不导入另一个 feature 的 presentation。
- `composition` 是唯一允许同时创建具体 data/platform 实现并装配 app 的位置。
- 播放器渲染表面当前仍是已接受的 `PlayerBackend` 合同；Phase 5 前不强制拆分
  `PlayerRuntimeBackend` 与 `PlayerSurfaceRenderer`。
- 当前 `services/`、`pages/`、`widgets/` 目录作为迁移中的兼容边界保留；Phase 0 不做目录
  搬迁或批量重命名。

### 2. 稳定身份与旧库 fixture

Phase 0 不修改 schema。旧库 fixture 固定表达迁移前的事实：

```text
videos.path                         = 主键
videos.video_id                     = 不存在
video_tags.video_path               = 关联身份
video_tags.video_id                 = 不存在
video_tags.primary key              = (video_path, tag_id, source)
```

fixture 只允许使用 `C:/fixture/...`、确定性标题和固定时间，不允许写入真实媒体路径、用户
标签文本、数据库文件或媒体内容。Phase 2 必须使用同一 fixture 验证：

- 幂等 schema migration；
- 稳定 `videoId` 回填；
- 标签、收藏、播放进度和缺失状态保留；
- 路径重命名/relink 不创建第二个用户身份；
- 迁移失败时旧库仍可恢复或安全停止。

### 3. 架构指标

指标脚本是只读工具，不进入生产代码和 UI。入口为：

```powershell
pwsh -File tool/architecture_metrics.ps1
pwsh -File tool/architecture_metrics.ps1 -AsJson
```

至少输出：

- `lib/src` Dart 文件数和总行数；
- `LibraryStore`、页面、后台服务和播放器关键文件行数；
- 大文件清单；
- feature presentation 跨功能依赖数量；
- Phase 0 fixture、契约测试和关键架构文件是否存在。

指标是趋势证据，不是通过一次脚本就代表性能合格。查询 P95、队列延迟、内存和构建仍由
对应 focused/QA 门禁测量。

### 4. 门禁失败策略

依赖方向门禁发现新违规时失败关闭；已有迁移兼容代码只允许通过明确的允许列表存在。
本阶段不通过移动文件、删除页面入口、修改 schema 或放宽测试来消除违规。

## Phase 0 验收

- `test/architecture_phase0_contract_test.dart` 通过；
- 旧库 fixture 可被独立测试读取，且不包含真实用户数据；
- 架构指标脚本可在 Windows PowerShell 输出文本和 JSON；
- 既有 architecture/focused tests、`flutter analyze` 通过；
- schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend、thumbnail/media
  queue 和用户数据保持不变。

## 下一阶段边界

Phase 1 只改变内存主索引、path 辅助索引和 stable-ID 命令 API；Phase 2 才进行 schema
migration。两者不得与 ResourceScheduler、播放器渲染拆分或 FTS5 一起提交。

## 对抗式审查

```text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved
protected behaviors: preserved
unauthorized feature removal: none
mount and reachability: not applicable; no UI tree changed
validation: Phase 0 focused contract + flutter analyze + existing focused tests
```
