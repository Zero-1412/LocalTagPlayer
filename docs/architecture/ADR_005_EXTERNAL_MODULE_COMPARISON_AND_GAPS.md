# ADR-005 外部项目模块对比与差距收口

状态：已接受（本轮先落地低风险、高收益的三个模块改进）

日期：2026-08-16

## 背景

Local Tag Player 已完成 stable `videoId`、单 SQLite 事务、最终 `FilterQuery` 语义校验、
统一 `ResourceScheduler` 和 `PlayerRuntimeBackend`/`PlayerSurfaceRenderer` 契约。本 ADR
补充对成熟开源项目和一手技术文档的模块级对比，避免仅凭抽象偏好继续扩张架构。

## 对比范围

| 模块 | 外部参考 | 外部实现特征 | 当前项目差距 | 决策 |
| --- | --- | --- | --- | --- |
| 媒体库查询与事务 | [Stash ARCHITECTURE.md](https://github.com/stashapp/stash/blob/develop/docs/ARCHITECTURE.md) | 按实体拆分 repository interface、SQLite 实现、query builder 和 transaction manager | 已有 Query/Command/Coordinator service，但低层 stable-ID video/cache/playback 写入仍集中在 Store；FTS 派生索引按 revision 全量重建 | 本轮先修候选索引正确性；低层 video persistence 继续作为单事务 owner，后续有证据再拆 |
| 标签与搜索 | [Hydrus](https://github.com/hydrusnetwork/hydrus) | 以 tag 为核心浏览、搜索、别名和大库管理 | 当前 manual/folder 来源隔离更严格，但没有照搬 Hydrus 的远端 repository、命名空间和复杂规则系统 | 保持产品目标，不引入不需要的远端标签系统 |
| SQLite 搜索索引 | [SQLite FTS5](https://www.sqlite.org/fts5.html)、[SQLite Query Planner](https://www.sqlite.org/queryplanner.html) | external-content FTS 需要显式同步；触发器可维护增量索引，`rebuild` 可恢复一致性；复合/覆盖索引影响搜索与排序 | 当前以 `dataRevision` 触发安全全量 rebuild，且索引文本遗漏 tag ID；没有独立索引一致性诊断 | 本轮纳入 tag ID、保持最终 Dart 校验；增量触发器等 schema/事务变化另立 ADR |
| 后台任务与资源预算 | [BullMQ](https://github.com/taskforcesh/bullmq) | 持久 job、优先级、并发、暂停、重试、延迟和去重 | 当前是本地进程内 lease，排队请求没有公开取消句柄；但产品不需要 Redis 分布式队列 | 本轮增加可取消 pending request；扫描状态继续由 SQLite 持久化，不引入 Redis |
| 播放器 runtime/surface | [mpv client API](https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h)、[media_kit](https://github.com/media-kit/media-kit) | mpv 区分事件循环、同步/异步请求和 `reply_userdata`；media_kit 将 `Player` 与 `VideoController`/Texture 分开并通过 release 生命周期解绑 | 当前已有 Dart 命令尾链、generation gate 和 runtime/surface contract；剩余风险主要是 Windows 原生矩阵和 dispose 诊断 | 保持现有契约，不为对齐外部 API 重新设计播放器；补验证而不是增加 adapter 层 |
| 缓存与 stable identity | [media_kit VideoController](https://github.com/media-kit/media-kit/blob/main/media_kit_video/lib/src/video_controller/video_controller.dart) | controller 绑定既有 Player，并在 Player release 时解绑输出 listener | 当前缩略图主 cache key 已可使用 fingerprint，但进程内已验证快照仍按 mutable path 保存 | 本轮改为 stable `videoId` 内存快照，并在每个 `videoId` 范围内以 fingerprint 优先生成磁盘 cache key |
| 诊断与可观测性 | [Sentry Dart](https://github.com/getsentry/sentry-dart)、[Sentry Native](https://github.com/getsentry/sentry-native) | trace/span、breadcrumb、上下文标签和 native crash 数据关联 | 当前采用本地匿名 `debugPrint`/snapshot，缺少统一 operation correlation；外部遥测也不符合当前产品边界 | 本轮不引入外部 telemetry；后续可增加本地 ring-buffer operation trace |

## 本轮修改边界

### 1. 搜索候选索引

FTS5 只能缩小候选集，不能成为最终过滤语义 owner。索引文本增加 `tags.id`，修复按 tag ID
搜索可能被候选阶段漏掉的问题；`FilterQuery`/`TagQueryService` 不变。仍使用 revision-aware
rebuild 和失败安全回退，避免在没有完整 changed-row contract 前引入不完整的 FTS 触发器。

### 2. 缩略图缓存

进程内有效缩略图以 `videoId` 为主键，路径只作为输入和兼容显示数据。磁盘 cache key 由
`videoId + mediaFingerprint` 组成；若没有稳定 fingerprint，才在该 videoId 范围内回退到
path/size/mtime。这样文件移动、重联或改名不会无条件丢失可复用缩略图，也不会让两个指向同一
内容的数据库记录共享一个可被单独删除的磁盘文件。

### 3. ResourceScheduler

新增可取消的 pending request handle。取消只影响尚未取得 lease 的请求；已启动工作仍由 owner
在 `finally` 中释放，避免把取消误实现成强行中断 FFmpeg/SQLite 操作。现有 `acquire` 和 `run`
接口保持兼容。

## 暂不引入

- Redis/BullMQ 或其它持久分布式 job queue：当前是单机桌面应用，扫描状态和备份状态已有 SQLite owner；
- go_router 或其它路由框架：当前没有 deep link、认证守卫或多 Navigator 状态需求；
- 直接把所有 Store 低层写入拆成多数据库/多 repository connection：会破坏统一事务和稳定身份提交边界；
- 外部 telemetry SDK：用户媒体路径、tag 和本地库内容不应默认离开设备。

## 验证要求

- 搜索：tag ID、tag name、alias、path/title 的候选结果必须与完整 Dart 过滤结果 stable-ID 集合一致；
- 缓存：同一 `videoId` 改变 path 后仍能读取进程内快照；不同 fingerprint 不得复用旧磁盘 cache；
- 调度：pending request 取消后不占用预算，已取得 lease 的工作仍能正常释放；
- 既有 `FilterQuery`、来源 filtered queue、播放器后端、用户数据和 schema v2 回归不变。
