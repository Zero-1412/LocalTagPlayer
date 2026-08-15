# ARCHITECTURE.md

## 当前基线

```text
Architecture Baseline 0.5.127
```

本文件只保存当前有效的模块、数据和平台合同。逐提交演化说明已归档到
`docs/history/architecture/ARCHITECTURE_HISTORY_THROUGH_2026-07-30.md`；
设计取舍优先记录为 `docs/architecture/ADR_*.md`，不要把时间线重新追加到本文件。

## 总体结构

```text
Presentation
  -> Application / Controllers / Coordinators
    -> Domain contracts and models
      -> Repository / Services
        -> Platform adapters
```

依赖只向内：

- Presentation 负责状态呈现和用户意图，不拥有查询、路径或播放器实现；
- Application 编排异步任务、取消、会话和用户动作；
- Domain 定义标签、过滤、稳定身份和播放会话合同；
- Repository 负责 SQLite 持久化和 migration；
- Platform adapter 隔离文件系统、数据库 Provider、播放器、FFmpeg 和系统路径。

## 产品数据流

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

Tag Manager 写入 repository；缩略图和媒体探测通过受限后台队列补充 repository，
不能改变筛选来源或阻塞高频 UI。

## 标签和过滤合同

合法标签来源：

```text
manual / folder / rule / filename / import / auto
```

- folder 标签从当前 root 文件树第一/第二层派生；
- 二级标签始终属于所属一级标签；
- 用户主动维护的 manual 标签始终属于独立顶层 `manual` 组，不继承 folder 父级；
- 历史挂在 folder 父级下的 manual 关系在顶层保存或批量操作时提升为顶层关系，保留标签名称与视频关联；
- folder 可重算，manual/locked 和其它用户维护关系必须保留；
- 同名 folder/manual 不合并身份；关系优先使用 `tagId`；
- 单视频编辑将 folder 锁定显示与 manual 可编辑集合分开传递；即使名称相同，manual 仍只新增/删除 `source=manual` 的数据库关联，绝不创建、移动或改写目录；
- 展示层可按来源、组、父级和规范化名称聚合，但不得改变真实关系。

过滤唯一所有者是 `FilterQuery` / `TagQueryService`：

```text
same group OR
different groups AND
excluded tags NOT
keyword -> file name / path / tag name / alias
```

UI、PlayerPage 和 Tag Manager 不复制查询语义。

## 稳定身份与 SQLite

```text
videoId: stable database identity
mediaFingerprint: file/media identity
path: mutable current location
isMissing: path unavailable while record is preserved
```

标签、收藏、播放记录和进度绑定 `videoId`。路径变化不能静默创建第二个用户身份，
也不能删除 manual 标签。schema/migration 必须向后兼容、幂等并保留旧数据库数据；
无法确认新位置时先 missing，不直接物理删除记录。

Repository 拥有：

- videos、tag groups/items、video-tag relations；
- favorites、play records/progress；
- roots、scan state、missing/relink 状态；
- 依赖备份和数据恢复事务。

扫描器只枚举和提取候选元数据；稳定身份判定和 SQLite 写入仍由 Application/Repository
拥有。Rust 扫描器不得直接写业务数据库。

## 媒体库与后台协调

- 搜索使用稳定 controller 输入链；
- 标签点击先更新可见结果，计数和预取延后；
- 扫描、媒体探测、缩略图生成和备份任务可取消过期工作；
- 相似视频视觉复核必须支持取消/分阶段进度回调；候选只读已有缩略图，FFmpeg 深度取帧有界，不能把
  不可见的大库视频批量提升为播放器兜底解码；页面必须区分候选构建与画面对比阶段，删除候选后局部
  更新，下一轮由用户明确触发。
- 相似视频批量取帧使用独立队列：页面前台按 CPU 采用 2–4 路有界并发，非前台降为单并发，离开页面
  取消排队任务；播放器活跃时由 ThumbnailService.pause 冻结批量队列，候选调度等待播放结束后恢复。
- 相似视频视觉扫描必须分别统计候选构建、首帧预筛和深度时序取帧的累计耗时、平滑吞吐率及剩余时间估算；
  首帧预筛两端可并行，深度签名按 stable `videoId` 建立连续有界 worker，完成一项后立即补位；实际
  FFmpeg 数量仍受 ThumbnailService 有界队列约束；任务按预计时长/大小优先，取帧队列跨视频轮转，派生
  签名写入不得占住 FFmpeg worker。深度任务未汇合前不得沿用预筛吞吐率伪造“还剩 1 秒”。
- 视觉签名属于可重建派生缓存，持久化在现有 `metadata` 表的
  `cache.visual_signature.<videoId>` key 中，不新增表或改变 SQLite schema version；条目必须携带
  算法版本及 mediaFingerprint/size/mtime 快照，读取时不匹配即失效并重算。签名写入经
  `VisualSignatureCacheRepository`，不进入用户数据备份；删除事务必须与 thumbnail/media_details
  metadata 一并清理，晚到写入须在事务内确认 stable videoId 仍存在。
- 播放活跃时降低后台媒体负载；播放期间不得让视觉复核继续启动新的 FFmpeg 任务；
- 目录切换、排序和搜索不得在 UI 线程重复全量查询/rebuild；
- root 删除、文件删除和数据库清理是不同用户动作，不能互相暗示授权。

### 用户视频删除合同

- 所有媒体库、收藏/最近播放、本地目录、相似视频和播放器队列中的用户视频删除，统一经过
  `LibraryFileCommandExecutor` 与 `FileSystemAdapter.moveFileToTrash`；执行顺序固定为
  `移入系统回收站 -> 删除 Repository 记录 -> 清理可重建缩略图缓存`。
- Repository 删除事务同时清理 `cache.thumbnail.<videoId>`、`cache.media_details.<videoId>` 与
  `cache.visual_signature.<videoId>` 三类缓存诊断/派生 metadata，和标签关联、视频行同批提交，
  不留下以 stable `videoId` 为键的孤立状态。
- 相似视频采用“合并后删除”：源视频的 `is_favorite` 与 `source=manual` 标签关系只并入用户
  选定的保留视频；目标数据按并集保留，folder 派生标签不复制。两条候选自动选择另一条，
  多条候选必须显式选择保留目标，合并与源记录删除在同一 Repository 事务中提交。
- 删除确认只保留“是否继续提示”的偏好；不再提供“仅移出媒体库、保留本地文件”的分支，
  因为该分支会让“删除”在不同入口产生不可逆的语义差异。视频文件可从系统回收站恢复。
- 路径失效/不可读的自动数据库清理是明确例外：它只删除数据库记录，不操作磁盘文件，也不
  冒充回收站动作。
- 缩略图、FFmpeg 临时输出、更新下载包和测试临时目录属于可重建/临时资源，不纳入用户视频
  回收站合同；它们继续使用各自的直接清理边界。

## 播放合同

```text
source filtered result
-> PlaybackSession(items, currentIndex, source context)
-> PlayerService
-> PlayerBackend
```

- PlayerPage 只消费来源 filtered queue，不从全局媒体库重建；
- 右侧二级标签切换保持来源语境；
- 返回媒体库保留筛选状态；
- 快速 open/seek 使用 generation/cancellation 防止旧请求覆盖新意图；
- 播放队列、当前 index、播放进度和 UI 反馈彼此独立，不以重建队列换取状态更新。

`PlayerBackend` 是平台播放能力的最小合同。可选扩展边界承载属性批处理、
交互式 seek、诊断和平台特性；不为单一后端强迫所有平台实现。

`PlayerMediaControlsBoundary` 是附着于 `PlayerBackend` 的可选媒体控制合同：只暴露当前会话的音轨、字幕、章节及音频/字幕延迟意图；`PlayerService` 负责安全转发，不支持的后端必须显式降级。该边界不拥有播放列表、播放记录或用户媒体数据，且不得创建第二条播放器/解码链。

## Windows 播放边界

- 正式默认后端仍是 MediaKit Texture；
- Windows native mpv/child HWND 只允许显式 QA 覆盖，不自动成为生产默认；
- `PlayerService -> PlayerBackend -> MediaKit / Windows native` 依赖方向固定；
- 交互式 seek 在按键重复期间只走 keyframe 快速预览，由应用层累计逻辑目标；
- 连续预览约以 64ms 节奏合并最新目标；短按使用完整配置步长，长按重复阶段使用
  受限小步长，避免一个刷新窗口内形成十几秒的画面硬跳；
- 物理按键松开时仅对最后目标执行一次精确 seek，平台后端不得用固定计时器自行收敛；
- 继续观看恢复使用精确 seek，不改变播放/暂停意图；
- Texture 输出尺寸由稳定档位、去抖、最小间隔、降档滞回和原生确认协调；
- NVIDIA VSR/HDR、NVOFA、VapourSynth 和本机插件属于能力门禁或长期研究，
  未经发布、许可、回退和真实性证据不得成为自动生产路径；
- 原生工作线程、窗口和纹理生命周期必须在 Flutter dispose/退出前有序收口。
- Windows runner 在 controller 释放后仍可能收到排队的系统消息；这类消息必须先确认
  Flutter controller 存活，不能再解引用 engine。

## 缓存与诊断

`ThumbnailService`、`MediaDetailsService` 通过队列调用 `FFmpegBackend`/FFprobe：

- 可见项优先、后台限流；
- 0-byte 或不完整 JPEG 无效；
- 失败原因可见、可重试；
- cache key/失效策略由服务层拥有，UI 不拼路径；
- diagnostics controller dispose 后取消 timer 和异步回调；
- 日志、诊断和截图不得泄露用户媒体路径或数据库内容。

## 平台边界

```text
FileSystemAdapter
DatabaseProvider
AppPaths
PlayerBackend
FFmpegBackend
LibraryScanBackend
```

- Windows/macOS/Linux adapter 实现系统行为；
- Dart core 不出现盘符、exe、Explorer/Finder 命令或打包目录假设；
- 应用更新代理由组合根注入 `AppPaths`，独立保存到 `app_update_proxy_settings.json`；
  仅 `GitHubReleaseUpdateService` 的独立 `HttpClient` 消费该配置，不修改系统代理或媒体链路；
  设置首页通过独立“网络代理”二级页读写该边界，“关于”页只保留版本与更新操作；
- 原生依赖必须固定版本/摘要并记录许可；
- Windows C++ 与 Rust 组件只通过显式 ABI/序列化合同进入 Dart；
- 平台不可用时返回可诊断失败或安全回退，不伪造能力成功。

## 跨模块不变量

1. UI 不复制过滤逻辑。
2. 播放器不回退全局队列。
3. folder 重算不删除 manual/locked 数据。
4. mutable path 不替代 stable identity。
5. 扫描和媒体工具不越过 Repository 写业务数据。
6. 平台命令不进入 UI/Domain。
7. 后台任务不阻塞高频交互。
8. 未授权功能删除失败关闭，页面挂载和真实可达性必须有证据。

## 修改本合同

修改 schema、core、repository/platform contract、过滤、稳定身份、播放/缓存队列时：

1. 更新本文件的 current contract；
2. 需要解释取舍时新增 ADR；
3. 历史事实进入 `CHANGELOG.md` 或 dated QA，不在本文件堆时间线；
4. 运行 architecture/focused tests、`flutter analyze` 和对应平台 build；
5. UI/运行时可观察变化按 `AGENTS.md` 完成真实点击与截图。
