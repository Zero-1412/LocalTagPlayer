# CURRENT_TASK.md

# 2026-08-17 · 播放器信息与诊断 UI 外壳重构（已完成）

- 目标：继续播放器 Phase 2，在媒体控制之后收口视频信息与播放诊断弹窗，先建立
  `docs/design/PLAYER_INFO_DIAGNOSTICS_UI_SHELL_TARGET.md` 的 Before/After 目标，再统一弹窗局部主题、
  分组表面、容器语义和稳定 key。
- 当前修改：新增播放器内容弹窗局部主题 helper；视频信息与诊断弹窗显式复用 `playerWorkspaceTheme`，
  `PlayerDialogSectionCard` 改为实色 `Material`、弱描边、统一圆角与裁切，并补齐信息/诊断分组的稳定 key。
- 保护：不修改视频信息字段来源、媒体详情读取、诊断采样/timer/播放流订阅/复制摘要、关闭与滚动路径；不修改
  `PlayerService`、`PlayerBackend`、`PlaybackSession`、来源 `filtered playback queue`、`FilterQuery`、
  `TagQueryService`、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据。
- 当前验证：`test/player_diagnostics_dialog_test.dart` focused 通过，已验证诊断分组挂载、容器语义、采样流和卸载后停止响应；
  完整 `flutter test` 通过（629 passed，4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。
  Debug 窗口真实从媒体库进入播放器，打开上下文菜单中的视频信息与诊断检查，检查信息分组、诊断实时/分析/详细指标表面、
  详细指标滚动、复制/关闭入口和 Esc 返回；正文对比度修正后可读，无明显遮挡或溢出，未触发收藏、标签、设置或文件写入。
- 阻塞：无。
- 下一步：收集本轮播放器信息/诊断弹窗在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化播放器其它残余内容表面，或转入下一个页面外壳重构；继续保护来源队列、播放器会话和用户数据边界。

# 2026-08-17 · 播放器媒体控制 UI 外壳重构（已完成）

- 目标：进入播放器页面下一处 UI 外壳重构，把媒体控制弹窗的音轨、字幕、音画同步、章节四个默认 `Card`
  分组收敛为播放器嵌套工作区表面，先建立 `docs/design/PLAYER_MEDIA_CONTROLS_UI_SHELL_TARGET.md` 的
  Before/After 目标，再补真实挂载证据。
- 当前修改：`PlayerMediaControlSection` 使用播放器实色弱描边 `Material`、圆角和裁切；媒体控制弹窗显式
  使用 `playerWorkspaceTheme`，四个分组和弹窗增加稳定 key/容器语义。
- 保护：不修改 `readMediaControls`、选轨/章节/延迟回调、`PlayerService`、`PlayerBackend`、来源
  `filtered playback queue`、播放会话、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据。
- 当前验证：媒体控制交互、播放器架构挂载、主题 token、high contrast/150% 文字与滚动可达性 focused 测试通过；
  完整 `flutter test` 通过（629 passed，4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug`
  成功。Debug 窗口真实从媒体库进入播放器，打开并滚动媒体控制弹窗检查音轨、字幕、音画同步、章节四组表面、
  空态、关闭与返回；未触发选轨、延迟、章节跳转或其它写入动作。
- 阻塞：无。
- 下一步：收集媒体控制在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，再决定继续细化
  播放器其它残余内容表面，或转入下一个页面的 UI 外壳重构；继续保护来源队列、播放器会话和用户数据边界。

# 2026-08-17 · 标签中心 UI 外壳重构（已完成）

- 目标：进入第三阶段维护页面，把 Tag Manager 从匿名双栏表面收敛为“标签中心工作区”以及左侧“标签导航
  工作区”、右侧“标签 inspector 工作区”，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/TAG_MANAGER_UI_SHELL_TARGET.md`；页面与两个结构表面增加稳定 Semantics/key，
  实色 `Material` 统一圆角、弱描边和裁切；空详情与选中标签详情共用 inspector 边界。
- 保护：不修改 `_filteredTagRows` 展示筛选、搜索 `TextField` 链路、分组选择、详情焦点顺序、别名/隐藏/收藏/
  排序保存、批量 manual 增删、folder 来源门禁、合并/删除影响检查、`LibraryApplicationFacade`、schema、
  filtered playback queue、ThumbnailService、stable identity 或用户数据语义。
- 当前验证：Tag Manager 搜索、分组、页面挂载、150% 文字缩放、详情焦点/下拉锚点和高风险只读反馈 focused
  测试已通过；完整 `flutter test` 通过（628 passed，4 skipped）；架构迁移预算、`flutter analyze` 和
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入标签中心，检查空 inspector、真实 folder
  标签 inspector、属性/批量/高风险区域、滚动和返回媒体库；未触发任何写入动作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：收集标签中心在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，再审查
  共享 Dialog/Menu/Sheet/Tooltip/Snackbar 和播放器残余内容表面；继续保护标签维护、播放队列与用户数据边界。

# 2026-08-17 · 播放器交互 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把播放器交互从通用卡片收敛为“全屏播放列表工作区”和
  “播放器快捷键工作区”，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/PLAYER_INTERACTION_UI_SHELL_TARGET.md`；两个 panel 使用稳定 Semantics/key
  和实色弱描边边界；保留全屏边缘开关、快捷键录制、冲突提示、恢复默认和 Esc 安全出口。
- 保护：不修改 `CacheSettingsPage` 的状态 owner、`PlaybackSettings`、PlayerBackend、PlaybackSession、
  filtered playback queue、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据语义。
- 当前验证：交互意图 focused 测试、150% 文字缩放 focused 测试、设置首页页面级可达性测试和架构迁移预算
  测试已通过；完整 `flutter test` 通过（626 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入播放器交互，检查两个工作区、
  快捷键网格、底部 Esc 安全出口说明、滚动条和返回设置首页；未触发设置动作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：收集播放器交互页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化维护页外壳，或转入播放器页面外壳；不扩展到快捷键语义、播放后端或队列业务边界。

# 2026-08-17 · 视频画质与增强 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把视频画质与增强从通用卡片收敛为“视频画质与增强工作区”，
  先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/PLAYBACK_QUALITY_UI_SHELL_TARGET.md`；设置 panel 使用稳定
  `settings.playbackQuality.workspaceSurface` key 和 Semantics container 的实色弱描边边界；保留比例、
  缩放、色彩、流畅度、增强、HDR 确认和能力状态行。
- 保护：不修改 `PlaybackSettings`、`PlaybackSettingsController`、PlayerBackend 实际应用、HDR/流畅度确认与
  撤销、FFprobe/诊断边界、PlaybackSession、filtered playback queue、ThumbnailService、媒体详情/缓存队列、
  schema、stable identity 或用户数据语义。
- 当前验证：150% 文字缩放 focused 测试、设置首页进入画质页后检查工作区/HDR 开关/返回的页面级测试、HDR
  确认 focused 测试、流畅度确认/撤销测试和架构迁移预算测试已通过；完整 `flutter test` 通过（625 passed，
  4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库
  进入设置，再进入视频画质与增强，检查比例、缩放、色彩、流畅度、压缩增强、两个增强开关和两个能力状态行；
  长内容滚动后工作区底部完整、返回设置首页可达，无明显遮挡、裁切或溢出；未触发任何设置动作。
- 阻塞：无。
- 下一步：收集视频画质与增强页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入播放器交互设置或下一个页面的 UI 外壳重构；不扩展到播放后端、确认语义或队列业务边界。

# 2026-08-17 · 播放与解码 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把播放与解码设置从通用卡片收敛为
  “播放与解码工作区”及“播放会话缓存工作区”，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/PLAYBACK_SETTINGS_UI_SHELL_TARGET.md`；两个设置 surface 使用稳定
  Semantics/key 和实色弱描边边界；保留恢复策略、后端说明、解码器选择、流缓存开关及原有 key/回调。
- 保护：不修改 `PlaybackSettingsController`、`CacheSettingsPage`、MediaKit Texture 统一后端、
  decoder confirmation、demux window、PlayerBackend、PlaybackSession、filtered playback queue、
  ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据语义。
- 当前验证：播放工作区唯一后端 focused 测试、150% 文字缩放 focused 测试、设置首页进入播放页后
  检查恢复策略/缓存工作区/返回路径的页面级测试和架构预算测试已通过；完整 `flutter test` 通过
 （624 passed，4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口
  真实从媒体库进入设置，再进入播放与解码，检查恢复策略、MediaKit Texture、解码策略和播放会话缓存
  两个工作区，无明显遮挡、裁切或溢出；未切换任何设置。
- 阻塞：无。
- 下一步：收集播放与解码页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定细化播放器交互/画质设置页，或进入下一个页面的 UI 外壳重构；不扩展到播放器队列、解码器
  后端或缓存业务边界。

# 2026-08-17 · 关于 / 更新 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把关于页从通用卡片收敛为
  “版本与更新工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/ABOUT_UPDATE_UI_SHELL_TARGET.md`；关于页使用带稳定
  `settings.about.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留 logo、版本 Future、更新渠道、主动检查、更新 Dialog 入口和 updateStatus 文案，状态反馈收敛为就地状态表面。
- 保护：不修改 `AppUpdateService`、版本比较、Release 查询、下载/校验/安装器、代理、媒体播放、媒体库、
  筛选、播放/缓存队列、stable identity 或用户数据语义。
- 当前验证：关于页版本/最新状态、失败恢复、150% 文字缩放 focused 验证通过；设置首页滚动后进入关于、
  检查工作区/logo/主动更新并返回的页面级可达性验证通过；完整 `flutter test` 通过（623 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入关于，
  检查当前版本、产品说明、更新渠道和检查更新入口，无明显遮挡、裁切或溢出；未触发更新检查或下载。
- 阻塞：无。
- 下一步：收集关于页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入下一个维护页面；不扩展到更新服务边界。

# 2026-08-17 · 更新网络代理 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把应用更新代理从通用卡片收敛为
  “更新网络连接工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/UPDATE_PROXY_UI_SHELL_TARGET.md`；网络代理使用带稳定
  `settings.updateProxy.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留范围说明、代理开关、地址输入、保存按钮、status 文案和历史 key，状态反馈收敛为就地状态表面。
- 保护：不修改 `AppUpdateProxySettingsService`、地址规范化、HTTP-only/无凭据约束、更新检查/安装包下载、
  系统代理、媒体播放、媒体库扫描、筛选、播放队列、缓存队列、stable identity 或用户数据语义。
- 当前验证：代理页保存、凭据拒绝、150% 文字缩放 focused 验证通过；设置首页滚动后进入网络代理、检查
  工作区/开关/地址/保存并返回的页面级可达性验证通过；完整 `flutter test` 通过（622 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入
  网络代理，检查当前持久化代理状态、范围说明、输入框和保存按钮，无明显遮挡、裁切或溢出；未修改代理设置。
- 阻塞：无。
- 下一步：收集网络代理页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入关于/更新页；不扩展到更新网络业务边界。

# 2026-08-16 · 文件删除设置 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个高风险维护叶页面，把文件删除设置从通用设置卡片收敛为
  “文件删除安全工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/DELETE_FILE_UI_SHELL_TARGET.md`；文件删除设置使用带稳定
  `settings.fileDeletion.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留历史 card key、两个开关、删除规则和危险提示；本页相关 Snackbar 接入共享维护反馈。
- 保护：不修改 `CacheSettingsPage` 的删除 owner、设置持久化、FileSystemAdapter、回收站、自动清理、
  stable identity、标签关系、扫描或用户数据语义。
- 当前验证：文件删除工作区、设置入口可达性、150% 文字缩放、关闭确认后的危险提示、
  共享维护反馈和架构契约 focused 验证通过；完整 `flutter test` 通过（621 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，
  再进入删除文件，检查两个开关、回收站规则和危险提示，无明显遮挡、裁切或溢出，且未触发删除或清理动作。
- 阻塞：无。
- 下一步：收集文件删除页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化其他维护状态或进入下一个页面；不扩展到删除业务或文件系统边界。

# 2026-08-16 · 数据备份 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个仍缺独立视觉目标的数据保护叶页面，把数据备份从通用设置卡片收敛为
  “数据保护工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/DATA_BACKUP_UI_SHELL_TARGET.md`；数据备份使用带稳定
  `settings.dataBackup.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留保护范围、同步状态、进度、维护动作和原有 `settings.dataBackup.card` key。
- 保护：不修改 `DataBackupSettingsWorkspace`、`DataBackupMaintenanceController`、备份数据库、
  文件选择器、持久化、备份状态语义或用户数据。
- 当前验证：数据备份工作区、设置入口可达性、150% 文字缩放、维护操作键盘顺序和架构契约
  focused 验证通过；完整 `flutter test` 通过（621 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入视频数据备份，检查
  保护范围、11,194 / 11,194 同步状态、维护按钮和完整性检查 Dialog，关闭后页面恢复，无明显遮挡、
  裁切或溢出。
- 阻塞：无。
- 下一步：先收集数据备份页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入下一个维护状态或继续细化备份错误/导出反馈；不扩展到备份服务或数据库边界。

# 2026-08-16 · 缓存诊断 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个仍缺独立视觉目标的维护叶页面，把缓存诊断从通用设置卡片收敛为
  “诊断工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/CACHE_DIAGNOSTICS_UI_SHELL_TARGET.md`；缓存诊断使用带稳定 key
  和 Semantics container 的实色工作区 surface；缓存重试、清除和缺失补全反馈接入共享维护 Snackbar。
- 保护：不修改 `CacheDiagnosticsController`、`CacheDiagnosticsMaintenanceController`、
  `ThumbnailService`、缓存队列、失败/缺失统计语义、失败详情或用户数据。
- 当前验证：缓存诊断工作区、读取失败、150% 文字缩放、设置入口可达性和架构契约 focused
  验证通过；完整 `flutter test` 通过（621 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入缩略图缓存，检查
  覆盖率、指标、后台任务、失败语义、失败详情展开和三项恢复操作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：先收集缓存诊断在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化其他缓存状态或进入下一个维护页面；不扩展到缓存业务边界。

# 2026-08-16 · 相似视频页 UI 外壳重构（已完成）

- 目标：进入下一个仍缺统一维护视觉证据的页面，把相似视频收敛为“维护工作区 / 相似视频”
  的内容优先页面，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/VIDEO_SIMILARITY_UI_SHELL_TARGET.md`；页面接入共享维护标题栏、
  `maintenanceFeedbackTheme` 和 1120px 内容宽度上限；保留候选列表右侧 18px scrollbar 安全区。
- 保护：不修改 `VideoSimilarityScanController`、`VideoSimilarityReport`、缩略图/相似取帧队列、
  播放器来源 playlist、stable videoId 对账、删除合并、回收站、标签/收藏或用户数据。
- 当前验证：相似视频页面结构/扫描生命周期 focused tests、主题与维护反馈 focused tests 通过；
  完整 `flutter test` 通过（621 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实检查从媒体库进入相似视频、扫描中摘要与视觉
  复核进度、重新计算禁用、返回媒体库路径，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：先收集相似视频页在宽/窄窗口、high contrast 和 reduced motion 下的视觉反馈，再决定继续
  细化其他维护状态或进入下一页面；不扩展到扫描、播放或数据边界。

# 2026-08-16 · 维护反馈组件族统一（已完成）

- 目标：继续第三阶段维护页面统一，把 `Dialog/Menu/Sheet/Tooltip/Snackbar` 收敛为 Calm Desktop
  Media Workspace 的共享反馈层。
- 当前修改：新增 `maintenance_feedback.dart`，提供维护主题对话框、菜单、modal sheet、Snackbar 和
  tooltip 入口；迁移标签中心、备份设置、Missing/Relink、目录管理及媒体库确认反馈，保留原有返回值、
  确认、撤销/恢复、危险动作和页面 owner。
- 保护：不修改 schema、`FilterQuery`、`TagQueryService`、搜索 controller、排序、filtered queue、
  `PlayerBackend`、缩略图/媒体详情队列、stable identity、root/detached 语义或用户数据。
- 目标文档：`docs/design/MAINTENANCE_FEEDBACK_UI_TARGET.md`。
- 当前验证：共享反馈 surfaces focused widget test、标签高风险/新建标签、Missing/Relink、目录管理、
  继续观看确认和备份维护路径均通过；架构契约 57 项通过；完整 `flutter test` 通过（619 passed，
  4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口在 1339×804
  下真实检查目录管理确认层、取消、返回媒体库和 Missing/Relink 维护外壳，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：继续维护页的共享菜单/sheet 实际调用迁移与 high contrast/reduced motion 实窗验收，再进入下一项
  仍缺视觉证据的维护状态；不扩展到业务边界。

# 2026-08-16 · 目录管理 UI 外壳重构（已完成）

- 目标：继续第三阶段维护页面统一，把目录管理收敛为“维护工作区 / 目录管理”的内容优先页面。
- 当前修改：复用维护标题栏并支持添加目录/重新扫描双动作的 expanded/compact 形态；为目录状态摘要和
  root 列表建立稳定桌面宽度；保留解除管理确认和数据保留说明。
- 保护：不修改 `LibraryApplicationFacade`、root、detached、扫描、解除管理、FileSystemAdapter、
  schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend 或用户数据。
- 目标文档：`docs/design/DIRECTORY_MANAGER_UI_SHELL_TARGET.md`。
- 当前验证：目录管理 150% focused widget test、compact 标题栏 focused test 通过；架构契约 57 项通过；
  完整 `flutter test` 通过（618 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口在 1339×804 下真实检查目录管理标题层级、添加/重新扫描入口、
  目录摘要、root 列表和返回媒体库路径，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：进入共享 `Dialog/Menu/Sheet/Tooltip/Snackbar` 组件族；继续保持维护页面回退路径和危险操作确认。

# 2026-08-16 · Missing / Relink UI 外壳重构（已完成）

- 目标：在播放器 Phase 2 已有实现证据的基础上，继续第三阶段维护页面统一；先把 Missing / Relink
  收敛为“维护工作区 / 缺失与重新关联”的内容优先页面。
- 当前修改：新增维护页面共享两级标题栏；为返回、批量路径替换和内容宽度建立稳定外壳；保留
  单条 relink、批量预览、空态、稳定身份说明与原有命中区。
- 保护：不修改 `videoId`、fingerprint、mutable path、missing 语义、Repository 提交、文件选择器、
  schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend 或用户数据。
- 目标文档：`docs/design/MISSING_RELINK_UI_SHELL_TARGET.md`。
- 当前验证：Missing/Relink 150% focused widget test 通过；稳定身份架构契约 57 项通过；relink command
  独立测试 4 项通过；完整 `flutter test` 通过（617 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口在 1339×804 下真实检查空态、维护标题栏、批量入口、
  内容宽度与返回媒体库路径，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：进入目录管理 UI 外壳或共享 Dialog/Menu/Sheet/Tooltip/Snackbar 组件族；继续保持稳定身份和
  用户数据边界不变。

# 2026-08-16 · 设置工作区 UI 外壳重构（已完成）

- 目标：在媒体库与标签中心外壳方向稳定后，推进下一页面设置工作区首页，统一维护上下文、
  首页分组和可进入入口的层级。
- 当前修改：设置 scaffold 的两级标题栏、首页上下文头部、分组入口 surface 和宽屏容器；保留
  `CacheSettingsPage` 状态 owner、section route、设置持久化、缓存/备份/删除/快捷键回调。
- 保护：不触碰 schema、FilterQuery、TagQueryService、filtered queue、PlayerBackend、缩略图/媒体详情
  队列、stable identity 或用户数据；既有 `settings.category.*`、返回和刷新 key 保持可达。
- 目标文档：`docs/design/SETTINGS_UI_SHELL_TARGET.md`。
- 当前验证：设置 focused widget tests 通过（20 passed）；旧交互清单通过；架构契约通过（57 passed）；
  完整 `flutter test` 通过（617 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口在 1339×804 下真实检查设置首页、播放与解码二级页、
  返回箭头、标题层级和首页滚动区域，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：等待设置首页视觉反馈；若方向保持，再进入下一个维护页的 UI 外壳重构，不扩展到业务边界。

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
