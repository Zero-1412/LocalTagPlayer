# CURRENT_TASK.md

## 当前状态

项目已能运行并构建 Windows debug 版本。

架构版本状态：`Architecture Baseline 0.4.4` 已完成，`Architecture Baseline 0.4.5` 当前推进中。

最近一次验证：

```powershell
flutter analyze
flutter build windows --debug
```

结果：通过。

## 最近完成

- Chat 7 Responsive UI + Platform Polish 第一阶段完成：统一弹窗 surface、8px 圆角、边框和标题层级，保持媒体库浅色区域与播放器深色区域协调。
- 媒体库视频卡片、顶部栏、筛选侧栏和当前筛选条完成窄宽度防溢出补强：compact 下搜索提示压缩、排序横向滚动、结果数量分行显示，视频网格改为稳定单列尺寸。
- 缓存诊断页 compact 下将补缓存、暂停队列、失败重试、清除失败记录和刷新操作收进 AppBar 菜单，页面间距与媒体库一致。
- Tag Manager 改为 responsive Flex：expanded 常驻管理侧栏，medium 收窄侧栏，compact 纵向堆叠标签列表和详情，避免小窗口横向溢出。
- 播放器 compact 下右侧队列不再常驻，改为顶部队列入口打开底部面板；队列面板宽度限制在当前窗口内，未修改 filtered queue 或 open worker。
- 已在 Chat 7 文档补充 macOS / Linux 适配 notes，覆盖 FFmpeg bundled tools、sqlite3 动态库、文件管理器 reveal、窗口尺寸和快捷键差异。
- 将后续规划源头提升为 `<private-planning-document>`，明确当前项目实现只代表历史状态，后续方向以该规划为准。
- 重写 `ROADMAP.md`，补齐 Tag 驱动检索闭环、网页式分组筛选、Player 筛选队列、folder/manual Tag 解耦、稳定视频身份、missing/relink、Tag Manager、响应式 UI 等阶段计划。
- 更新 `PROJECT.md` 和 `ARCHITECTURE.md`，写入外部规划文件优先级和新的多 Chat 协作边界。
- 按外部规划重排 `docs/chat_tasks/`，统一为 7 个 Chat 分工，并新增 Chat 6 Tag Manager、Chat 7 Responsive UI。
- `lib/main.dart` 已按现有类边界拆分为 `src/models`、`src/services`、`src/pages`、`src/widgets`，当前采用 Dart part 机制保持无行为变化。
- 新增 `src/core/TagRules` 和 `src/core/AppPaths`，集中标签派生规则、视频扩展名判断和应用数据路径。
- 新增 `src/core/LayoutSize` 和 `LayoutBreakpoints`，统一预留 `compact`、`medium`、`expanded` 响应式布局语义。
- 新增 `src/repositories/repository_interfaces.dart`，规划 `LibraryRepository`、`TagRepository`、`CacheRepository`、`PlaybackRepository` 数据边界，暂不替换现有 `LibraryStore`。
- 收口 `FileSystemAdapter`、`FFmpegBackend`、`DatabaseProvider` 接口职责，补齐目录选择、文件管理器定位、FFmpeg 可用性/版本和数据库文件位置等边界方法。
- 扩展 `TagGroup`、`TagItem`、`FilterQuery`、`PlaybackSession` stub 到外部规划字段，现有筛选入口仍保持原 Windows 行为。
- SQLite 新增 `tag_groups`、`tags`、`tag_aliases`、`video_tags` 规范化 Tag 索引表，旧库打开时自动创建，不需要清空媒体库。
- `LibraryStore` 扫描时同步 `folder` 来源一级/二级 Tag，手动编辑标签时同步 `manual` 来源 Tag，现有 `VideoItem.tags/childTags` 继续作为兼容数据面。
- 新增 `TagQueryContext` 和 `TagQueryService`，筛选逻辑可使用视频关联的 tagId、标签名和别名，并暴露按标签统计的结果数量。
- 补齐 Tag Model + Filter Engine 第一阶段验收修复：旧库按缺失链接的视频回填 folder 索引，手动编辑只刷新当前 manual 范围并排除 folder 派生标签，同组候选计数不再被当前组筛选压缩。
- SQLite 补充 `tag_aliases(alias)` 与 `video_tags(source)` 索引，保留 `video_tags(video_path)`、`video_tags(tag_id)` 查询索引。
- 主界面筛选接入 `TagQueryService`，关键字搜索继续匹配文件名、路径、文件夹、标签名，并新增匹配当前视频关联标签别名。
- 从筛选结果进入播放器时，传入当前筛选结果队列，避免二级筛选时自动扩展成整个一级标签队列。
- Chat 4 Player Filter Queue 第一阶段完成：`PlayerPage` 使用进入页面时的 filtered queue 副本作为播放队列，空 playlist 兜底为 initialItem，initialItem 不在队列时安全落到队列首项。
- 播放器右侧队列标题接入当前筛选摘要，包含 keyword、一级/二级兼容筛选、分组 include/exclude 和收藏筛选；右侧继续显示当前序号如 `1 / 1661`。
- 播放器右侧二级标签切换只在当前 filtered queue 上做子集切换，不再扩展到媒体库全量列表。
- 播放器快速切换视频时改为串行处理最新 open 请求，避免旧 open 完成后覆盖新视频；相关异步回调补充 mounted 检查，降低 dispose 后 setState 风险。
- Chat 4 验收补漏：无筛选时播放器队列标题改为中性的“当前列表”，右侧序号统一为 `1/1661` 格式；open worker 结束前会检查并接续 pending open 请求，避免极端连续切换时请求滞留。
- 媒体库首页新增网页式分组 Tag 筛选侧栏，按 `tag_groups` 展示标签，并复用 `LibraryStore.resultCounts` 显示候选结果数。
- 媒体库顶部搜索提示扩展为文件名 / 路径 / 标签 / 别名，搜索仍走现有 `TagQueryService`。
- 媒体库中心顶部新增当前筛选 chips，显示一级/二级兼容标签、分组标签、收藏筛选和 `-标签` 排除项。
- 媒体库中心顶部新增当前结果数 / 总数、清空筛选和“保存筛选”入口；保存筛选当前为 Smart List 持久化 TODO。
- 媒体库分组筛选支持包含标签与排除标签切换，排除标签显示为 `-标签` chip。
- 媒体库首页接入 `LayoutSize` / `LayoutBreakpoints`：expanded 常驻左侧筛选栏，medium 可折叠，compact 通过 BottomSheet 打开筛选。
- 保留旧的常用标签、一级标签兼容区、二级标签横条和当前一级下二级标签展示，作为分组 Tag UI 的过渡入口。
- Chat 3 验收补漏：旧一级/二级兼容筛选与新分组 tag 筛选会互相清理等价状态，避免同一筛选条件在 chips 和查询中重复残留。
- Chat 3 验收补漏：当前筛选条在窄宽度下改为上下两行布局，避免 compact / medium 小窗口中清空、保存和结果数量区域溢出。
- 新增本地编码规则：新增/修改代码时，为规则、平台边界、异步流程添加简短必要注释。
- 新增多 Chat 协作边界和 Architecture Baseline 0.2.0，要求底层边界变更同步更新架构版本。
- 新增 ROADMAP.md 和 docs/chat_tasks/ 模板，后续各 Chat 重开对话时按对应模板继续，不丢上下文。
- 主界面一级标签、常用标签、二级标签改为单选。
- 从二级筛选进入播放器时，播放器当前队列使用筛选结果；同层二级标签列表后续由 Player Queue Chat 继续按筛选上下文优化。
- 播放器右侧顶部显示当前一级标签下的所有同级二级标签。
- “默认专辑”在二级标签排序中放到第一个。
- 点击播放器右侧二级标签会切换播放列表。
- 主界面和播放器里的二级标签横条支持鼠标滚轮和鼠标按住拖动。
- 播放诊断改为打开诊断弹窗期间持续采样，暂停播放时停止采集，关闭弹窗后停止诊断任务。
- 播放诊断新增连续采样、最近采样时间和异常原因提示，辅助判断播放位置推进、掉帧、缓存、AV 同步问题。
- 播放器右侧列表改为当前播放位置附近窗口预读，避免进入播放器或切换视频时对整条播放列表读取媒体信息。
- 播放器右侧列表改为固定高度虚拟列表、稳定 Future 缓存和更紧凑的专业播放器侧栏样式。
- SQLite 视频表新增根目录、相对路径、文件大小、修改时间字段，并自动兼容旧库补列。
- 媒体库保存改为元数据、单条视频 upsert、单条删除分离，收藏/播放时间/媒体信息/标签编辑不再全量重写视频表。
- 目录扫描改为增量写库，只在新增、删除、标签变化、文件指纹变化时更新对应视频记录。
- 扫描已有视频时按当前目录结构刷新二级标签，避免旧二级标签残留。
- 媒体库路径比较改为 Windows 大小写不敏感稳定 key，添加根目录时规范化路径并去重。
- 目录扫描增加不可访问目录、不可读取文件、stat 失败容错，单个坏文件不会中断整次扫描。
- 主界面扫描流程增加并发保护和失败恢复，扫描异常会提示错误并恢复按钮状态。
- 搜索改为多关键词匹配标题、路径、文件夹、一级标签和二级标签。
- 收藏标签和标签编辑增加 trim 与大小写不敏感去重。
- 缩略图后台队列改为保守并发：总并发最多 4，后台并发最多 2，可见区域任务优先。
- 后台批量缩略图默认只走 FFmpeg，避免大量 media_kit 兜底播放器实例影响播放；可见区域仍允许播放器兜底。
- FFmpeg 缩略图写入改为临时文件成功后替换，FFprobe 输出缩减为必要 stream 字段，并补充超时错误。
- 缓存诊断页新增后台并发统计，补缓存完成后按钮自动恢复，并在离开页面时保存失败原因。
- Chat 5 第一阶段完成：新增 `DesktopFFmpegBackend` 兼容适配层，`ExternalMediaTools` 统一通过 `FFmpegBackend` 定位和调用 FFmpeg/FFprobe，保留当前 Windows bundled tools 查找行为。
- 缓存诊断页新增 FFmpeg/FFprobe 版本展示、缩略图后台排队上限、媒体信息队列/执行中/本轮完成/失败状态。
- 缩略图 media_kit 兜底写入改为临时文件成功后替换，避免半截 JPEG 被当作有效缓存。
- 缩略图后台批量排队增加上限，避免播放期或大库补缓存时一次性派发过多低优先级任务。
- 缓存诊断页新增失败重试、清除失败记录和异常文件列表；失败原因继续写入 `thumbnail_error` / `media_details_error`，不修改 tag schema。
- Chat 5 验收补漏：读取已有缩略图缓存时校验 JPEG 头尾和文件长度，自动丢弃 0 字节或半截缓存文件；诊断页失败重试/清除失败记录按钮在执行中禁用，避免重复触发。
- Chat 6 第一阶段完成：媒体库顶栏新增标签管理入口，进入 `TagManagerPage` 后可查看 tag groups、tags、aliases、usage count 和 folder/manual 等来源使用数量。
- `LibraryStore` 新增标签维护 API：创建 manual tag、编辑 displayName、aliases、hidden、favorite、sortOrder，并支持移动 tag 到其它 group。移动 group 只更新 tag 元数据，不重写已有 `video_tags` 关系。
- 标签管理页支持基于当前媒体库 filtered result 批量添加 manual tag、批量移除 manual tag；移除时限定 `source=manual`，不会删除 folder 来源关系，并同步旧 `VideoItem.tags/childTags` 兼容字段。
- 删除和合并属于高风险操作，当前仅保留入口、确认弹窗和 `video_tags` 引用检查；folder 来源 tag 会提示为路径派生标签，不允许第一阶段硬删除。
- 分组 Tag 匹配在已有规范化索引时优先按 tagId，避免同名 folder 兼容字段误命中 manual tag。
- Chat 6 验收补漏：Tag Manager 左侧补充 tag groups 摘要；批量添加/移除只允许 manual 来源标签，非 manual 标签按钮禁用并显示来源说明；创建 manual tag 时如果会覆盖同分组同名非 manual tag 会阻止保存，避免 folder tag 被伪造成 manual。
- 乱码检查未发现实际乱码字符。

## 当前已知问题 / 待观察

- 第一阶段拆分已完成，但仍是同一个 Dart library；下一阶段需要小步把低风险 core/model 文件迁移到普通 import，并逐步让实现依赖新接口。
- 本轮 `flutter analyze` 和 Windows debug 构建通过；但 `dart format` 仍会超时，后续需要单独确认本机 Dart formatter 启动问题。
- 播放时仍可能有轻微卡顿感，需要继续结合持续诊断结果，从缩略图队列、mpv 参数、硬解模式三个方向排查。
- media_kit 对精确掉帧、AV offset 暴露有限，诊断页中部分指标来自 mpv property，仍需验证不同机器/显卡下是否可用。
- 缩略图缓存队列已降低后台资源占用并限制后台排队；后续仍需观察不同硬盘/显卡环境下 FFmpeg 超时、失败重试和播放时暂停效果。
- 当前 README 已重写为简洁入口，历史乱码内容已不再保留。

## 下一步建议任务

优先级从高到低：

1. 小步迁移平台与数据接口实现：让 `LibraryStore`、媒体工具和页面逐步依赖 `FileSystemAdapter`、`DatabaseProvider`、Repository 接口，迁移时必须保持 Windows 行为不变。
2. 排查播放卡顿：结合新增后台并发统计，确认播放时缩略图队列暂停后是否仍有已启动任务造成 I/O 抖动。
3. 完善诊断能力：继续增加 FFmpeg/FFprobe 实际调用耗时、可复制诊断摘要和播放诊断入口联动。
4. 继续优化媒体库 schema：推进 `videoId + fingerprint + mutable path`，增加 `missing` 标记、单文件 relink 和批量路径替换。
5. 继续优化播放器右侧列表：基于滚动可见区动态预取缩略图，并减少播放中列表状态刷新频率。

## 新 Chat 启动提示词

```text
这是 Flutter Windows 本地标签播放器项目，路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- 对应 docs/chat_tasks/CHAT_*.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

不要依赖旧聊天历史。先读规划、任务文档和相关代码再改。修改后运行：
- flutter analyze
- flutter build windows --debug

当前任务：<在这里写新的具体任务>
```







