# ARCHITECTURE.md

## 当前基线

```text
Architecture Baseline 0.5.129
```

本文件只保存当前有效的模块、数据和平台合同。演化记录进入
`docs/history/architecture/`，设计取舍进入 `docs/architecture/ADR_*.md`。

## 总体结构与数据流

```text
Presentation
  -> Application / Controllers / Coordinators
    -> Domain contracts and models
      -> Repository / Services
        -> Platform adapters
```

依赖只向内：Presentation 呈现状态和用户意图；Application 编排任务、取消和会话；
Domain 定义标签、过滤、稳定身份和播放合同；Repository 拥有 SQLite/migration；
Platform adapter 隔离文件系统、数据库 Provider、播放器、FFmpeg 和系统路径。

```text
local roots
-> LibraryScanBackend
-> stable identity validation
-> SQLite repositories
-> TagQueryService / FilterQuery
-> visible library result
-> PlaybackSession
-> PlayerPage filtered queue
```

Tag Manager 写入 Repository；缩略图、媒体探测、备份和视觉取帧通过受限后台队列补充，
不得改变筛选来源或阻塞高频 UI。Rust 扫描器只枚举/提取候选元数据，不得直接写业务数据库。

## 标签与过滤合同

合法来源：`manual / folder / rule / filename / import / auto`。

- folder 标签只从当前 root 文件树第一/第二层派生，二级始终属于所属一级。
- folder 可重算；manual、locked 和其它用户维护关系必须保留。
- manual 关系保持独立顶层 `manual` 组；同名 folder/manual 不合并身份，关系优先使用 `tagId`。
- UI、PlayerPage 和 Tag Manager 不复制查询语义，唯一所有者是 `FilterQuery` / `TagQueryService`。

```text
same group OR
different groups AND
excluded tags NOT
keyword -> file name / path / tag name / alias
```

## 稳定身份与 SQLite

```text
videoId: stable database identity
mediaFingerprint: file/media identity
path: mutable current location
isMissing: path unavailable while record is preserved
```

标签、收藏、播放记录和进度绑定 `videoId`。路径变化不得创建第二个用户身份或删除 manual
标签；无法确认新位置时先进入 missing。schema/migration 必须向后兼容、幂等、可回滚并保留旧数据。

schema v2 的 `videos.video_id` 为 PRIMARY KEY，`videos.path` 为可变唯一字段，Windows 维护
不区分大小写索引；`video_tags(video_id, tag_id, source)` 为关系主键。旧 path-keyed 数据库在同一
SQLite transaction 中换表迁移，孤立关系使迁移回滚而不静默丢失用户字段。详细取舍见
`docs/architecture/ADR_003_STABLE_VIDEO_ID_AND_SCHEMA_MIGRATION.md`。

`VideoIdentityIndex.byVideoId` 是主索引，pathKey 只是同步辅助视图；删除、重命名、missing relink
和合并删除的生产命令使用 stable-ID API。`LibraryRepositoryContext` 统一 connection、索引、
标签关系和事务；查询、命令、root/扫描/relink 协调分别由 Store service 拥有，不复制状态。

大库且 FTS5 可用时可生成关键词候选 SQL，`dataRevision` 成功写入后按需重建；候选文本包含
tag ID、名称、显示名和 alias，最终结果仍由 `FilterQuery` / `TagQueryService` 验证，小库、短词
和 FTS5 不可用时走内存路径。缩略图进程内快照按 stable `videoId` 索引，磁盘 key 在该
`videoId` 范围内优先使用 `mediaFingerprint`，没有 fingerprint 时才回退到 path/size/mtime，
避免 relink 后丢失可复用缓存，也避免两个数据库记录因内容相同而互相清理缓存。
`ResourceScheduler` 除 lease 预算外提供 pending request cancellation；取消只移除尚未启动的工作，
已经取得 lease 的 FFmpeg/SQLite 工作必须自然收尾。详见 ADR_004 和
`docs/architecture/ADR_005_EXTERNAL_MODULE_COMPARISON_AND_GAPS.md`。

## 媒体库、后台任务与删除

- 搜索使用稳定 controller 输入链；标签点击先更新可见结果，计数和预取延后。
- 扫描、媒体探测、缩略图、备份和视觉复核支持取消过期任务、分阶段进度和有界并发。
- 播放器活跃时后台 FFprobe/批量取帧让渡或冻结，退出后按进入前状态恢复，不覆盖用户手动暂停。
- 可重建视觉签名保存为带算法版本、fingerprint/size/mtime 快照的 metadata，不新增 schema；失效即重算，
  不进入用户备份，晚到写入必须确认 stable videoId 仍存在。
- 视觉匹配度只供人工复核；首帧 dHash 只预筛，review 组不得自动删除或移动文件。
- 目录删除、文件删除和数据库清理是不同动作，不能互相暗示授权。

用户视频删除统一经过 `LibraryFileCommandExecutor` 与 `FileSystemAdapter.moveFileToTrash`：

```text
移入系统回收站 -> 删除 Repository 记录 -> 清理可重建缓存
```

删除事务同步清理标签关系、视频行、thumbnail/media_details/visual_signature metadata；相似视频
合并删除必须由用户选择保留目标，并只合并收藏和 manual 标签。缺失记录的自动数据库清理不操作磁盘，
临时资源使用各自清理边界。

## 播放合同

```text
source filtered result
-> PlaybackSession(items, currentIndex, source context)
-> PlayerService
-> PlayerBackend
```

- PlayerPage 只消费来源 filtered queue；右侧切换保持来源语境，返回媒体库保留筛选状态。
- Route 返回先发布已提交的 stable-ID 差量，再在尾部等待原生释放、采样和进度刷盘。
- open/stop/seek/dispose 共享媒体命令尾链；快速请求使用 generation/cancellation，旧事件不能覆盖新意图。
- 精确/交互式 seek 串行化，确认窗口屏蔽旧位置事件；播放队列、current index、进度和 UI 反馈彼此独立。
- `PlayerBackend` 是最小平台合同；可选属性、seek、诊断和媒体控制扩展不得拥有播放列表或用户数据，
  不支持时必须显式安全降级，不得创建第二条解码链。

## Windows、缓存与平台边界

- 正式默认后端是 MediaKit Texture；Windows native mpv/child HWND 只供显式 QA，不自动成为生产默认。
- `PlayerService -> PlayerBackend -> MediaKit / Windows native` 依赖方向固定；原生窗口、线程和纹理在
  Flutter dispose/退出前有序收口，排队系统消息先确认 controller 存活。
- NVIDIA VSR/HDR、NVOFA、VapourSynth 和本机插件必须经过能力、许可、回退和真实性门禁，不能自动生产化。
- `ThumbnailService`/`MediaDetailsService` 通过 `FFmpegBackend`/FFprobe；可见项优先、后台限流、失败可见可重试，
  0-byte/不完整 JPEG 无效，diagnostics dispose 后取消 timer/异步回调，日志不得泄露媒体路径或数据库内容。
  缩略图缺失补全既可由设置页明确入口启动，也会在媒体库首帧后延迟登记一次；媒体库首帧后还会错峰登记缺少媒体详情/可靠
  时长的 active 视频，但不自动重试已知失败项。两类后台生产源都只按最多 500 项候选窗口推进，窗口空出后再从迭代器补入
  后续项目，禁止超过窗口的候选被截断；媒体详情原生探测仍按最多 8 项小批次串行。
  缩略图 cache key/JPEG 校验请求最多 24 个，处理器数达到 12 时生成并发最多 3 个，`ResourceScheduler` 的缩略图
  lease 预算最多 3 个且共享总预算仍为 4。

平台边界：`FileSystemAdapter`、`DatabaseProvider`、`AppPaths`、`PlayerBackend`、`FFmpegBackend`、
`LibraryScanBackend`。Dart core 不出现盘符、exe、Explorer/Finder 命令或打包目录假设；原生组件只通过
显式 ABI/序列化合同进入 Dart；平台不可用时返回可诊断失败或安全回退。

## 跨模块不变量

1. UI 不复制过滤逻辑。
2. 播放器不回退全局队列。
3. folder 重算不删除 manual/locked 数据。
4. mutable path 不替代 stable identity。
5. 扫描和媒体工具不越过 Repository 写业务数据。
6. 平台命令不进入 UI/Domain。
7. 后台任务不阻塞高频交互。
8. 未授权删除失败关闭；页面挂载、可达性和真实窗口行为必须有证据。

修改 schema、core、Repository/platform contract、过滤、稳定身份、播放或缓存队列时，更新本合同，
必要时增加 ADR，并运行 architecture/focused tests、`flutter analyze`、对应平台 build 和真实 UI 验收。
