# CHANGELOG.md

本文件只保存未发布变更和版本索引。完整历史位于
`docs/history/changelog/`，不要把旧条目复制回根文件。

## Unreleased

### 关于 / 更新 UI 外壳重构

- 新增关于页 Before/After 视觉目标；页面从通用 `Card` 收敛为带稳定 Semantics 和挂载 key 的
  “版本与更新工作区”，保留 logo、版本信息、更新渠道、主动检查和 updateStatus 文案。
- 更新状态改为低干扰就地状态表面；不改变版本读取、Release 查询、下载/校验/安装器、更新 Dialog 或失败恢复语义。
- 不新增自动检查或网络副作用，不修改代理、媒体播放、媒体库、筛选、播放/缓存队列、stable identity 或用户数据。

### 更新网络代理 UI 外壳重构

- 新增网络代理页 Before/After 视觉目标；页面从通用 `Card` 收敛为带稳定 Semantics 和挂载 key 的
  “更新网络连接工作区”，保留范围说明、开关、地址输入、保存与 status 文案。
- 状态反馈改为低干扰就地状态表面；不改变 HTTP-only、无凭据、地址规范化、更新检查/安装包下载或禁用态语义。
- 不修改系统代理、媒体播放、媒体库扫描、筛选、播放/缓存队列、stable identity 或用户数据。

### 文件删除设置 UI 外壳重构

- 文件删除设置从通用 `Card` 收敛为带稳定 Semantics 和挂载 key 的文件删除安全工作区；保留确认开关、
  自动清理开关、回收站规则、危险提示和原有设置 key。
- 删除设置保存失败、自动清理完成/失败反馈接入共享维护 Snackbar；不改变回收站、数据库清理、扫描、
  stable identity 或用户数据语义。

### 数据备份 UI 外壳重构

- 数据备份从通用 `Card` 收敛为带稳定 Semantics 和挂载 key 的实色数据保护工作区；保留保护范围、
  同步状态、进度、立即备份、完整性检查、导出和原有设置 key。
- 不改变 `DataBackupSettingsWorkspace`、备份 controller、备份数据库、文件选择器、持久化、用户数据
  或任何备份命令语义。

### 缓存诊断 UI 外壳重构

- 缓存诊断从通用 `Card` 收敛为带稳定 Semantics 和挂载 key 的实色诊断工作区；保留 loading、
  error、覆盖率、指标、后台任务、失败详情与恢复动作顺序。
- 缓存重试、清除失败标记和缺失补全反馈改用维护工作区共享 Snackbar；不改变缓存统计、失败/缺失
  语义、ThumbnailService、缓存队列或用户数据。

### 相似视频页 UI 外壳重构

- 新增相似视频页 Before/After 视觉目标；页面统一进入“维护工作区 / 相似视频”标题层级，
  重新计算动作保留原 key、tooltip、扫描中禁用和结果语义。
- 结果区增加 1120px 桌面宽度上限，保留候选列表右侧 scrollbar 安全区；页面接入维护反馈主题。
- 不修改相似扫描 controller、缩略图/媒体详情队列、来源 playlist、stable identity、删除合并或用户数据。

### 维护反馈组件族统一

- 新增维护工作区共享 Dialog、Menu、Sheet、Tooltip、Snackbar 入口，统一深色实色浮层、弱描边、圆角、
  安全区和 tooltip 语义；不引入全窗口 blur 或持续动画。
- 迁移标签中心、备份设置、Missing/Relink、目录管理和媒体库确认/恢复反馈；保留原有返回值、确认、
  危险动作、撤销/恢复文案和页面业务 owner。
- 不修改 schema、`FilterQuery`、`TagQueryService`、filtered queue、`PlayerBackend`、缓存/媒体详情队列、
  stable identity 或用户数据。

### 目录管理 UI 外壳重构

- 目录管理统一为“维护工作区 / 目录管理”标题层级；添加目录与重新扫描在 expanded 下保留文字动作，
  compact 下收敛为带 tooltip 的图标动作。
- 内容区增加稳定桌面宽度边界，继续保留目录数量、扫描状态、root 列表、空态、解除管理确认和数据保留说明。
- 不修改 root/扫描/解除管理业务、`LibraryApplicationFacade`、schema、`FilterQuery`、`TagQueryService`、
  filtered queue、PlayerBackend 或用户数据。

### Missing / Relink UI 外壳重构

- 建立“维护工作区 / 缺失与重新关联”两级上下文标题栏，保留返回与批量路径替换入口；窄窗口下
  批量动作降级为带 tooltip 的图标按钮。
- 内容区增加稳定桌面宽度边界，继续保留缺失摘要、稳定身份保留说明、空态、单条重新关联和批量预览。
- 不修改 `videoId`、fingerprint、mutable path、missing/relink 业务、schema、`FilterQuery`、
  `TagQueryService`、filtered queue、PlayerBackend 或用户数据。

### 设置工作区 UI 外壳重构

- 建立设置首页的 Before/After 视觉目标，顶部改为“维护工作区 / 设置”两级上下文栏，二级页
  改为“设置 / 当前分区”层级；保留返回、刷新统计及既有 key/回调。
- 首页增加轻量设置工作区上下文头部，入口分组改为结构 surface + 交互 surface，继续保留播放、
  数据维护和应用三组入口的顺序、状态摘要与键盘/鼠标可达性。
- 不修改设置持久化、缓存诊断、备份、删除确认、快捷键录制、schema、筛选语义、filtered queue、
  PlayerBackend、缩略图/媒体详情队列、stable identity 或用户数据。

### 标签中心 UI 外壳重构

- 建立 Tag Manager 的 Before/After 视觉目标，顶部改为“维护工作区 / 标签中心”两级上下文栏，
  左侧强化标签发现 rail，右侧增加标签 inspector 身份头部。
- 空状态、选中行、属性/批量/高风险操作分区统一维护页深色 surface 层级；保留搜索、分组筛选、
  创建、编辑、批量 manual 打标、引用检查、焦点顺序和返回路径。
- 不修改标签数据模型、来源语义、schema、`FilterQuery`、`TagQueryService`、filtered queue、
  PlayerBackend、缩略图/媒体详情队列、stable identity 或用户数据。

### 媒体库首页 Phase 1 视觉重构

- 建立媒体库首页 Before/After 视觉目标，明确页面上下文、搜索、活动筛选、标签发现和视频结果的层级关系。
- 左侧导航选中态改为轻量底色加定位线；搜索焦点和视频卡片 hover 的阴影收敛，减少结构表面对内容的干扰。
- 标签发现面板新增只过滤可见标签的稳定搜索入口；不创建新的筛选条件，不触发媒体库查询，也不改变标签父子语义。
- `FilterQuery`、`TagQueryService`、filtered queue、缩略图/媒体详情队列、PlayerBackend、schema 和用户数据保持不变。

### 媒体库首页 Phase 2 内容区与 inspector 细化

- 收紧桌面结果区外侧留白和宽屏行间距，把首屏空间优先还给缩略图与文件名；保留既有列数、增量加载、滚动和缩略图任务边界。
- 排序字段改用结构轻表面，网格/列表滑块用低对比度当前端色洗表达状态；排序、方向、视图 owner、偏好保存和命中区不变。
- 标签 inspector 的 tab 增加选中定位线与辅助 selected 语义；二级标签语义补充父级上下文和数量，继续保留排除态与真实筛选链路。
- 不修改 `FilterQuery`、`TagQueryService`、filtered queue、缩略图/媒体详情队列、PlayerBackend、schema、stable identity 或用户数据。

### 缩略图缓存缺失补全

- 缓存诊断页新增“生成缺失缓存”明确入口；媒体库首帧后延迟登记一次自动补全，用户也可以按需手动开始。
- 缩略图后台候选改为惰性分批生产并持续推进，保留 500 项窗口、24 个后台校验请求和既有 FFmpeg/资源调度限制，
  超过窗口的候选不再被截断；启动时已有扫描预取会顺序让位，播放期间仍暂停后台补全并保留可视缩略图优先。
- 多核机器的缩略图后台生成并发从最多 2 个提高到最多 3 个；共享资源总预算仍为 4，前台缩略图和播放门禁不变。
- 媒体详情/时长补全也改为最多 500 项惰性窗口和 8 项 FFprobe 小批次；应用首帧后错峰自动补齐安全的 active 项目，
  已知失败项不在启动时循环重试，继续由诊断页显式重试。
- 重新核对启动后台任务：备份续跑、稳定计数和缓存/媒体详情补全自动执行；新视频扫描、无效记录清理和视觉相似度扫描仍保留
  用户确认或设置门禁，所有任务继续共享总资源预算和播放让渡边界。

### Agent 治理门禁与动态安全评测

- 压缩根级治理状态、架构契约和变更索引；旧内容保留在 dated history，恢复默认上下文预算门禁。
- 增加隔离动态安全用例、untrusted fixture、benign-control、结果泄露检查和工具动作检查。
- Agent governance workflow 覆盖架构契约与 Agent eval 文档变更，避免治理规则变更绕过门禁。

### 播放器首帧与媒体库悬停预览

- MediaKit 以 `open(play: false)` 完成引擎、媒体可播放性和恢复位置门禁后显式播放；失败/超时继续显示 poster。
- 共享 hover 预览、邻近缩略图预热和 stop/open 释放使用后台任务、串行链和代次保护。

### 架构分层与资源预算

- Library Store 查询、命令和协调职责拆分；FTS5 候选路径最终仍由 `FilterQuery`/`TagQueryService` 校验。
- FTS 候选文本补齐 stable tag ID；缩略图内存快照与后台候选去重改用 stable videoId，磁盘 cache key
  在 videoId 范围内优先复用 mediaFingerprint；ResourceScheduler 增加 pending request cancellation，
  不中断已开始的 I/O。
- schema v2、stable videoId、来源 filtered queue、正式 PlayerBackend、缩略图/媒体队列和用户数据保持不变。

### 播放器命令与异步身份

- open/stop/seek/dispose 共享媒体命令尾链；超时封锁当前代次，旧事件不能写回新媒体。
- 释放、诊断、GPU 探测和属性读取保留有界等待、失败阶段和可复核日志。

### 相似视频与删除安全

- 视觉复核使用可取消、有界、可让渡的后台队列；视觉签名为带 fingerprint 快照的可重建缓存。
- 用户视频删除统一先进入系统回收站，再删除 Repository 记录和可重建缓存；manual 标签和收藏按 stable videoId 保留。

## 已发布版本

- `0.2.8+10`：当前版本索引，详细发布说明见 `docs/RELEASE_NOTES_0.2.8.md`。
- 历史版本和逐项变更见 `docs/history/changelog/`。
