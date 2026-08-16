# CURRENT_TASK.md

# 2026-08-16 · 播放器首帧与媒体库悬停预览启动链（完成）

- 完成：正式 MediaKit 后端以 `open(play: false)` 打开本地媒体，完成引擎/可播放性/恢复位置门禁后由页面显式 `play()`；
  本地 `cache-pause` 默认切换为 `no`，可用 `LTP_LOCAL_CACHE_PAUSE=true` 做同素材对照。
- 完成：媒体库结果页挂载一个共享 hover `Player/VideoController`；静态 poster 在原生首帧、透明 Texture 挂载和 Flutter 帧合成完成前持续可见，失败/超时不揭示黑帧。
- 完成：点击播放器前的邻近缩略图预热改为 `unawaited` 后台任务，不再阻塞正式播放器 Route；共享预览释放与 stop/open 具备代次和串行门禁。
- 保护：schema、`FilterQuery`/`TagQueryService`、来源 filtered queue、stable videoId 用户数据、正式 PlayerBackend 公共契约和缩略图/媒体队列语义不变。
- 已验证：目标 focused/widget/architecture tests 通过；`flutter analyze` 通过；`flutter build windows --debug` 成功；Debug 桌面运行时可进入媒体库并点击卡片到播放器 surface。

# 2026-08-16 · 播放器未提交改动与架构 Phase 3–6 收口（完成）

- 完成：播放器释放/seek/媒体身份改动的 analyzer 与架构契约失败已清除；页面派生状态迁出后
  `player_page.dart` 回到架构行数门禁，释放阶段的取消、dispose、released 均保留有界等待和失败诊断。
- Phase 3：`LibraryStoreQueryService` 承载真实 SQL/标签查询和候选查询；`LibraryStoreCommandService`
  承载标签、收藏、root 元数据和 manual tag 命令；`LibraryStoreCoordinatorService` 承载 root、扫描、
  取消和 relink 协调。三者共享原 `LibraryRepositoryContext`、索引、persistence helpers 和事务，
  Store 只保留兼容端口及低层 stable-ID 视频/缓存/播放状态持久化 owner。
- Phase 5：确认“契约拆分完成”；`PlayerRuntimeBackend`/`PlayerSurfaceRenderer` 已独立注入，具体
  runtime/surface adapter 暂不继续拆，保留正式 MediaKit Texture 和 Windows native 默认行为。
- Phase 6：候选查询已接入 `LibraryQueryController`/Facade；`dataRevision` 在主库成功写入后推进，
  FTS5 派生索引按需重建，失败安全回退完整 Dart 查询。真实 11,194 条库的隔离副本基准：完整筛选
  平均 75.63ms，候选+最终校验 0.484ms，冷索引建立 430.17ms，结果集合一致，因此保留大库启用策略。
- 保护：schema v2、`FilterQuery`/`TagQueryService` 语义、来源 filtered queue、缩略图/媒体队列、
  stable videoId 用户数据、正式播放器后端和 Navigator/显式 Route 不变；未增加路由框架。
- 已验证：`flutter analyze` 无问题；Phase 3–6 focused、播放器 focused、架构契约和隔离真实大库查询基准通过；
  全量 `flutter test -r compact` 为 600 项通过、4 项按环境/能力跳过；`flutter build windows --debug` 成功生成
  `build/windows/x64/runner/Debug/local_tag_player.exe`。本轮未提交或推送，保留工作树中的全部用户未提交改动。
- 最新 Debug 窗口验收：实际进程来自 `E:\LocalTagPlayer\build\windows\x64\runner\Debug\local_tag_player.exe`；
  短按 `L` 快进后画面与进度继续前进，全屏播放列表单击第二项可更新选中态，退出播放器返回媒体库后重新进入
  可正常重建普通播放器、队列和 Texture，未见全屏/旧资源残留。

# 2026-08-16 · 播放器命令、释放与异步身份对抗式修复（完成，窗口验收受构建阻断）

- 修复方向：native seek 只在已进入后端后计时；超时会封锁当前 `PlayerService` 代次，唤醒并失效尚未派发的
  `open/seek/stop`，不与旧 seek 并发；seek worker 收敛失败并清除乐观进度。
- 完成：释放链对 `dispose`、`released`、事件取消和诊断日志分别保留有界等待/失败阶段；普通属性读取和页面
  `getMpvProperty()` 统一超时，避免健康、GPU、打开确认和释放诊断永久占用任务。
- 完成：NVIDIA 探测、联合滤镜、运行状态轮询、CPU 回滚和健康采样统一校验
  `videoId + mediaGeneration + requestRevision`；旧媒体采样在新媒体切换后不得写回当前状态。
- 保护：schema、FilterQuery/TagQueryService、来源 filtered queue、PlayerBackend 公共接口、缩略图/媒体队列和用户数据不变；
  超时后当前 Player 进入终止态，只允许释放并由上层创建新会话。
- 验证：播放器 focused 与目标源码契约 46 项通过，直接相关 analyzer 通过；Windows Debug 构建被工作树中既有
  Library 稳定身份编译错误阻断，未把 8 月 10 日旧安装包的窗口烟测结果冒充为本轮验收。

# 2026-08-16 · 全屏筛选结果队列被原生视频表面覆盖（完成）

- 现象：全屏模式下显示播放列表时，显式 child HWND 路径仍可能被视频表面覆盖或抢走列表命中区域。
- 修复：全屏队列显示前按实际右侧矩形串行提交原生 airspace 裁剪；隐藏、退出全屏和其它 Flutter
  弹层关闭时按优先级恢复裁剪，过期显示请求由单调代次丢弃；默认 MediaKit Texture 路径保持空操作。
- 保护：schema、FilterQuery/TagQueryService、来源 filtered queue、PlayerBackend 公共接口、缩略图/媒体队列
  和用户数据不变；全屏队列仍为根 Stack 覆盖层，不改变视频尺寸。
- 验证：全屏几何 focused/widget、HWND airspace、PlayerService focused 测试及独立 Windows Debug 构建通过；
  标准 Debug 构建仍被 PID 21368 锁定，未强制结束用户进程。下一步为真实窗口全屏队列点击/截图验收。

# 2026-08-16 · 播放器对抗式时序与事件归属检查（完成）

- 完成：`open/stop/seek/dispose` 共用 PlayerService 媒体命令尾链；失败或 missing open 会
  停止旧媒体；最后一项删除在退出路由前不把页面队列变为空。
- 完成：进度条乐观位置有代次保护和超时回退；事件 bridge 按 stable `videoId + generation`
  重绑；KeyUp 按实际逻辑键收敛，失焦时取消输入会话。
- 保护：schema、FilterQuery/TagQueryService、来源 filtered queue、PlayerBackend 公共接口、
  缩略图/媒体队列和用户数据不变；重命名重开仍保留播放进度与稳定身份。
- 验证：播放器 focused tests、相关 widget tests、播放器目标源码 `flutter analyze` 和隔离
  Windows Debug 构建已通过；标准构建仍被 PID 21368 锁定，未强制结束用户进程。

# 2026-08-16 · 架构演进 Phase 1/2 稳定身份迁移（完成，Phase 3 进行中）

- 完成：`VideoIdentityIndex` 以 stable `videoId` 为主索引、pathKey 为同步辅助视图；标签关系
  新增 videoId 主索引；删除、改名、missing relink 和合并删除的生产命令切换到 stable-ID API。
- 完成：SQLite schema 版本升至 2；旧 path-keyed `videos/video_tags` 在同一事务中换表迁移为
  `videos.video_id PRIMARY KEY`、`videos.path UNIQUE`、`video_tags(video_id, tag_id, source)` 主键；
  迁移幂等、孤立关系失败关闭并保留旧数据。
- 保护：FilterQuery/TagQueryService 语义、来源 filtered queue、PlayerBackend、缩略图/媒体队列、
  用户数据和已有播放器改动保持；页面 path 读取视图暂作为迁移兼容层保留。
- 验证：Phase 2 migration/index focused、旧库 Store 启动、改名、fingerprint relink、missing
  relink、architecture contract、`flutter analyze` 通过；下一步拆分 LibraryStore 逻辑并保持单库统一事务。

# 2026-08-16 · 短按快进回到原关键帧（进行中）

- 现象：单次按下快进偶发先移动到目标，随后回到原点；长按才能继续到后面。
- 根因：短按只走 `absolute+keyframes`，长 GOP 的前置关键帧可能等于当前落点；位置栅栏不能改变后端实际落点。
- 修复方向：保留短按即时关键帧预览，KeyUp 在无 `KeyRepeat` 时补一次精确 seek；长按仍 latest-only 预览。
- 保护：不修改 schema、FilterQuery/TagQueryService、来源 filtered queue、PlayerBackend 接口或播放/暂停意图。
- 下一步：完成 focused/analyze/build，停止编辑后独立只读审查并只提交本任务文件。

# 2026-08-16 · 架构演进 Phase 0 基础门禁（完成，Windows 构建待解锁）

- 目标：建立架构 ADR、依赖方向门禁、架构指标入口和不含用户数据的旧库 fixture，为 stable-ID
  与 schema migration 提供可重复基线。
- 保护：本轮不修改 schema、FilterQuery/TagQueryService、来源 filtered queue、PlayerBackend、
  thumbnail/media queue、播放器行为或用户数据；保留当前工作树中的播放器相关未提交改动。
- 验证：Phase 0 focused contract、既有架构 contract、`flutter analyze`、指标脚本和 `git diff --check`
  通过；Windows Debug 构建因 PID 21368 占用 Debug exe 触发 `LNK1168`，未强制结束用户进程。
- 下一步：关闭 PID 21368 后重跑 `flutter build windows --debug`；随后进入 Phase 1 stable-ID 索引设计，
  仍需保持 schema migration 与当前播放器行为隔离。

# 2026-08-16 · 播放器列表删除返回后的主界面刷新延迟（完成，构建待解锁）

- 现象：播放器右侧队列删除视频后返回主界面，旧视频要等较长时间才从对应结果中消失。
- 根因：播放器 Route 返回后的删除差量刷新位于原生资源释放、最多 15 秒等待、内存采样和进度刷盘之后。
- 修复：Route 弹回并恢复媒体库语义后立即发布 stable `videoId` 差量；释放、采样和刷盘继续在尾部执行。
- 保护：不修改 schema、FilterQuery/TagQueryService 语义、来源 filtered queue、回收站事务或用户数据。
- 验证：focused/全量 `flutter test`、`flutter analyze` 通过；Windows Debug 构建因 PID 26180
  占用 Debug exe 触发 `LNK1168`，未强制结束用户进程。
- 下一步：关闭 PID 26180 后重跑 `flutter build windows --debug`；本次代码审查和提交不依赖强杀进程。

# 2026-08-16 · 播放器快进位置回跳竞态（进行中）

- 现象：快进/快退偶发先移动到新位置，随后被旧位置状态回写到操作前落点。
- 根因：seek 命令与位置流不是同一时序；后端可能在 seek 返回后投递 seek 前已排队的旧
  `time-pos`，精确与交互式 seek 还可能分别进入后端。
- 修复：`PlayerService` 串行化两类 seek；新增目标栅栏，在确认窗口内屏蔽迟到旧位置，超时
  后回退真实后端值。新增 reconciler 与服务边界 focused 回归。
- 保护：不修改 schema、FilterQuery/TagQueryService、来源 filtered queue、PlayerBackend
  接口、播放/暂停意图或用户数据。
- 下一步：完成 focused/analyze/build，停止编辑后独立只读审查并只提交本任务文件。

# 2026-08-16 · 相似视频扫描跨页面复用与播放器后台让渡（完成）

- 根因：视觉扫描 Future、取消代次和进度只由相似视频页面持有，页面退出立即取消；再次进入又从头
  执行，播放器也只冻结部分缩略图任务。
- 修复方向：新增媒体库 Route 级 `VideoSimilarityScanController`，首次进入自动执行，离开页面只降为
  后台速率并保留 Future，后续进入订阅共享进度/结果，显式刷新才重跑；删除/数据变化失效旧结果但不自动
  重扫。播放器进入时通知 controller 等待视觉调度，并暂停 MediaDetailsService 新 FFprobe，退出后按原状态恢复。
- 保护：不改变 schema、FilterQuery/TagQueryService、来源 filtered queue、PlayerBackend、候选算法、
  删除/回收站/标签合并事务或持久化视觉签名缓存；页面只做状态投影和 stable ID 局部对账。
- 验证：相似视频页面/播放回程、架构契约和相似服务 focused tests 通过；全量 `flutter test` 为 564 项通过、
  3 项既有条件跳过；`flutter analyze` 与 `flutter build windows --debug` 通过；隔离 Debug 实例可启动并
  正常关闭。当前环境没有桌面点击/截图控制器，未冒充完成真实页面点击证据。
- 下一步：停止编辑后检查只 stage 本任务文件，提交中文变更并推送当前跟踪分支。

# 2026-08-15 · 相似视频临时预览缓存竞态（进行中）

- 现象：真实窗口相似视频页报 `PathNotFoundException`，缺失路径位于 `hover_preview/*.jpg`，整轮视觉复核被页面显示为失败。
- 根因：`ThumbnailService` 将短生命周期临时帧 `File` 路径交给视觉签名；并发取帧超过 24 项时，LRU/外部清理可在 dHash 读取前删除该 JPEG。
- 修复：新增 `similarityPreviewBytesFor`，在缓存服务边界立即读取字节快照并有限重试；dHash 改为消费字节，单帧失败只跳过，不再向页面抛出路径异常；补 LRU 竞态回归测试。
- 保护：FFmpeg 边界、相似取帧有界并发、缓存有效性、视觉阈值、删除/回收站/标签合并和播放器来源队列不变。
- 下一步：完成 focused/全量测试、analyze、Windows Debug 构建和停止编辑后的只读审查后推送。

# 2026-08-15 · 相似视频视觉评分与排序校准（进行中）

- 根因：首帧 dHash 曾可直接形成候选组，且分组分数取组内最佳边；单个巧合画面会显示 100%，而真实副本的剪辑/编码差异又可能被低百分比掩盖。
- 修复方向：首帧只保留为预筛；完整视觉签名只比较 30%/50%/70% 中段采样点，要求主体采样点在固定小时间偏移下全部命中并对省略点加惩罚；组分数改取最弱匹配边，UI 明确显示“视觉匹配度”而非概率。
- 排序：视觉候选按距离升序（等价于匹配度百分比降序）稳定展示，确定指纹重复组顺序不变；算法版本升至 v5，使旧的视觉缓存自动失效重建。
- 保护：不改变文件级指纹、FilterQuery/TagQueryService、来源 filtered queue、删除/回收站/标签合并事务；视觉结果仍只供人工复核，不自动删除。
- 下一步：完成 focused/全量测试、analyze、Windows Debug 构建（若旧进程仍锁定则记录阻塞），停止编辑后做独立只读审查并推送。

# 2026-08-15 · 相似视频难例召回与待复核分层（进行中）

- 现象：v5 只接受三个中段采样点全部通过，棘手的剪辑/重编码副本容易被静默丢弃；此前只剩难例后页面看不到候选。
- 修复：保留高置信门槛，同时增加有界 review 距离（主体证据部分通过且标题或时长/画幅/大小元数据足够接近）的候选；UI 标记“疑似内容近重复（待复核）”，不改变删除语义。
- 保护：公共片头/片尾仍不参与主体评分；review 组不能自动删除，仍须人工确认；文件、标签、收藏、回收站事务与播放器来源队列不变。
- 下一步：完成全量验证、构建和独立审查后推送。

# 2026-08-15 · 相似视频尾部负载与取帧公平队列（完成，构建待解锁）

- 根因补充：唯一视频 worker 仍按候选发现顺序排队，长视频/大文件可能集中在尾部；相似取帧 FIFO 可能连续处理同一视频的多个时间点；签名完成后的 SQLite 写入还会占住取帧 worker。
- 修复：深度签名按预计时长/文件大小使用最长任务优先；ThumbnailService 相似取帧队列跨视频轮转；签名 metadata 写入改为独立串行后台链，不再阻塞 FFmpeg worker。
- 保护：FFmpeg 并发上限、播放暂停/取消、缓存有效性和删除事务不变；只调整任务分配与派生缓存写入时机。
- 验证：相似服务和取帧队列 focused tests、全量 `flutter test`（558 项通过，3 项既有条件跳过）及 `flutter analyze` 通过；
  Windows Debug 构建因 PID 29740 锁定当前 Debug exe 触发 `LNK1168`，未强杀用户进程；已完成停止编辑前审查。

# 2026-08-15 · 相似视频后半段取帧调度收敛（完成，构建待解锁）

- 现象：深度取帧进入后半段时，某个慢视频会拖住整个候选对批次；其它已完成任务不能立即补位，页面因此长时间不动。
- 根因：深度阶段以候选对为批次等待；同一视频虽已合并 in-flight，但进度仍按候选对递增，慢对造成批次屏障和重复等待感。
- 修复：改为按 stable `videoId` 建立唯一签名任务池，以 2–4 个连续 worker 领取下一条任务；每个视频完成后立即补位，候选比较延后在内存 dHash 上完成。候选规则、视觉阈值、取消和播放器让渡语义不变。
- 验证：相似服务、取帧队列、状态组件 focused tests 通过，全量 `flutter test`（557 项通过，3 项既有条件跳过）和
  `flutter analyze` 通过；Windows Debug 构建仍被当前运行的 Debug exe 触发 `LNK1168` 锁文件阻塞，未强杀用户进程。

# 2026-08-15 · 相似视频深度取帧进度收敛（完成）

- 现象：候选首帧预筛已到 `129185/131072` 时，页面仍显示“预计剩余 1 秒”，但后续深度取帧候选尚未执行完，
  造成最后阶段长时间停留且用户无法区分排队任务。
- 根因：快速预筛和深度时序取帧共用 `comparingCandidates` 计数与吞吐率；深度任务只在批次完成后才递增，
  ETA 却按前面近千项/秒的廉价路径外推。
- 修复：新增独立 `extractingSignatures` 阶段，以待执行的深度候选为总量，阶段切换时重置吞吐率与 ETA；状态卡
  直接显示“取时序帧 x/y”，确保扫描 Future 只有在所有深度批次汇合后才结束；非零剩余时间向上取整，避免
  最后一个批次仍在运行时显示 `0 秒`。
- 验证：服务进度、状态组件、全量 `flutter test`（556 项通过，3 项既有条件跳过）和 `flutter analyze` 均通过；
  Windows Debug 重编译被当前运行的 Debug exe 锁文件阻塞，未强杀用户进程，需关闭实例后重试。

# 2026-08-15 · 相似视频视觉签名持久化缓存（完成）

- 目标：把视觉签名从单次扫描内存缓存提升为可复用的派生缓存，第二次进入相似视频页时跳过重复取帧。
- 方案：复用现有 `metadata` 表保存 `cache.visual_signature.<videoId>`，记录算法版本、dHash 序列和
  mediaFingerprint/size/mtime；读取前严格校验媒体快照，算法升级或文件变化自动失效。
- 性能：进入相似视频页时按候选涉及的 stable videoId 批量预热签名，避免逐视频 SQLite 查询；未命中时
  才回退到现有有界取帧队列并异步保存新签名。
- 保护：删除事务同步清理签名 metadata；签名晚到写入在 SQLite 事务内确认 stable videoId 仍存在；缓存
  故障只回退本轮重算，不阻断媒体库。用户标签、收藏、播放队列和文件回收站语义不变。
- 验证：持久化命中、批量预热、媒体快照失效、删除清理回归已补；focused/全量测试、`flutter analyze`、
  Windows Debug 构建和停止编辑后的独立只读审查均通过。

# 2026-08-15 · 相似视频扫描吞吐与 ETA 估算（完成）

- 根因：视觉比较循环逐候选等待，候选两端首帧读取也串行；页面进度固定每 64 项更新，无法解释阶段耗时或剩余时间。
- 修复：首帧预筛两端并行；深度签名按 CPU 档位以 2–4 个候选批次并发，并按 videoId 合并 in-flight 取帧任务；
  进度记录阶段累计耗时、平滑吞吐率和预热后的 ETA，页面每秒局部更新耗时/速度/预计剩余。
- 保护：不改变候选通道、视觉阈值、删除事务、标签/收藏合并、filtered queue 或数据库结构；播放器活跃时仍由
  `shouldYield` 和相似取帧队列让渡资源，离开页面仍可取消排队任务。
- 验证：相似服务/状态组件/取帧队列/页面回程/架构契约 focused tests、完整 `test/widget_test.dart`（210 项）、
  `flutter analyze` 和 `flutter build windows --debug` 均通过；真实窗口启动请求被已运行的安装版单实例接收，
  未关闭用户进程强行冒充 Debug 运行时点击结论。

# 2026-08-15 · 相似视频视觉复核前台加速与播放资源让渡（完成）

- 根因：视觉复核的深度签名对每个视频的多个时间点逐个取帧，候选两端也逐个等待；所有取帧还复用
  播放器悬停预览的单并发 latest-only 队列，大库会把 FFmpeg 成本串成几十分钟，并可能与播放器争用。
- 修复：ThumbnailService 增加独立相似视频批量取帧队列；相似视频页前台按 CPU 以 2–4 路有界并发运行，
  同一视频的多个采样点和候选两端并行取帧。离开页面取消等待中的批量任务；若仍有后台调用则降为单并发。
  播放器打开时页面让渡前台资格，播放器的缩略图暂停合同同时冻结相似视频批量队列，候选调度等待播放结束后恢复。
- 保护：不启动无界 FFmpeg 进程，不改变候选规则、删除事务、标签/收藏合并、来源 filtered queue 或数据库结构；
  已启动的单个 FFmpeg 任务自然收尾，排队任务可取消，避免旧结果写回页面。
- 验证：新增相似取帧前台并发/后台降速/播放暂停回归与页面/服务调度契约；待完成本轮 analyze、focused tests、
  Windows Debug 构建及停止编辑后的独立审计。

# 2026-08-15 · 相似视频扫描阶段进度可见（完成）

- 现象：页面只显示“视觉复核 准备中”和中心转圈；候选构建阶段没有总量或当前进度，用户无法判断
  搜索是否仍在工作。
- 修复：视觉扫描进度拆为“建立视觉候选”“首帧预筛”和“时序取帧”三个阶段；服务在候选构建、廉价预筛和
  深度批次汇合时上报阶段进度，顶部摘要显示阶段/当前项/总量，中部状态卡增加线性进度条。
- 验证：补充三阶段进度回归、状态组件 widget 测试和页面挂载契约；相似视频 focused tests、架构契约、
  `flutter analyze`、`flutter build windows --debug` 均通过。真实窗口启动仍受已有安装版单实例转发影响，
  未关闭用户实例强行冒充新构建做点击结论。

# 2026-08-15 · 相似视频视觉复核可收敛与召回兜底（完成）

- 根因：视觉复核对未缓存视频调用 `ensureThumbnailFor`，会把播放器兜底解码扩散到大库；删除候选后
  又自动重启全库取帧，导致候选清空后仍长时间显示“搜索中”。候选全局上限实际只覆盖少量邻居，
  且时长/画幅硬门槛会漏掉改名、剪辑、裁切和加黑边副本。
- 修复：视觉任务支持取消与进度回调；删除时取消旧任务、仅局部移除并标记“待重新计算”，不再自动
  重启万级全库复核。视觉复核只读已有缩略图，深度 FFmpeg 取帧有单侧缓存/全局预算，禁止播放器兜底
  解码风暴；候选增加归一化标题、宽松时长、最近画幅变化和双向最近帧距离通道。
- 验证：新增标题缺失时长、画幅漂移、取消收敛和删除不自动重启回归；相似服务/页面 focused tests、
  架构/删除契约、媒体库 Store 回归和侧栏/回收站 widget tests、`flutter analyze`、
  `flutter build windows --debug` 均通过。真实窗口未能指向新 Debug 二进制：应用单实例把启动请求转发到
  已运行的安装版进程；未关闭用户实例或冒充新构建做点击结论。

# 2026-08-15 · 分层 AXTree 复现与真实跨 DPI 门禁（进行中）

- 硬件阻塞：Windows 仍只检测到 `DISPLAY1`（2560×1440），没有第二显示器；没有运行稳定性矩阵，
  `PhysicalCrossDpiStatus` 继续保持未通过。
- 分层 harness：在前一版语义树基础上增加 240 个媒体卡片、自动滚动脉冲、播放器式 route、
  `BlockSemantics`、24 项来源队列和自动返回媒体库，循环 3 次；仍只使用独立 artifacts profile。
- 3.44.4/3.41.9 与 observer/no-observer 四组均构建、运行、正常退出，日志均为 0 条
  `Failed to update ui::AXTree`；observer 的 accessibility state 已实际观察到媒体库、播放器、
  `BlockSemantics`、队列和返回节点交替挂载。
- 结论：问题仍未在独立 harness 中复现，不能把 SDK/engine 升级写成已验证修复；继续保留生产
  `Semantics`、`ExcludeSemantics`、`BlockSemantics` 和播放器 route 语义。
- 下一步：接入缩放比例不同的第二显示器后，执行真实移窗/全屏/返回/释放门禁；AXTree 继续只增加
  一层应用形状并保持四格 A/B。

# 2026-08-15 · 真实跨 DPI 与 AXTree 独立门禁（进行中）

- 硬件阻塞：本机仍只有 `DISPLAY1`（2560×1440），没有第二显示器；真实跨物理 DPI 不能执行，
  `PhysicalCrossDpiStatus` 不得伪造为 `passed`。
- AXTree 最小复现：在 `artifacts/ax_tree_repro_20260815/` 建立独立 Flutter Windows harness，
  以 800 个全部挂载的语义节点交替切换到 6 个节点，并执行 24 次无动画 route replacement。
- SDK/engine A/B：Flutter 3.44.4（engine `a10d8ac...`）与隔离 Flutter 3.41.9（engine `42d3d75...`）
  均完成 Debug 构建；两版在桌面 observer 和无 observer 条件下均为 0 条 `Failed to update ui::AXTree`。
- 结论：最小 harness 尚未复现主应用大 profile 的 188 条告警，不能据此宣称 SDK 升级修复；当前证据仍指向
  大规模应用语义树、hydration/route 时序和桌面 observer 的组合，保留现有 `Semantics`、`ExcludeSemantics`
  与播放器 `BlockSemantics`。
- 下一步：接入缩放不同的第二显示器，真实移窗/全屏/返回并重新执行稳定性矩阵；AXTree 继续缩小
  “大语义树 + observer + route”复现范围，不升级全局 Flutter SDK。

# 2026-08-15 · 既有全量单测与跨 DPI/AXTree 收尾（本轮完成）

- 目标：单独收口前一轮全量 `flutter test` 暴露的 3 条既有失败，同时保持播放器来源队列、页面可达性和
  无障碍语义入口不变；第二显示器可用后再执行真实跨物理 DPI 门禁。
- 单测修复：继续观看视图拆出行/卡片叶子；相似视频页拆出状态展示、候选组/行和缩略图叶子；播放/删除
  契约改为读取实际候选行文件并校验带 `playlist` 的删除回调。架构契约同步覆盖拆分后的真实组件边界，
  没有放宽历史预算；侧栏、本地目录和视频网格中同一门禁暴露的后续预算超额也按叶节点迁移收口。
- 验证：全量 `flutter test` 结果为 542 项通过、3 项跳过，日志末尾为 `All other tests passed!`；
  `flutter analyze`、`flutter build windows --debug` 和 `flutter build windows --release` 均通过。
- 真实窗口：使用全新隔离 `LOCAL_TAG_PLAYER_DATA_DIR` 启动当前 Debug 构建，实际点击“相似视频”进入
  空状态页（0 组），再点击返回媒体库，页面仍保持空库状态；窗口正常关闭，未触碰用户 profile。
- 跨 DPI：当前只有 `DISPLAY1`（3840×2160），真实跨屏无法执行，发布状态继续为
  `pending-physical-cross-dpi`；已有 100%/125%/150%/200% 模拟 metrics 只作为自动化证据。
- AXTree：Flutter stable 为 3.44.4（framework `ad70ec...`，engine `a10d8a...`）；带桌面控制的真实窗口
  复现 188 条 `accessibility_bridge.cc:114` AXTree stale-node 错误，独立 profile 无桌面控制对照为 0 条。
  当前建议先做小语义树 + route/hydration 的最小复现，再在隔离 SDK/engine 版本上 A/B，不删除 `Semantics`、
  `ExcludeSemantics` 或播放器 `BlockSemantics`。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、缩略图/媒体队列、
  stable identity 和用户数据未改；`D:\video` 仍只读，写入型测试使用可丢弃 profile。
- 证据：`artifacts/three_failures_20260815_flutter-test-final.log`、`artifacts/desktop_gate_20260815_01/`、
  `artifacts/desktop_gate_20260815_02_no_cua/`；日期化结论见
  `docs/history/qa/2026-08/full_gate_20260815.md`。
- 下一步：接入第二显示器并确认两块屏缩放不同后，运行稳定性矩阵并通过桌面实点记录真实移窗/全屏/返回；
  AXTree 另开隔离 SDK/最小复现评估，不在本任务中升级全局 Flutter SDK。

# 2026-08-15 · 相似视频合并用户数据后删除（完成）

- 目标：相似候选删除前，把源视频收藏和 `source=manual` 自定义标签并入保留视频；目标已有
  数据只做并集，不覆盖；folder 派生标签不复制。
- 实现：两条候选自动选择另一条；多条候选显示保留目标选择框；新增 Repository 原子命令，
  在同一 SQLite 事务中更新目标视频并删除源视频，文件仍先移入系统回收站。
- 验证：新增 LibraryStore 合并删除回归，覆盖收藏、manual 标签、folder 标签隔离和源关系删除；
  focused store/executor、架构契约与 `flutter analyze` 已通过；`flutter build windows --debug`
  被 Explorer 启动且仍在运行的 Debug `local_tag_player.exe` 锁定，返回 LNK1168，未强制结束用户进程。
- 下一步：完成停止编辑后的独立审计，提交并推送当前分支；关闭该窗口后重跑构建门禁。

# 2026-08-15 · 压测与性能全测标准（文档完成）

- 目标：为后续一次全测建立 Windows 主基线，覆盖大库加载/扫描、标签筛选、过滤队列、播放器、
  缓存诊断、资源尾部和隔离目录压力；不把平均值或 Debug 耗时冒充发布性能结论。
- 方案：新增 `docs/qa/performance_full_test_standard.md`，统一 profile/release-like 构建、P50/P95/P99、
  冷热启动、帧预算、资源增长、硬失败/Warning/Pass 裁决和报告字段；复用现有 benchmark、seek 矩阵、
  双后端稳定性、增删目录压力与真实库播放器长跑入口。
- 保护：不修改 schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、缓存队列、
  stable identity 或用户数据；真实媒体根只读，写入型压力测试必须使用可丢弃 profile。
- 验证：完成文档交叉检查；尚未执行真实 L3 全测。下一步按标准冻结机器/样本/seed，先跑 L0–L2 建立首个
  可比较基线，再执行隔离增删压力和 30 分钟播放器长跑。

# 2026-08-15 · 删除视频同步清理缓存诊断 metadata（完成）

- 根因：相似视频等入口已通过统一删除命令清理文件、视频行、标签关联、备份快照和缩略图，
  但主库 `metadata` 中以 stable `videoId` 命名的 `cache.thumbnail.*` 与 `cache.media_details.*`
  状态未随视频行删除，可能留下孤立诊断记录。
- 修复：`LibraryStore.deleteVideo` 将两类 metadata 的定向删除加入与标签关联、视频行相同的
  SQLite batch；只删除目标视频的键，不影响其它视频或全局 metadata。
- 验证：新增“删除视频移除缓存诊断 metadata”回归测试，`library_store_test.dart` 与文件命令
  执行器 focused tests、`flutter analyze` 通过；`flutter build windows --debug` 已尝试，但被
  Explorer 启动且仍在运行的 Debug `local_tag_player.exe` 锁定，返回 LNK1168，未强制结束用户进程。
- 下一步：完成停止编辑后的独立审计，提交并推送当前分支；构建门禁待关闭该窗口后重跑。

# 2026-08-15 · 用户视频删除统一移入回收站（完成）

- 盘点：媒体库网格/列表、收藏、最近播放、本地目录、相似视频、批量选择和播放器右侧队列
  最终都经过 `LibraryFileCommandExecutor`；此前 `DeleteVideoCommand.moveLocalFileToTrash` 与
  删除确认/设置页允许“仅移出媒体库”，导致文件可能留在原目录。
- 修复：删除命令移除绕过布尔值，所有用户视频删除固定按“移入系统回收站 → 删除 Repository
  记录 → 清理可重建缩略图缓存”执行；确认框和设置页删除“仅移出媒体库”选项，保留“不再提示”。
  旧设置 JSON 键继续以 `true` 回写，避免旧配置恢复保留文件语义。
- 例外边界：缺失/不可读自动清理仍只删除数据库记录；缩略图、FFmpeg 临时输出、更新下载包和
  测试临时目录继续使用直接清理，不属于用户视频回收站合同。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、stable
  videoId、数据库删除顺序和用户数据绑定未改变；平台失败时在删除 Repository 前抛错并保留记录。
- 验证：文件执行器、相似视频/播放器返回、删除弹窗/设置、架构契约和 PlaybackSettings focused
  tests 通过；`flutter analyze`、`flutter build windows --debug`、真实 Windows 回收站 smoke 与
  隔离数据目录启动响应检查通过。全量 `flutter test` 仅保留既有的架构迁移预算和
  `video_similarity_page.dart` 行数治理两条基线门禁失败；本次删除合同 focused 测试未失败。
- 下一步：停止编辑后完成只读审计，提交并推送当前分支。

# 2026-08-15 · 相似视频播放器删除返回局部对账（完成）

- 根因：播放器右侧删除已通过原有确认、文件/数据库/缩略图事务更新 Store，但相似视频页仍
  持有进入播放器时的候选报告快照；Route 返回回调此前只清除行级动作状态，没有从报告移除已删行。
- 修复：Route 返回立即比较报告分组中的 stable `videoId` 与 Store 当前索引，按
  `VideoSimilarityReport.withoutVideo` 局部移除失效候选；下一帧再检查一次，覆盖宿主延后发布
  内存索引的时序，不触发整页重建或视觉全量复核。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、缩略图/媒体
  队列、删除确认/事务和用户数据未改变。
- 验证：新增播放器返回局部对账契约；相似页面/服务 focused tests 15 项、`flutter analyze`、
  `flutter build windows --debug`、隔离数据目录启动响应检查均通过。真实入口点击仍需人工确认。
- 下一步：从新 Debug 构建进入相似视频，播放任一候选，在播放器右侧删除另一条候选后返回，确认对应
  行立即消失且剩余候选、滚动位置和缩略图不整体重载。

# 2026-08-15 · 相似视频扫描期间删除入口恢复（完成）

- 根因：行级删除按钮复用了视觉扫描全局禁用门控；该门控原本用于防止旧扫描快照回流，
  但实际把已经展示的候选也锁死，用户看到灰色删除图标。
- 修复：删除不再受 `_visualScanning` 阻塞；删除成功后立即按 stable `videoId` 局部移除当前行，
  视觉扫描晚返回的结果会过滤已删除 ID，避免旧候选重新出现；扫描和删除继续复用原有文件、
  数据库和缩略图清理事务。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、用户数据和
  删除确认/回收站策略未改变；只移除错误的 UI 禁用条件。
- 验证：删除期间播放/删除门控、旧扫描快照过滤、相似服务 focused tests、`flutter analyze`、
  Windows Debug 构建和隔离数据目录启动均通过。
- 下一步：从新 Debug 构建打开相似视频，在视觉复核转圈时删除一条候选，确认按钮可点击、行立即
  消失且扫描完成后不会回流。

# 2026-08-15 · 相似视频入口首帧响应优化（完成）

- 根因：相似视频页 `initState` 立即启动视觉复核；候选构建在首个异步边界前同步遍历和排序
  大量时长相近视频，路由首帧被阻塞，导致从主界面进入耗时明显。
- 修复：页面先完成首帧挂载，再通过 post-frame callback 启动视觉扫描；候选构建改为异步函数，
  首次和每 8 个时长索引主动让出事件循环，保留现有候选上限、候选覆盖和缩略图队列边界。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、视觉召回
  条件、删除事务和用户数据未改变；扫描结果仍在当前页面内存中生成。
- 验证：新增首帧调度与候选异步构建 focused 契约；相似页面/服务 focused tests、`flutter analyze`、
  Windows Debug 构建和隔离数据目录启动均通过。
- 下一步：从新 Debug 构建点击主界面“相似视频”，确认页面先显示确定重复组，再异步显示视觉复核；
  首次进入不应再等待视觉候选构建完成。

# 2026-08-15 · 相似视频滚动安全区与候选召回复核（完成）

- 根因：相似视频 `ListView` 的 Windows overlay Scrollbar 直接覆盖卡片右边缘；视觉复核还存在
  8 邻居/视频、6% 时长窗口、0.32 首帧硬拒绝和两侧未缓存仅 256 对深度回退等静默漏检条件。
- 修复：列表内容右侧预留 18px 安全区；候选改为 24 邻居/视频并交错综合分、时长近邻和大小近邻，
  时长窗口放宽到 12%、画幅容差放宽到 0.12；首帧预筛提高容错，只有两侧都未缓存时才消耗
  4096 对有界深度回退额度；视觉签名改为多个时间点且允许单个取帧失败，继续只生成当前页内存结果。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、缩略图队列、
  删除事务和用户数据未改变；视觉结果仍只作为人工确认候选，不自动删除。
- 验证：新增 12% 时长漂移候选、部分视觉签名和滚动安全区 focused 契约；相似服务/页面
  focused tests、`flutter analyze`、Windows Debug 构建均通过；隔离数据目录启动 8 秒保持响应。
  接下来只做停止编辑后的独立只读审查。
- 下一步：从新 Debug 构建打开相似视频，确认滚动条不再压住卡片；对不同编码、不同文件大小、
  片头/片尾有差异的重复视频重新计算，核对候选覆盖和视觉复核统计。

# 2026-08-15 · 相似视频扫描期间播放入口恢复（完成）

- 根因：相似视频页首次展示确定重复组后会后台执行视觉复核；行级播放与删除共用
  `_visualScanning` 禁用门控，导致确定重复组的播放按钮显示灰色且点击无响应。
- 修复：视觉复核只追加内容近重复候选，不会改变已展示候选组；播放入口始终复用当前组的
  独立 filtered queue。删除仍在扫描期间锁定，避免视觉结果与删除后的候选快照竞态。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend、
  缩略图队列、删除事务和用户数据未改变。
- 验证：新增扫描期间播放门控契约；相似服务/播放返回 focused tests、`flutter analyze`、
  Windows Debug 构建均通过；停止编辑后将进行独立只读审查和隔离数据目录启动检查。
- 下一步：从新 Debug 构建打开相似视频，在视觉复核转圈时点击确定重复组的播放按钮，确认进入
  当前候选组播放器；视觉复核候选仍待扫描完成后允许删除。当前环境缺少可靠桌面鼠标命中工具，
  真实点击需人工完成。

## 2026-08-15 · 删除后的列表局部差量刷新（完成）

- 盘点：主媒体库网格/列表、收藏、最近播放、本地目录和相似视频页都有视频删除或列表
  清理入口；播放器右侧队列已有 stable `videoId` key；标签管理当前只检查删除影响，不执行
  标签或视频删除。此前主库删除会提升 revision 后走全量筛选，`VideoGrid` 还会重置增量批次
  并把滚动位置跳回顶部。
- 修复：删除入口传递 stable ID 差量，`FilterStateSource` 只移除对应结果并保留未变化对象；
  主库网格用 stable key 和滚动锚点保持视口，最近播放/本地目录/相似分组补齐 stable key 与
  `findChildIndexCallback`。最近播放清理也改为只提交 changed video 差量；相似页删除先局部
  移除分组，再在后台进行有界视觉复核。
- 保护：删除事务、回收站策略、schema、FilterQuery / TagQueryService 语义、来源 filtered queue、
  PlayerBackend、缩略图队列和用户数据边界未改变；连续删除会合并 pending stable ID，避免旧项
  从缓存结果短暂回流。
- 验证：删除差量查询、相似报告局部移除、列表入口 stable key 契约、文件删除顺序、媒体卡片菜单、
  相似检测 focused tests，以及 `flutter analyze`、Windows Debug build 均通过；使用隔离数据目录
  的 Debug 前台启动成功并正常退出；真实桌面点击需在新 Debug 构建中人工确认删除后滚动位置和
  相邻卡片不跳回首屏。
- 下一步：打开媒体库网格/列表、收藏、最近播放、本地目录和相似视频，分别删除视口中间项，确认
  未删除项目、当前滚动位置和缩略图不整体重载。

## 2026-08-15 · 相似视频播放返回动作状态（完成）

- 根因：相似视频行的 `_actingVideoIds` 由 `onPlay` Future 的完整生命周期清除；播放 Route
  弹回后，父页面仍等待原生播放器释放、播放进度刷盘和缩略图恢复，导致已返回的行继续显示
  加载圆环。相似报告本身没有重新挂载或重算。
- 修复：播放协调链在 Route 弹回的第一时间通知相似页清除当前行动作状态；既有播放器资源
  释放、进度刷盘、缩略图恢复和候选组 filtered queue 均保持原顺序与边界。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、缩略图/媒体队列、
  PlayerBackend、标签、收藏、播放记录和媒体文件未改变。
- 验证：新增返回时序架构回归，相关页面 `flutter analyze` 通过；随后执行 Windows Debug
  构建并做停止编辑后的只读链路审查。
- 下一步：从新 Debug 构建打开相似视频，播放任一候选返回，确认该行立即恢复播放/删除/定位按钮，
  不再等待资源释放尾部。

## 2026-08-09 · 全局 manual 标签候选与历史关系修复（完成）

- 补充修复：页面状态宿主曾保留一份旧候选规则，实际弹窗仍会忽略带历史 `parentId` 的 manual 定义；现已统一委托给同一候选函数，顶层弹窗显示全部非隐藏 manual 标签，二级 folder 标签仍只在所属父级展示。
- 来源边界：单视频编辑器已分离 folder 只读标签与 manual 可编辑集合；自定义标签不继承目录层级，和 folder 同名时也保存为独立 `source=manual` 关系，不创建或影响本地文件夹。
- 同名提示：当 folder 与 manual 同名时，编辑器明确提示两者为独立来源，并说明移除无锁 manual 不会影响目录标签。
- 候选排序：全部候选明确为未选中的 manual 自定义标签，并按真实关联次数把最常添加的标签排在前面。
- 根因：历史版本曾把 manual 标签保存到 folder 二级父级下，导致同名用户标签按父目录分裂；编辑器顶层候选只显示顶层定义，因此已有标签会像是“必须重新输入”，顶层筛选也会漏掉旧关系中的视频。旧的“添加到我的标签库”入口还只在同时新增收藏时刷新视图。
- 修复：媒体库加载时以单个 SQLite batch 幂等提升已加载视频的历史二级 manual 关系到同名顶层 `tagId`，保留旧标签定义、folder 标签、稳定 `videoId` 与用户数据；编辑器兼容展示未迁移的旧 manual 定义并显示标签中心已收藏的 manual 快捷候选；旧入口无论收藏是否变化都会更新标签定义视图。
- 数据核对：当前用户库发现 8 个 manual 定义，其中 3 个历史二级定义、5 条关系将于下一次新构建启动时自动提升；不删除视频、标签定义、收藏或播放记录。
- 验证：历史关系、同名 folder/manual 双来源保存、弹窗分离展示、保存回滚与架构契约 focused tests，以及 `flutter analyze`、`flutter build windows --debug` 均通过。未后台启动第二个应用进程修改正在使用的用户数据库；请从新 Debug 构建启动后验证候选与筛选。
- 下一步：人工打开任一视频的标签编辑器，确认 `Banana` / `婊子` 等已有 manual 标签可直接点击；在媒体库 manual 分组点击后确认旧二级关系视频一并命中。

## 2026-08-07 · seek→native-rendered-frame 单调时间线（实现完成）

- 目标：为同一媒体的 click → seek → 首帧解码建立项目内部可比的单调时间线，区分命令返回与原生渲染帧真正到达；不再扩大进度条命中区。
- 实现：`PlayerSeekCoordinator` 在实际派发前记录 `seek_submit_start`，命令返回记录 `seek_command_complete`，后台仅观察最新目标的帧号变化并记录 `native_rendered_frame` / `presented_frame_fallback` 与 `seek_to_frame_us`。
- 保护：后台观测不阻塞下一次 latest-only seek；schema、FilterQuery / TagQueryService、filtered queue、PlayerBackend 方法契约、缩略图队列和用户数据不变。
- 验证：seek coordinator 17 项、进度条 11 项、隐藏进度 3 项 focused tests，`flutter analyze` 与 `flutter build windows --debug` 均通过；Debug 可执行文件启动并保持响应后正常退出。
- 阻塞：当前线程没有可调用的桌面鼠标工具，未冒充完成同媒体真实点击录屏；人工路径是打开 `D:\video\崩铁\银狼\241229_90_SilverWolf-interview.mp4`，点击两个不同进度目标后从 stdout 搜索同一 `trace=` 的 `seek_submit_start → seek_command_complete → native_rendered_frame`，比较 `seek_to_frame_us`。
- 已知基线：`architecture_contract_test.dart` 的既有 `library_top_bar_search_surface.dart` 446 行 / 444 行门禁失败与本任务无关；其余相关架构用例通过。

## 2026-08-06 · 同媒体 click→seek→首帧 A/B 与隐藏态首击修复（完成）
- 媒体：项目播放器与 PotPlayer 均使用 `D:\video\崩铁\银狼\241229_90_SilverWolf-interview.mp4`，时长 3:21、H.264 2560x1440 60fps；项目来源队列保持 1/1。
- A/B：PotPlayer 49% 目标点击派发约 72ms，约 250–300ms 采样出现目标帧；项目隐藏态 20% 目标点击派发约 79ms，100ms 采样已到目标附近，300/800ms 仍保持目标播放。
- 根因：隐藏视觉线只有 3px，透明点击区虽扩大到 12px，但播放器页面外层与 Texture/HWND 的命中顺序仍可能让首击只唤醒控制条；HWND 还必须让出完整点击区。
- 修复：视觉线保持 3px；隐藏态在页面最外层挂载 12px 透明命中区，直接复用 latest-only seek 协调器；HWND 隐藏底部让出 12px；移除会造成重复 seek 的外层兜底路径。
- 保护：schema、FilterQuery、TagQueryService、来源 filtered queue、PlayerBackend 契约、缩略图队列和用户数据未改。
- 验证：同媒体 PotPlayer/项目真实窗口与 100/300/800ms 截图采样、隐藏进度 widget、seek coordinator focused tests、`flutter analyze`、`flutter build windows --debug` 均通过。

## 2026-08-06 · 进度条快速点击回写竞态（完成）
- 根因：相近目标的第一次位置回写仅凭 500ms 容差被误判为最新点击，导致滑块回弹。
- 修复：进度条等待 latest-only 提交完成，并比较最近旧目标与当前目标的距离；旧回写不再清掉最新乐观位置。
- 保护：PlayerBackend、filtered queue、播放暂停意图、标签筛选、缓存队列和用户数据未改。
- 验证：进度条快速点击回归、播放器 focused tests、`flutter analyze`、`flutter build windows --debug` 通过；真实窗口已启动并完成界面截图，Computer Use 鼠标输入未能稳定命中 Flutter 卡片。

## 2026-08-06 · 进度条连续点击响应（完成）

- 目标：鼠标连续快速点击进度条时只追踪最新目标，单次点击立即进入交互式 seek，不被旧 seek 的新帧等待或音量恢复阻塞；
- 实现：进度条回调复用页面级 latest-only `PlayerSeekCoordinator`，移除鼠标交互路径上的 `PlayerSeekAudioGate` 等待；精确恢复路径仍保留原音频门禁；
- 保护：PlayerBackend、来源 filtered queue、播放/暂停意图、标签筛选、缓存队列和用户数据不变；
- 验证：seek、进度条和播放器架构 focused tests、`flutter analyze`、Windows Debug build 通过；Debug 页面截图挂载正常，但实际点击因 Computer Use 再次返回 `node_repl exec context not found` 未完成。

## 2026-08-06 · 主动标签脱离文件夹层级（完成）

- 目标：主动添加的 manual 标签统一作为独立顶层关系，任意视频可单独添加，并可从 manual 分组筛选；
- 实现：编辑器不再继承当前 folder 子级上下文；批量入口统一顶层写入；历史二级 manual 关系在顶层保存时提升；
- 保护：folder 一级/二级派生关系、默认专辑、稳定 videoId、收藏、播放记录和筛选队列不变；
- 验证：focused 标签编辑、存储、筛选测试、架构契约测试、`flutter analyze` 和 Windows Debug build 均通过；Debug 媒体库截图挂载正常。标签入口实际点击因 Computer Use 返回 `node_repl exec context not found` 未完成，需人工打开详情并确认弹窗。

## 2026-08-06 · 播放器队列占位与鼠标 seek 响应（完成）

- 目标：修复播放器右侧队列偶发停留在灰色占位，以及鼠标点击进度条后滑块回弹、画面迟迟不更新的问题。
- 实现：队列项在滚动负载允许前延迟创建完整卡片，并用 `ScrollController` 变化补齐缺失的滚动结束通知；进度条提交后暂时保持鼠标目标，鼠标 seek 改走关键帧交互路径并等待新帧证据，继续观看恢复仍保留精确 seek。
- 保护：不修改 schema、FilterQuery / TagQueryService、来源 filtered queue、PlayerBackend 契约或用户数据。
- 验证：相关 widget/播放器聚焦测试、`flutter analyze`、Windows Debug 构建通过；Debug 窗口真实检查了队列缩略图、当前项高亮和点击后新画面。一次桌面自动化误触触发的回收站项已恢复原路径，并核实 SQLite 记录仍在。

## 2026-08-04 · mpv 推荐媒体控制（完成）

- 目标：在不扩展为专业播放器的边界内，补齐审计确认的音轨、字幕、章节和音频同步校正；不修改已有快捷键、schema、标签过滤、来源 filtered queue、缓存队列或用户数据。
- 实现：`PlayerMediaControlsBoundary` 是可选平台能力，MediaKit 后端复用同一条 libmpv 会话读取轨道/章节并执行控制；不支持的后端明确返回“不支持”。播放器控制栏已挂载“音轨、字幕与章节”面板。
- 快捷键：只新增未占用的 `#`、`v`、`z/Z`、`Ctrl++/Ctrl+-` 与 `g-a/g-s/g-c`；`J/L`、`PageUp/PageDown` 等既有绑定未改。
- 验证：`flutter analyze`、播放器/架构聚焦测试、媒体控制面板点击测试和 Windows Debug 构建通过；新 Debug 进程成功启动。完整 `flutter test` 唯一失败为未改动的 `library_top_bar_search_surface.dart` 446 行超过既有 444 行上限，已记录为独立基线问题；媒体控制入口另有页面挂载契约保护。

## 2026-08-04 — 键盘 seek 恢复连续播放（进行中）

- 真实同素材对照已复现：项目方向键短按后约 0.4 秒静止帧窗口；PotPlayer 的同一步骤持续有帧变化。MediaKit Texture 会退回 `estimated-frame-number`，不能再把它当作最终呈现证据。
- 已改为：键盘短按立即 `absolute+keyframes` 且保持原音量；长按保留 latest-only、GOP 自适应节流与临时静音，但 KeyUp 只收敛已提交的关键帧预览，不再追加 absolute 精确 seek。进度条松手仍走独立精确定位。
- 已通过完整 `flutter test`、`flutter analyze` 与 Windows Debug build；新 Debug 窗口同素材短按复录已无旧路径约 0.4 秒静止帧窗口，trace 不再出现 `exact_seek_start`。
- 不修改 schema、FilterQuery / TagQueryService、filtered queue、缓存队列、用户数据或 PlayerBackend 契约。

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-08-15 · 标签输入触发 Windows runner 原生闪退（进行中）

- 根因：Windows 事件日志记录 `flutter_windows.dll` 的 `0xc0000005`；runner 在
  `OnDestroy` 释放 `FlutterViewController` 后，仍会对延后抵达的 `WM_FONTCHANGE`
  无条件访问 engine。标签输入框会触发字体/输入法消息，因而更容易命中该生命周期竞态。
- 修复：`WM_FONTCHANGE` 处理前检查 controller 是否仍存活；不会改动 SQLite schema、
  TagQueryService / FilterQuery、来源 filtered queue、播放器后端或用户标签数据。
- 验证：Windows runner focused 源码守卫、`flutter analyze` 与 `flutter build windows --debug`
  均通过；使用隔离数据目录启动新 Debug 应用并保持 5 秒存活，未新增 Windows
  Application Error 1000。未为验证向真实用户库写入测试标签。
- 下一步：人工在真实媒体库打开任意视频的“添加标签”，输入/保存后关闭应用；确认事件查看器
  不再出现 `local_tag_player.exe` 的 `flutter_windows.dll` 访问冲突。

### 2026-08-15 · 内容级重复判断与候选缩略图（完成）

- 目标：在已有文件级重复候选之上识别重新编码/容器变化后的近重复，并让候选组可直接目视复核。
- 实现：保留 `mediaFingerprint` 作为快速预筛；每个视频按时长、画面比例和文件大小选取最相近
  邻居，再交错覆盖不同 duration 区间，避免全局前 48 对被同一密集时长区垄断。复用
  `ThumbnailService` 的缓存首帧做 dHash 预筛，通过后经 FFmpeg 取中段/后段 2 帧，计算有序
  3 帧 dHash 时序距离；无缓存条目只保留有限深度回退，算法签名仅驻留页面内存，不写 schema。
- 页面：确定重复与内容近重复分组分开标识；每行展示共享缩略图缓存、标题、路径、媒体摘要和定位按钮；
  视觉复核进行中/失败均可见；新增播放与删除操作，删除仍需统一确认。
- 播放：相似页通过显式 `similarity` 来源创建当前候选组的 filtered queue，只把该组传给播放器，
  不回退到全库；删除成功后重建候选快照并重新执行有界视觉复核。
- 保护：schema、FilterQuery / TagQueryService、既有来源 filtered queue、PlayerBackend、标签、收藏、
  播放记录和缩略图后台队列未改变；missing 记录继续保留，只有媒体详情与播放记录都没有有效时长时才跳过物理比较。
- 验证：相似服务回归测试覆盖密集时长区候选分摊、缺少媒体详情时的播放时长回退；真实库只读审计
  发现原 48 对只覆盖 14 个视频、漏掉约第 794022 个候选对。以真实缓存首帧复现该重复对后，新候选链
  成功进入多帧复核并成组；220 项 focused/widget tests、`flutter analyze`、`flutter build windows --debug`
  均通过。
- 下一步：重新打开 Debug 相似视频页，确认候选计数与该重复组可见，再完成 Windows Debug 构建和独立只读审查。

### 2026-08-15 · 相似视频候选入口（完成）

- 目标：在主界面左侧完整/折叠功能栏增加“相似视频”入口，用代码筛出重复下载候选，
  让用户逐组人工复核，不自动删除或移动文件。
- 实现：复用扫描链路已持久化的 `mediaFingerprint`（文件大小 + 首尾轻量采样）做内存分组；
  页面展示重复组、可复核多余项、待扫描和缺失记录统计，并可通过既有文件系统边界定位文件。
- 保护：schema、FilterQuery / TagQueryService、来源 filtered queue、缩略图/媒体详情队列、
  PlayerBackend 和用户数据均未改；missing 记录继续保留但不参与物理重复判断。
- 验证：新增分组 focused tests 与侧栏完整/折叠可达性测试、`flutter analyze`、
  `flutter build windows --debug`、真实 Debug 窗口入口挂载和独立只读 diff 审查均通过。
- 后续：若需要识别重新编码而非重复下载，再单独设计更严格的媒体详情相似度规则，
  不在本次轻量指纹候选中静默扩展。

### 2026-08-10 · v0.2.7 发布门禁：启动挂起与 HWND 命中区（完成）

- 首次挂载悬挂根因：`library_card_file_menu_test.dart` 在 Windows runner 上使用
  `Directory.systemTemp.createTemp`；目录已落盘但 Future 偶发不回调，测试停在
  `pumpWidget` 前并在 GitHub Actions 超时 10 分钟，并非生产页面的“新增提示 → 自动清理”
  异步顺序倒置。测试改为同文件既有的同步唯一路径创建法；关闭“稍后”对话框、释放模拟
  清理 Future，并推进清理回调排入的零延迟筛选 Timer，确保测试 teardown 无悬挂 Route/Timer。
- HWND 语义核对：隐藏态视觉线固定 3px，实际首击命中区固定 12px；child HWND 必须让出
  完整 12px，否则 `hit-test-transparent` 也无法保证 Flutter 收到首击。将过时的 3px
  unit/integration 断言改为 12px，不改变生产实现。
- 真实窗口：使用匿名 `fixed-low-bitrate-1080p.mp4` 启动 Debug child-HWND 集成窗口，报告确认
  `gpu-next-d3d11-child-hwnd`、`d3d11va`、zero texture copies、input forwarding
  `hit-test-transparent`、hidden `bottomAirspace=12`。在窗口底边的 12px 命中区进行物理首击后，
  播放位置跳转至点击横向目标且画面持续播放；视觉进度线仍为 3px。
- 验证：启动发现 focused widget、HWND surface focused unit、无人工等待的 child-HWND Windows
  integration test 均通过。schema、FilterQuery / TagQueryService、filtered queue、缩略图/媒体
  队列、PlayerBackend 契约和用户数据未改。
- 完整门禁：`flutter test`（521 passed / 3 skipped）、`flutter analyze`、Windows Debug 构建均通过。
- 下一步：提交、推送，再以 `publish_unsigned_release=true` 重新触发 v0.2.7 手动未签名 Windows /
  未公证 macOS 发布，并核验公开 Release 与资产。

### 2026-08-10 · 标签编辑器中文输入法候选确认（完成）

- 根因：单视频 manual 标签编辑器把 `TextField.onSubmitted` 直接用作“添加标签”；
  Windows 中文输入法按 `Enter` 确认候选词时会触发该回调，文本随即被归一化并清空，
  表现为中文偶发无法输入而英文正常。
- 修复：不再在原始键盘事件层拦截 `Enter`；改为监听 `TextRange.composing` 的结束时机，
  仅忽略紧随候选确认的一次 `onSubmitted`，下一帧自动失效。`Ctrl+Enter` 保存、Tab 候选
  浏览、Esc 取消和既有标签来源分离保持不变。
- 验证：新增 IME 组合态 widget 回归；组合态 Enter 保留文本，确认文本后 Enter 正常添加；
  既有键盘保存回归通过。`flutter analyze` 和 Windows Debug build 均通过；Debug 程序可启动，
  但当前本机媒体库启动加载未结束，且已有正式应用进程，未触碰用户数据以强行进入真实弹窗。
- 发布状态：此前的两个全量测试门禁已在本次独立定位后修复/确认；未创建 tag、Release 或安装包资产，
  待本次完整本地门禁通过后按既有手动未签名/未公证路径重新发布。

### 2026-08-09 · 启动新增视频发现延后（完成）

- 根因：默认开启的“自动清理无效记录”先遍历整个媒体库；未入库视频计数被串行安排在清理完成后。大型媒体库中提示长期不出现，表象为启动自动检索消失。
- 修复：首帧后优先执行未入库视频检查并保留“重新扫描 / 稍后”确认；确认流程结束后再执行原有后台无效记录清理，避免同盘两轮全库读取并发。
- 保护：不自动触发全量扫描；SQLite schema、stable identity、标签筛选语义、来源 filtered queue、缩略图/媒体解析队列和用户媒体数据不变。
- 验证：新增页面回归覆盖“清理挂起时仍立即展示新增视频提示”；`flutter analyze` 与 `flutter build windows --debug` 通过，Debug 可执行文件已启动并保持响应。聚焦 widget test 在本机 native-assets runner 的陈旧锁清理后仍停在用例初始化阶段、无错误输出，需该测试环境恢复后重跑。

### 2026-08-04 · seek 恢复时间线诊断（完成）

- 对真实 4K 媒体库样本的录屏曾复现连续预览后约 1.37 秒画面静止；新增 `PLAYER_SEEK_TRACE` 把 `KeyUp`、精确 seek 开始/返回、新视频帧证据、音频恢复请求/完成关联到同一 trace id。最终帧基线仅在精确命令返回后读取，Windows 优先以原生 Texture 已渲染计数而非 mpv 估算帧号判定，trace 记录证据来源。
- 每条事件记录 `mono_us` 作为唯一延迟依据，`wall_utc_ms` 仅用于和录屏启动侧车日志建立跨进程锚点；最终基线在 exact seek 返回后采样，Windows 优先观察 `native-rendered-frames`，并用 `frame_evidence` 区分原生 Texture 与估算回退；不改 `PlayerBackend`、音频策略、filtered queue 或用户数据。
- 验证：seek coordinator focused test 覆盖“exact 完成后才取基线”、六个节点顺序、同一 trace id 和 Texture 证据来源；`flutter analyze`、播放器/架构契约与 Windows Debug 构建通过。真实窗口可启动且 stdout 已接通，但捕获持续混入其他前台应用，已停止输入；待无覆盖的播放器窗口可用后，以 30fps 录屏和 trace 日志复核此前间歇性静止段。

### 2026-08-03 · 修复 seek 临时静音与新帧恢复（完成）

- 目标：长按快进/快退只临时静音，关键帧预览保持视频时钟连续；KeyUp 只精确 seek 一次，且必须等新视频帧交付证据后解除静音。
- 作用域：`PlayerKeyboardSeekController`、进度条提交和 `MediaKit Texture` 会话控制；不修改 `PlayerBackend` 接口、数据库、筛选语义、来源 filtered queue、缓存队列或用户媒体。
- 方案：以 `volume=0` 代替 `pause/play`；保持 latest-only 合并，按实际关键帧 seek 耗时自适应为 15/10/8fps 预览，并采用 750/1200/1800ms 新帧确认阈值。12-case 脚本会产出长 GOP p95 对应的建议档位，不伪造本机无 manifest 的结果。
- 验证：seek 会话顺序（含无新帧不解静音）、长 GOP 节流档位、页面与架构契约、完整 widget 测试、`flutter analyze` 与 Windows Debug build 均通过；真实 Debug 应用成功启动并显示媒体库。`.local/qa/player_seek-latency-matrix.json` 不存在，故 12-case Texture 门禁仍需在持有私有 manifest 的机器重跑。

### 2026-08-03 · 修复播放器单次 seek 与真实延迟门禁（完成）

- 目标：消除进度条释放和方向键短按各自可能产生的预览加精确 seek 双跳转，避免长 GOP
  媒体在一次交互中重复解码；保持长按关键帧预览和 KeyUp 精确收敛。
- 作用域：`PlayerProgressSlider`、`PlayerKeyboardSeekController` 与正式 MediaKit Texture
  seek 门禁；不修改 `PlayerBackend` 接口、数据库、筛选语义、来源 filtered queue、缓存队列或用户媒体。
- 验证：新增短按无预览且只精确收敛一次的单元契约；新增 1080p/4K、H.264/HEVC/AV1、
  短/长 GOP 的 ffprobe 规格核验与真实后端 p95 矩阵门禁。本机完整矩阵与 Windows 构建结果见本任务记录。

## 最近完成

1. 2026-08-03：seek 改为临时静音而非暂停视频时钟；方向键 KeyUp 等新视频帧后恢复音量，
   并保持 latest-only 合并和 GOP 成本自适应节流。
2. 2026-08-03：进度条松手改为单次精确 seek；方向键短按不再先做关键帧预览，
   长按仍在 `KeyRepeat` 后预览并在 KeyUp 精确收敛一次；建立真实 codec/GOP 延迟矩阵门禁。
3. 2026-08-01：完成 `0.2.5+7` 双平台打包、全量门禁与 `v0.2.5` 公开 GitHub Release；
   缺少签名 secrets 的风险已在发布说明和 macOS 文件名中明确标识。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.127`。
- 数据：schema、标签来源、查询语义、filtered queue 与用户维护数据保持稳定。
- 版本：`0.2.5+7`；依赖：`file_picker 11.0.2`、`package_info_plus 9.0.1`；后者 10.x
  受稳定版 `win32` 约束冲突阻塞。
- 最近业务验证：短按/长按 seek 会话、进度条 widget 与页面契约已通过；完整的 12-case
  编码/GOP 矩阵仍需在持有私有 manifest 的机器重跑，结果将决定最终门禁校准档位。

## 已确认阻塞

- GitHub Support purge 工单尚未确认服务端缓存清理完成；完成后需验证旧 Commit API 返回 404。
- 可信 Windows/macOS 正式签名仍需仓库所有者配置外部证书和 GitHub Actions secrets；
  任何证书、密码或私钥都不得写入仓库。

## 下一步

1. `file_picker 12` 发布稳定版或上游 `win32` 约束收敛后，单独复核
   `package_info_plus` 9 → 10；不得使用 beta 或 `dependency_overrides` 绕过。
2. 如继续精修播放器，使用实体键盘补一次完整的长按验收；应用切换后播放器需先点击
   才重新接收快捷键的问题应作为独立任务调查，不与 seek 语义混改。对真实用户视频建立新预算时，
   使用 `docs/qa/player_seek_latency_matrix.md` 的 12-case manifest，不将路径提交仓库。
3. 代理功能完成后，使用本机代理完成一次 GitHub 检查和安装包下载真实验收；
   仓库签名凭据与 GitHub Support purge 仍按既有独立任务跟进。
# 2026-08-16 · 架构演进 Phase 3–6（实现完成，独立验证待执行）

- 完成：`LibraryRepositoryContext` 统一单数据库、双索引、persistence helpers 和事务；查询/命令端口
  通过独立适配器注入，避免页面重新取得聚合 Store。
- 完成：`ResourceScheduler` 统一 scan/probe/thumbnail/visual/backup 预算，并由播放让渡门控制后台 lease；
  完成：`PlayerRuntimeBackend`/`PlayerSurfaceRenderer` 独立注入，保留 `PlayerBackend` 兼容实现。
- 完成：`LibraryQueryProfile`、trigram FTS5 可选派生索引和候选编译器；只作为候选缩小，最终仍经过
  `FilterQuery`/`TagQueryService`，小库、短词和不支持 FTS5 回退内存。
- 保护：schema v2、stable videoId、用户数据、来源 filtered queue、现有缩略图/媒体详情队列和正式
  MediaKit/Windows 后端行为不变；未增加路由框架，当前 Navigator/显式 Route 足够。
- 聚焦验证：Phase 3 context、Phase 4 scheduler、Phase 5 player contract、Phase 6 query compiler、
  stable identity 和播放器 service/filter tests 通过；架构门禁仅剩用户既有 `player_page.dart` 454 行超过旧阈值 444。
- 下一步：停止编辑后做独立只读 diff/status/analyze/build/runtime 审查；Windows build 仍需先释放 PID 21368。
