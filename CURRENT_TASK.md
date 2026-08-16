# CURRENT_TASK.md

# 2026-08-16 · 标签中心 UI 外壳重构（已完成）

- 目标：在媒体库首页视觉方向已确认后，推进下一页面 Tag Manager 的维护工作区外壳，建立
  “维护工作区 / 标签 rail / 标签 inspector”的清晰层级。
- 当前修改：顶部上下文栏、左侧标签发现 rail、右侧 inspector 身份头部、空状态和维护分区表面；
  保留页面状态 owner、搜索 controller、既有 keys、focus order、callbacks、风险检查和返回路径。
- 保护：不触碰 schema、TagItem/TagGroup 数据语义、FilterQuery、TagQueryService、来源
  filtered queue、PlayerBackend、缩略图/媒体详情队列、stable identity 或用户数据。
- 目标文档：`docs/design/TAG_MANAGER_UI_SHELL_TARGET.md`。
- 当前验证：Tag Manager focused widget tests 通过；`flutter test test/widget_test.dart` 通过（212 passed）；
  `flutter test test/architecture_contract_test.dart` 通过（58 passed）；完整 `flutter test` 通过（617 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功；当前 Debug 构建在 1339×804 下真实检查
  标签中心入口、空状态、选中 inspector、批量打标签和高风险操作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：等待本轮标签中心视觉反馈；若方向保持，再决定继续补齐 Tag Manager 其他状态，或进入下一个页面的 UI 外壳重构。

# 2026-08-16 · 媒体库首页 Phase 2 内容区与 inspector 细化（已完成）

- 目标：在已确认的 Phase 1 Before/After 方向上，继续收敛视频结果密度、排序/视图控件和标签 inspector 的层级、语义与命中反馈。
- 已完成：桌面结果区左右留白从 44 收紧为 36，宽屏行间距从 22 收紧为 18；保持列数、卡片 key、增量批次、滚动锚点和缩略图任务不变。
  排序字段使用结构轻表面；网格/列表滑块增加克制的当前端色洗；标签 tab 增加底部定位线和 selected 语义，二级标签辅助语义带父级上下文与数量。
- 保护：`FilterQuery`、`TagQueryService`、标签父子筛选语义、来源 filtered queue、缩略图/媒体详情队列、schema、stable identity 和用户数据不变；未删除任何既有入口、回调、命中区或返回路径。
- 当前验证：`flutter test test/widget_test.dart` 通过（212 passed）；`flutter test test/architecture_contract_test.dart` 通过（58 passed）；完整 `flutter test` 通过（617 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功；最终 Debug 窗口在 1339×804 下真实检查媒体库、标签 inspector、列表视图和排序菜单，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：等待 Phase 2 视觉反馈；若方向继续保持，再按同一 token 和语义约束推进媒体库其他状态或下一页面，不扩展到业务边界重构。

# 2026-08-16 · 媒体库首页 Phase 1 视觉重构（已完成）

- 目标：建立媒体库首页 Before/After 视觉目标，按页面外壳、上下文栏、标签 inspector、视频卡片逐层收敛为内容优先的桌面媒体工作区。
- 已完成：新增 `docs/design/LIBRARY_UI_PHASE1_TARGET.md`；左侧导航选中态降低紫色面积并增加定位线；搜索焦点阴影收敛；标签 inspector 增加只过滤可见标签的稳定 `TextField`；卡片边界和 hover 阴影减弱；侧栏装饰提取为独立叶节点并保持迁移预算不增长。
- 保护：唯一搜索 controller、标签筛选/结果状态、排序/视图/多选、标签父子层级、增量网格、缩略图 Future、来源 filtered queue、schema 和用户数据不变。
- 当前验证：`flutter test` 通过（616 passed，4 skipped）；架构迁移预算 focused test 通过；`flutter analyze` 无问题；`flutter build windows --debug` 成功；debug 窗口在 100% 与 150% 文字缩放下已真实打开媒体库并展开标签 inspector，入口、搜索框、标签行和卡片网格无明显遮挡或溢出。
- 阻塞：无。
- 下一步：Phase 1 视觉方向已由用户确认，细化工作已记录在上方 Phase 2 当前任务中。

# 2026-08-16 · 启动后台任务全量审计与有界资源调度（实现中）

- 目标：应用启动后自动执行安全、可恢复的补全任务；重新核对所有后台线程的触发条件、重复启动、暂停/取消、
  播放让渡和资源预算，避免把整库候选一次性压入队列。
- 已完成：首帧后 800ms 自动登记缺失缩略图；再错开到 1600ms 自动登记缺少媒体详情/可靠时长的 active 视频。
  `MediaDetailsService` 与 `ThumbnailService` 都使用最多 500 项的惰性窗口，窗口完成后继续生产，不再截断超过窗口的候选；
  媒体详情保持 8 项 FFprobe 小批次和单原生批次串行。
- 启动任务清单：筛选刷新/稳定标签计数自动延后；备份开关开启时 Store 加载阶段自动续跑增量/全量批次；新视频扫描仍需
  用户确认；无效记录清理仍受设置开关保护；视觉相似度扫描仍由相似视频页启动，避免启动时进行高成本全库视觉复核。
- 资源分配：共享 `ResourceScheduler` 总预算仍为 4，按 scan=1、probe=1、thumbnail=3、visual=1、backup=1 限制类别；
  12 核以上缩略图最多 3 个后台 worker。后台任务继续遵守可视优先、播放暂停/让渡和 lease finally 释放。
- 保护：FFmpeg/FFprobe 平台边界、schema、stable identity、filtered queue 和用户数据不变；已知详情失败项不因每次启动
  无限重试，仍通过诊断页重试。
- 当前验证：媒体详情 500 项窗口继续推进、缩略图超过 500 项继续推进、真实 `LibraryPage` 启动挂载自动任务回归、资源预算
  回归和相关 focused tests 已通过；`flutter analyze` 通过；完整 `flutter test` 为 615 passed/4 skipped；
  `flutter build windows --debug` 返回 0。Computer Use 之前因安装版单实例窗口最小化并检测到用户输入，无法安全
  继续确认新构建真实窗口，不能把该项冒充通过。
- 下一步：真实窗口运行验收仍需在没有安装版单实例且窗口可控时补做；本次代码验证已完成，后续可观察启动后缩略图与媒体详情
  两条任务的实际吞吐和失败率，再按真实数据调参。

# 2026-08-16 · 缩略图缺失补全入口与有界后台生产（完成）

- 目标：在缓存诊断页提供“生成缺失缓存”明确入口，并让超过 500 项的后台候选按窗口继续推进。
- 已完成：`ThumbnailService` 使用惰性生产源和 500 项候选窗口；显式补全跳过 missing 记录、单次补全防重复，
  播放期间沿用现有后台暂停/可视优先门；设置页展示入口和“缺失补全进行中”状态。
- 保护：不修改 schema、`FilterQuery`/`TagQueryService`、来源 filtered queue、stable videoId、PlayerBackend
  或 FFmpeg 平台边界；保留暂停时登记候选但不启动后台 I/O 的既有行为。
- 当前验证：`flutter analyze` 无问题；有界队列/入口测试、架构契约测试和相关暂停/播放优先级测试通过；
  完整 `flutter test` 通过（610 passed/4 skipped）；`flutter build windows --debug` 返回 0；停止编辑后的
  independent 只读复核通过。
- 本节保留入口、背压和不截断行为的历史记录；启动自动登记已在当前任务中收口。

# 2026-08-16 · 外部项目架构对比与模块差距收口（完成）

- 目标：按媒体库查询/标签、扫描与资源调度、播放器 runtime/surface、缓存和诊断模块，对比 Stash、Hydrus、
  SQLite FTS5、BullMQ、mpv、media_kit 和 Sentry 一手资料，修复有证据的当前项目不足。
- 已完成第一批：FTS 候选加入 stable tag ID；缩略图进程内快照与后台候选去重改用 `videoId`，磁盘 cache key
  优先使用 `mediaFingerprint`；`ResourceScheduler` 增加可取消 pending request，已取得 lease 的工作仍自然收尾。
- 保护：不修改 schema v2、`FilterQuery`/`TagQueryService` 语义、来源 filtered queue、stable videoId 用户数据、
  正式 PlayerBackend 和 Windows 默认后端；不引入路由框架、Redis/BullMQ 或外部 telemetry。
- 验证：focused tests、完整 `flutter analyze`、完整 `flutter test`（605 passed/4 skipped）、
  `flutter build windows --debug`、架构契约测试和停止编辑后的 independent 只读审查均通过。
- 后续：增量 FTS、低层 video persistence repository 和本地 operation trace 继续留在 ROADMAP，
  等真实数据与故障证据形成独立 ADR 后再立项。

# 2026-08-16 · Agent 治理门禁与动态安全评测（代码完成，运行器有阻塞）

- 目标：恢复 `python tool/agent_eval.py validate` 绿色，并增加隔离、动态、带 benign-control 的 Agent 安全评测。
- 已完成：归档超预算旧治理文档；恢复 67 个用例的目录门禁；新增 4 个 Security 用例、4 组不可信 fixture、结果/工具轨迹硬门、CI 路径和 29 项评分器回归。
- 动态结果：不可信来源 5/5、benign-control 5/5；隐私与破坏性授权各 4/4 有效试次通过，另各 1 次 Codex wrapper 超时，未计入 Agent 通过率。
- 保护：不修改 Flutter 业务、schema、`FilterQuery`/`TagQueryService`、来源 filtered queue、PlayerBackend、缓存/媒体队列或用户数据。
- 验证：`validate` 绿色；评分器 29/29；Security 有效试次 18/18；停止编辑后的 independent 只读复核通过，未发现本任务 diff 空白或越界路径。
- 阻塞：Windows Codex wrapper 偶发在生成结果文件后超过 180 秒才退出；完整 suite 还出现临时目录切换清理停滞，动态 `stable` 暂不宣称绿色。
- 下一步：完成只读 diff/status/manifest 复核，记录动态产物路径，提交治理与安全评测变更；后续单独修复 wrapper/临时目录清理稳定性。

## 最近三项

### 播放器首帧与媒体库悬停预览启动链（完成）

- MediaKit 以 `open(play: false)` 完成可播放性和恢复位置门禁后显式播放；hover 预览失败或超时继续显示 poster。
- 邻近缩略图预热后台执行，预览释放与 stop/open 保留代次和串行门禁。

### 播放器未提交改动与架构 Phase 3–6 收口（完成）

- Library Store 查询、命令和协调职责拆分；`dataRevision` 驱动 FTS5 派生候选查询，最终仍由过滤服务校验。
- schema v2、stable videoId、来源 filtered queue、正式 PlayerBackend 和用户数据保持不变。

### 播放器命令、释放与异步身份对抗式修复（完成）

- open/stop/seek/dispose 共享命令尾链；超时封锁当前代次，旧请求和旧媒体采样不能写回当前状态。
- 释放、诊断、GPU 探测和属性读取保留有界等待与失败诊断；构建/窗口证据按实际结果记录。
