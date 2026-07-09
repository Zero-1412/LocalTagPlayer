# CHANGELOG.md

## 2026-07-09

### 搜索输入与标签切换流畅度

- 搜索框新增页面级 `FocusNode` 协调，`Ctrl+K` 会稳定聚焦主搜索框并选中现有文本，真实键盘输入、自动化输入和 controller 文本变化继续统一走 `onChanged` 筛选入口。
- 标签点击和搜索输入默认只刷新当前可见视频结果，不再同步触发全量标签计数刷新；需要刷新计数时使用 revision 保护的延后任务，旧任务完成后不会覆盖新筛选状态。
- 新增 widget smoke 覆盖 `Ctrl+K -> 输入 firefly -> onChanged -> 结果计数/列表更新`，确保搜索结果计数和可见列表同步变化。
- debug exe 真实窗口复测：连续 10 轮随机切换不同一级标签并点击其下二级标签两次，未观察到全页空白或冻结；`Ctrl+K -> 逐键输入` 可触发搜索筛选，结果从全量收敛到匹配列表。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

## 2026-07-08

### 二级标签筛选与交互流畅度

- 修复右侧一级展开卡中点击二级标签可能筛不出视频的问题：`FilterQuery` 现在携带当前媒体库 roots，并按当前文件树重新派生一级/二级层级参与匹配。
- 同时配置 `X:\test-media` 与 `X:\test-media\鸣潮` 这类子 root 时，筛选会以最上层 root 为准，`X:\test-media\鸣潮\尤诺` 正确命中一级 `鸣潮`、二级 `尤诺`。
- 排序 helper 改为预计算标题、目录、扩展名、日期、大小和路径 key，减少大库切换排序或标签后反复拆字符串造成的 UI 卡顿。
- 筛选后的 `FilterState` 排序也复用同一预计算排序入口；标签计数刷新延后到可见结果更新之后，避免点击标签后立即阻塞主界面。
- 项目规则新增：二级标签必须永远从属于一级标签，不能与一级标签同层；标签筛选和排序方式改变时永远以界面流畅度为第一优先级。
- 本次未修改 SQLite schema、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### Windows 风格排序字段

- 顶部排序字段对齐 Windows 文件排序习惯：菜单按“名称 / 日期 / 类型 / 大小 / 目录 / 添加时间”展示。
- “日期”沿用旧的 `recent` 偏好 key 以兼容已保存设置，但排序语义改为优先使用文件修改时间，缺失时回退到应用入库时间。
- “名称”改为大小写不敏感的自然排序，`video2` 会排在 `video10` 前面；“类型”按扩展名排序，“大小”按扫描到的文件大小排序。
- 排序下拉面板增加最小宽度，避免新增长字段后菜单文字溢出或与按钮宽度强绑定。
- 新增 widget tests 覆盖 Windows 风格字段、自然排序、类型/大小/日期/添加时间排序和菜单宽度稳定性。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 文件树层级标签与本地媒体库排序

- 右侧标签发现面板的 folder 一级/二级候选改为从 `store.videos` 的真实路径和 `store.roots` 重新派生，不再信任历史 `tags` 表里的 folder.primary / folder.child 记录。
- 多个 root 同时命中同一视频时优先使用最上层 root，例如 `X:\test-media\崩坏三\李素裳\clip.mp4` 会派生一级 `崩坏三`、二级 `李素裳`，不会把 `李素裳` 当一级。
- folder 组筛选继续通过 `primaryTagId/childTagId` 的路径兼容字段执行，避免历史 tag id 与当前文件树 root 不一致时影响筛选结果。
- 本地媒体库路径浏览里的视频项现在使用与媒体库、标签筛选、本地收藏、最近播放相同的 `sortedLibraryVideos` 排序规则；文件夹仍固定在视频前面。
- 新增 widget test 覆盖 `X:\test-media` 与子 root 并存时的一级/二级派生。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 媒体库排序状态持久化

- 新增媒体库排序偏好持久化到独立 `library_sort.json`，不再每次进入媒体库页面都回到默认排序。
- 媒体库全量结果、标签筛选结果、本地收藏和最近播放统一使用 `sortedLibraryVideos` 排序 helper，避免不同来源各自排序导致选择的排序方式不生效。
- 排序偏好独立于播放硬解 `settings.json`，播放设置保存不会覆盖媒体库排序字段和方向。
- 新增 widget tests 覆盖排序偏好 save/load，以及筛选、收藏、最近播放三类来源使用同一排序规则。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 标签筛选一级列表层级修复

- 右侧标签发现面板增加文件树层级守卫：一级列表只接收 `folder.primary`、`folder` 来源、无父级且 id 形态为 `folder.primary:*` 的标签。
- 二级候选只接收 `folder.child`、`folder` 来源、带父级且 id 形态为 `folder.child:*` 的标签；二级标签继续只在一级展开卡或“全部二级标签”页签展示。
- 补充 widget test，模拟历史污染数据把二级/manual 标签误放进 `folder.primary` 组，确认一级候选不会展示这些污染项。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 主界面标签与排序性能 QA

- `LibraryStore` focused tests 增加扫描异常路径覆盖：内容变化会清理旧媒体详情/缩略图错误，不可访问 root 不会误删仍存在的视频，非 manual 来源标签不能走批量 manual 添加/移除。
- 右侧标签筛选的“一级标签”页签只展示 `folder.primary` 文件夹一级标签；二级标签统一收敛到“全部二级标签”页签，避免一级页签混入热门二级标签造成层级误解。
- 媒体库排序切换改为直接重排当前 `FilterState`，不再触发完整筛选刷新和 `resultCounts` 重算；标签计数刷新延后执行，降低切换排序或标签时的主线程阻塞感。
- “添加时间”排序只使用 `addedAt`，播放器返回更新 `lastPlayedAt` 不再导致主媒体库默认排序重排。
- 播放器 controller tests 覆盖二级队列切换回退和 open 请求失败后继续保留最新打开请求。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 来源、`PlayerBackend` 或缩略图/media 队列。

### LibraryStore 边界继续拆分

- `LibraryStore` focused tests 继续覆盖 metadata 去重持久化、扫描删除缺失视频并保留剩余 manual 标签、manual child link 删除不破坏 folder child 兼容字段。
- 新增 `LibraryMetadataPersistence`，集中 metadata 表 roots / favoriteTags 的加载、去重和保存。
- 新增 `LibraryScanCoordinator`，承接扫描结果合并、增量视频写入、缺失视频清理、folder 标签索引刷新和 metadata batch 保存。
- 新增 `LibraryTagMaintenance`，承接 manual/folder 标签来源分离策略、批量 manual 标签添加/移除、folder/manual 标签索引同步。
- 播放器侧新增 `PlayerOpenRequestController` 和 `player_delete_dialog.dart`，把 open 请求最新路径/worker/遮罩状态与删除确认弹窗从 `PlayerPage` 拆出。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### Store 测试保护与播放器拆分

- 新增 `test/library_store_test.dart` focused tests，覆盖临时目录扫描、folder 一级/二级标签派生、manual 标签添加/移除不破坏 folder 标签，以及 roots、favoriteTags、收藏和播放时间的 `save/load` 持久化。
- `LibraryStore` 增加 `close()`，用于测试和后续 repository/service 拆分时释放 SQLite 文件句柄。
- 新增 `LibraryScanService`，将文件系统扫描、视频扩展名识别、stat 读取、folder 标签派生和轻量媒体指纹从 `LibraryStore.scan()` 中拆出；`LibraryStore` 仍负责 SQLite 写入、内存状态和标签索引同步。
- `player_page.dart` 拆出 `player_context_panel.dart` 和 `player_queue_sidebar.dart`，保留播放器生命周期、跳转、快捷键和队列语义不变。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面模块继续拆分

- 继续按职责拆分 `library_widgets.dart`：本地媒体库路径浏览迁到 `widgets/library_local_view.dart`，右侧标签筛选面板迁到 `widgets/library_tag_discovery_panel.dart`，视频网格、列表行和卡片迁到 `widgets/library_video_results.dart`。
- `library_page.dart` 中的筛选摘要、显示表达式、播放队列标题、排序比较和排序切换逻辑迁到 `pages/library_page_helpers.dart`，保留页面主体负责状态输入和布局编排。
- 评估 `library_store.dart` 后确认它仍耦合 SQLite 持久化、目录扫描、标签索引同步和手动标签维护；本轮只记录边界，不在缺少专门测试时拆分扫描/标签/持久化层。
- 本次保持 `part of '../app.dart'` 编译边界，不改变私有符号可见性、SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面 UI 模块拆分

- 分析当前代码行数后确认最大耦合点：`library_widgets.dart` 约 5001 行、`player_page.dart` 约 2126 行、`library_page.dart` 约 1943 行、`library_store.dart` 约 1140 行。
- 先按低风险边界拆分 `library_widgets.dart`：测试/自动化 key 移到 `widgets/library_smoke_keys.dart`，顶部排序控件和排序枚举移到 `widgets/library_sort_control.dart`。
- 保持现有 `part of '../app.dart'` 架构，不切换 import/export 边界，避免一次性破坏私有符号访问和业务行为。
- 拆分后 `library_widgets.dart` 降到约 4647 行，排序控件模块约 297 行，smoke key 模块约 68 行。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 排序抽屉展开

- 排序字段列表从 `PopupMenuButton` 浮动菜单改为自定义下拉面板，面板贴合排序字段按钮底部并向下展开。
- 下拉面板使用字段按钮同宽、底部圆角和轻阴影，顶部不再作为独立浮层覆盖或压住按钮。
- 顶部工具栏 smoke 改为验证排序下拉面板与字段按钮底部对齐且宽度一致。
- debug exe 真实窗口复测：点击“添加时间”后，“添加时间 / 名称 / 目录”列表像抽屉一样从按钮下方展开，未再出现按钮与列表重叠。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 本地收藏叠加筛选 QA

- 修复左侧“本地收藏”进入后再点击右侧标签会丢失收藏条件的问题：本地收藏入口现在同步设置 `favoriteOnly`，标签筛选会继续按 AND 关系叠加。
- 当前筛选 chip 中的收藏文案统一为“本地收藏”，不再残留“智能收藏”。
- 排序字段菜单增加垂直偏移，避免弹出列表与顶部排序按钮贴边或视觉重叠。
- 顶部工具栏 smoke 增加排序菜单位置断言，确保菜单项在排序按钮下方展开。
- debug exe 真实窗口复测：本地收藏播放队列标题正确；本地收藏叠加 `mod + ntr` 后结果收敛到 0 条且收藏 chip 保留；网格/列表下排序字段和正倒序切换未发现遮挡。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 顶部工具栏与排序方向

- 顶部工具栏移除“收藏筛选”按钮，收藏视频入口统一到左侧“本地收藏”，避免与侧栏来源视图重复。
- 左侧“智能收藏”改名为“本地收藏”，当前筛选摘要、结果 chips 和播放器队列标题同步更新。
- 排序控件改为工具栏内的分段式控件：左侧选择排序字段，右侧独立切换“正序 / 倒序”。
- 排序方向纳入媒体库筛选状态缓存 key，切换方向时会刷新当前列表顺序，但不改变标签筛选语义。
- 新增顶部工具栏 smoke 断言，覆盖重复收藏按钮移除、排序方向文字和点击回调。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 列表模式操作区对齐

- 列表模式视频行移除内容区 980px 宽度上限，行内信息区使用剩余空间，播放、收藏、更多操作区固定到卡片右侧。
- 操作按钮保持 8px 间距，右侧保留约 8px 内边距，避免按钮贴边或悬在列表中部。
- 新增宽屏列表行 smoke 断言，验证“更多”按钮右边缘贴近列表行右边缘。
- 使用 debug exe 真实窗口复测列表模式：每行播放、收藏、更多按钮已右对齐到列表卡片右侧。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 顶部工具条与播放器返回性能

- expanded 顶部工具条取消搜索框宽屏固定上限，搜索框会填满右侧动作按钮左侧的剩余空间，窗口放大时红框区域同步扩展。
- 播放器返回主界面后，`lastPlayedAt` 更新改为轻量路径：不再触发全库标签计数、完整筛选刷新和缩略图预取，降低大媒体库返回卡顿。
- 保留最近播放、收藏和按播放时间排序场景的必要轻量重建，不改变播放器队列来源或标签筛选语义。
- 新增顶部工具条宽屏填充 helper 测试，避免搜索框重新退回固定宽度。
- 使用 debug exe 真实窗口复测：最大化后顶部搜索工具条已跟随宽度拉伸；从视频进入播放器约 980ms，点击 Back 返回主界面约 698ms。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面布局比例

- 主界面 expanded 状态下，左侧导航和右侧标签筛选面板由固定宽度改为基于窗口总宽度的比例宽度，窗口放大/缩小时三块区域会同步保持相对占比。
- 较窄 expanded 宽度下优先保护中央结果区，避免右侧标签面板把视频结果区域挤压到不可用。
- 新增 `mainLibraryLayoutSlotsForWidth` 纯函数测试，覆盖 1280 / 1600 / 1920 宽度下左右栏增长、中心区增长和总宽度守恒。
- 使用 debug exe 真实窗口复测普通窗口与最大化窗口：三栏区域可见比例随窗口尺寸变化，视频结果区可扩展到更多列，右侧标签筛选未遮挡中心内容。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 搜索输入与 Git 规则

- 新增 Git 远程提交规则：验证通过并完成本地提交后，必须执行 `git push` 到当前分支远程跟踪分支；如果远程不存在、认证失败、网络失败或用户明确要求暂不推送，记录原因并保留本地提交。
- 顶部搜索框从 `SearchBar` 改为稳定 `TextField` 输入链路，保留原搜索图标、`Ctrl + K` 提示、controller 和 `onChanged` 筛选刷新方式。
- 新增顶部搜索框 widget smoke test：输入 `lupa` 后断言 `TextEditingController` 和 `onSearchChanged` 都收到新关键字。
- 真实窗口 QA 继续复测：Computer Use 的 `type_text` / `set_value` 对 Flutter Windows 文本控件仍不稳定；逐键输入可触发搜索筛选，但目录管理、本地媒体库路径和右侧一级/二级筛选因 Windows 自动化前台窗口状态中断，仍需人工复测。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面 smoke test

- 使用 debug exe 对主界面第一轮 smoke test：覆盖媒体库、最近播放、智能收藏、标签中心、设置、排序菜单、右侧标签面板收起/恢复和播放入口。
- 修复右侧标签筛选面板收起后恢复入口缺少按钮语义的问题：收起窄条现在暴露“展开标签筛选”语义、Tooltip 和稳定 smoke key，点击后可恢复右侧标签面板。
- 新增 `collapsedTagDiscoveryRailSmokeHarness` widget smoke test，覆盖收起窄条 key、Tooltip 和点击回调，避免恢复入口再次退化。
- 播放入口复测通过：从主界面底部“播放”进入播放器，右侧队列显示 `1 / 11078`，返回主界面正常。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 语义、播放器队列规则、缩略图/media 队列或用户数据维护规则。

## 2026-07-07

### 媒体库参考顶部布局

- 全仓库自有文档和代码注释完成中文化审查：Dart 注释英文句子已改为中文，`ROADMAP.md`、`docs/chat_tasks`、`.agents/skills`、安装说明和 FFmpeg 工具说明中的英文/乱码正文已改为中文；保留必要技术术语、路径、命令和 API 名称。
- 新增中文优先规则：文档新增/修改、代码注释、任务记录和 Git 提交信息默认使用中文；只有代码、第三方 API、命令、路径、固定术语和外部错误信息保留必要原文。
- 清理右侧标签面板周边残留乱码注释：`_SmartFilterContextCard` 和 `TagDiscoverySmokeHarness` 的维护说明改为中文，不改变筛选逻辑、播放队列或数据库。
- 本轮验证通过：`dart format lib/src/widgets/library_widgets.dart`、`flutter analyze`、`flutter build windows --debug`。
- 修复右侧热门二级标签“更多标签”按钮：从禁用样式改为可点击展开/收起，并显示 `当前/总数`。
- “全部二级标签”页签改为使用完整二级标签列表，不再被热门区默认 12 个标签截断。
- 热门二级标签仅在同名冲突时显示所属一级标签，解决 `ntr/NTR` 等同名标签无法区分的问题。
- 复查媒体库/本地媒体库职责：媒体库仍是全量视频重置入口，本地媒体库仍是路径浏览入口，不改筛选语义、不改扫描或播放逻辑。
- 修复非最大化 debug 窗口下的可视区域溢出：顶部工具条在实际行宽不足时让搜索框弹性收缩，单列视频卡片高度按 16:9 缩略图重新留足空间，列表行动作区在中等宽度下降级为图标按钮。
- 使用 computer-use 复测普通窗口和最大化窗口：顶部工具条、列表行“播放 / 收藏 / 更多”、右侧标签筛选面板、本地媒体库返回入口均可见，未发现遮挡或跑出可视区域。
- 扩展稳定 smoke harness：列表行“播放 / 收藏 / 更多”按钮增加 key 与回调计数断言，本地媒体库 `dense` 列表模式增加文件夹进入/返回验证。
- 右侧标签筛选 smoke 增加结果状态断言：默认专辑 chip 显示当前一级全部示例结果，Child01 chip 会把结果收敛到对应二级标签。
- 列表行播放按钮从 `FilledButton.icon` 改为固定尺寸自定义紫色按钮，避免行内双击识别和按钮内部命中链影响自动化单击验证；视觉尺寸和入口语义保持不变。
- 将本地媒体库返回、鼠标侧键返回、右侧标签筛选展开/收起的 smoke test 方法从截图坐标校准改为稳定 key + harness：测试直接驱动真实 `_LocalLibraryView` 和 `_TagDiscoveryZone`，并断言路径/面板状态。
- 新增 `LibrarySmokeKeys`、`LocalLibrarySmokeHarness`、`TagDiscoverySmokeHarness`，覆盖文件夹进入、返回按钮、鼠标后退侧键、一级标签展开/收起、二级“展开全部/收起”和右侧标签 tab 切换。
- `AppPaths` 增加测试进程内数据目录覆盖入口，服务 widget smoke 的可回滚 profile；debug exe 临时 profile 仍使用 `LOCAL_TAG_PLAYER_DATA_DIR`，真实默认数据目录不变。
- 新增 `LOCAL_TAG_PLAYER_DATA_DIR` 数据目录覆盖，用于临时 profile / 可回滚测试库；不设置时仍使用系统应用支持目录。
- 使用临时 profile 完成最近播放真实鼠标复测：单条删除、全选删除和清空全部都只清理临时库中目标视频的 `last_played_at`。
- 临时 profile 下记录三大入口切换响应：媒体库首次约 213ms，最近播放约 63ms，智能收藏约 59ms，再回媒体库约 51ms；进程均保持响应。
- 热门二级标签区只显示二级标签名，不再显示“所属一级标签”小标签；默认专辑也不会进入热门/全部二级候选列表。
- 一级标签展开卡过滤真实子标签里的“默认专辑”，只保留卡片开头的虚拟默认专辑 chip，避免同一展开卡出现两个默认专辑。
- 本地媒体库文件夹浏览增加返回栈：点击文件夹进入下一级后可用顶部返回按钮回到上一层，鼠标后退侧键也触发同一返回逻辑。
- 最近播放清理增加目标选择测试覆盖：单选删除、全选删除和清空全部都只作用于有播放记录的视频，不影响未播放视频。
- 媒体库、最近播放、智能收藏三大入口改为轻量来源切换：最近播放和智能收藏直接使用内存集合生成结果，媒体库重置时即时清空筛选并重建全量结果，减少入口切换卡顿。
- 最近播放主结果区新增管理工具条：支持单选、全选、删除已选和清空全部；删除语义仅清理 `lastPlayedAt`，不删除视频文件、标签、收藏或播放进度。
- “我的标签库”改为“本地媒体库”：侧栏只管理本地库路径，添加入口复用目录选择，单项移除只更新 root 配置，不再打开标签新增弹窗。
- 本地媒体库路径浏览支持文件夹/视频混合展示：文件夹显示为文件夹项并可进入下一层，已入库视频复用现有卡片/列表行，网格/列表切换继续生效。
- 设置入口从顶部工具条移除并放到左侧功能栏底部；小窗口下使用滚动内容 + 底部固定按钮结构，debug exe 坐标点击确认可进入设置页。
- 最近播放入口从弹窗改为主结果区视图：点击左侧“最近播放”会直接用网格/列表展示最近播放视频，播放时队列也使用该可见列表。
- 左侧“媒体库”入口改为重置入口，点击后清空搜索、标签、分组、排除和收藏筛选，回到全部视频。
- 设置入口补齐到顶部工具条和左侧侧栏，复用已有 `CacheSettingsPage` 展示播放解码设置和缩略图缓存统计。
- “我的标签库”新增标签弹窗支持输入即时过滤已有标签，并在创建/保存失败时用 SnackBar 显示错误。
- 左侧导航继续收敛：删除重复的“播放历史”、低价值的“当前筛选”和“常用标签”，保留“最近播放”并接入最近播放弹窗。
- 目录管理弹窗新增非破坏性移除根目录入口；该操作只更新 root 配置，不删除磁盘文件、不立即清理已索引视频记录。
- “我的标签库”改为可维护快捷标签列表：支持添加已有标签或创建 manual 标签，支持移除快捷项，列表过多时固定高度滚动；移除快捷项不删除真实标签或视频关联。
- 右侧标签数量改为全库稳定计数缓存，点击一级/二级筛选后其它标签数量不会从侧栏消失。
- 顶部工具条修复搜索框在宽屏下占满剩余空间的问题，标签中心、收藏筛选、排序和网格/列表切换在高宽桌面窗口下保持可见。
- 列表行二次修复：限制行内容可读宽度、加宽操作区并放宽行高，列表态播放/收藏/更多按钮在宽屏下可见且不再出现 overflow。
- 列表视图改为真正的密集列表模式：`dense` 结果视图使用 `ListView.builder` 和横向列表行，不再复用卡片网格尺寸。
- 新增列表行专用 UI：左侧缩略图、中部标题/路径/标签、右侧播放/收藏/更多按钮，保持播放入口、收藏和标签编辑回调不变。
- 修复源码乱码清理后暴露的结构缺失：恢复标签发现 helper、右侧标签面板 build、缓存设置页、播放器横向滚动条和缓存统计类，确保主界面可编译可运行。
- 清理 `LibraryPage` / `library_widgets` 触达区域乱码注释和用户可见乱码字符串；触达文件乱码扫描、`flutter analyze`、`flutter build windows --debug`、`flutter test` 均通过。
- 主界面追加点击 smoke 修复：当前筛选条会显示搜索关键字 chip，关键字可通过 chip 的 X 单独清除，避免搜索过滤残留但界面看似“全部视频”。
- 左侧导航补齐“播放历史”和“目录管理”可点击入口；播放历史以只读弹窗展示最近播放条目，目录管理以只读根目录弹窗承载添加目录/重新扫描入口。
- debug exe 复测通过：搜索输入与清除、标签中心打开/返回、播放历史弹窗、目录管理弹窗、卡片更多入口、播放入口与全库队列传递均有可见响应。
- 右侧一级标签列表默认显示 7 个，底部“更多一级标签”改为展开/收起开关。
- 右侧一级标签列表新增“按数量 / 按名称”排序控件；按数量使用当前显示数量排序，按名称使用标签名排序。
- 修复默认专辑和二级标签定位：右侧 folder.child tagId 会反解到 `FilterQuery.childTagId` 的标签名，二级标签 fallback 会把 parentId 反解成一级标签名再匹配视频 childTags。
- 右侧面板滚动列表增加独立 Scrollbar 和内容右侧留白，减少滚动条与一级标签行重合。
- 右侧“标签筛选”补强互斥交互：点击一级折叠行会选择该一级的“默认专辑”并展开，一级之间互斥；当前一级下二级标签互斥，重复点击已选二级会回到默认专辑。
- 所有一级展开卡片新增“默认专辑”虚拟 chip，用当前一级标签过滤表达“该一级下全部视频”，不新增 tag 数据、不改 schema。
- 一级展开标题行改为固定高度整行命中区，“展开全部”保持当前一级本地开关并支持再次点击收起。
- 右侧“标签筛选”面板继续微调一级展开卡片：默认按蓝图展示 9 个二级 chip，“展开全部（总数）⌄”改为可点击轻量文本按钮，并且只影响当前一级标签的本地展开状态。
- “展开全部”点击区域从文字宽度扩大为展开卡片底部整行 32px 高命中区，减少横向点偏时误触下方一级行。
- “更多一级标签”按钮弱化为一级列表底部的浅紫整行文本按钮，高度压到 30px，减少对热门二级标签区的视觉抢占。
- 热门二级标签区按蓝图微调垂直节奏：默认一级列表收回到 5 个，热门 chip 固定 3 列，标题字号略收，底部“更多标签⌄”按钮居中并固定轻量高度。
- 清理右侧标签筛选面板及候选区组件内残留乱码注释/tooltip 说明，避免后续视觉 QA 时被历史编码问题干扰。
- 右侧“标签筛选”面板按蓝图重构视觉：桌面宽度约 440px，增加顶部/左右外边距，使用 20px 圆角、`#E6ECF5` 轻边框和极轻阴影。
- 删除右侧一级区域的“一级标签 40”标题行、绿色竖条和重色强调，一级列表直接使用浅色展开卡片与折叠行。
- 二级标签 chip 改为自定义轻量样式：普通态无 tag 图标，选中态浅紫背景 + check；热门二级标签标题固定为“热门二级标签（可直接选择）”，不再显示数量括号。
- 右侧标签筛选一级列表改为蓝图式手风琴：默认展示更多一级标签，点击折叠一级行展开对应二级标签，避免所有二级标签都被固定到第一个一级标签下。
- 一级展开行新增独立筛选按钮，二级标签 chip 增大命中区域并修复 tooltip 文案，降低右侧面板“点不到”的问题。
- 当前筛选条的“清空全部”按钮移出横向 chips 滚动区域，固定在滚动区外侧，减少点击被滚动容器吞掉的风险。
- 继续按参考图红框微调主界面比例：右侧标签筛选面板改为独立卡片式外观，增加桌面端外边距和固定宽度，视觉上更接近参考图的“工具面板”而不是播放器式贴边栏。
- 顶部搜索框增加最大宽度约束，普通窗口保持弹性，超宽窗口不再横向拉满；顶部工具条左右留白和按钮节奏更接近参考图。
- 右侧标签筛选的分组卡片减少嵌套边框，展开一级标签时用单张组卡承载子标签，降低“列表套列表”的拥挤感。
- expanded 媒体库布局继续按参考图红框修正：顶部工具条现在横跨中间结果区和右侧标签筛选区，右侧标签筛选面板从第二行开始，不再从窗口顶部开始。
- 中间当前筛选条仍限定在视频结果列内，和右侧筛选面板并列，保持“当前筛选 chips + 结果数”和“标签筛选”各自归属清晰。
- 媒体库主界面顶部按参考图选中区域调整：搜索框改为弹性占位，标签中心、收藏筛选、排序和网格/列表切换保持同一行。
- 当前筛选区改为白色工具条，直接展示“当前筛选（AND）”、筛选 chips、清空全部和结果数量；桌面端 chips 横向滚动，避免挤压右侧结果数。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 构建验证

- 本轮 `dart format`、`flutter test`（16 项）、`flutter analyze`、`flutter build windows --debug` 均通过。
- 本轮 `dart format`、`flutter test`、`flutter analyze`、`flutter build windows --debug` 均通过；debug exe 使用临时 profile 启动 3 秒保持运行并可安全关闭。
- `flutter analyze` 通过。
- `flutter build windows --debug` 通过。
- `flutter test` 通过。
- 本轮 debug exe 真实窗口复测：最近播放可打开弹窗，目录管理可见删除根目录按钮，顶部工具条入口在宽屏下可见，列表模式可切入且列表行播放/收藏/更多按钮可见、无 overflow。Win32 坐标脚本仍未稳定点开列表行“更多”弹窗，需人工鼠标或更稳定桌面自动化补测该命中路径。
- `dart format lib/src/pages/library_page.dart lib/src/widgets/library_widgets.dart` 通过。
- 本轮 debug exe 截图验证右侧一级列表默认 7 个、排序控件可见、按数量排序正确、滚动条与列表内容有留白；OS 鼠标坐标在当前 Windows/DPI 环境仍偏移到应用外，真实点击路径需人工补测。
- 本轮 debug exe 验证二级 chip 真实点击：当前筛选能切到“崩铁 + 克拉拉/停云”，结果数量与视频路径跟随当前二级标签；一级标题折叠与展开全部受当前 Windows DPI 坐标自动化影响，建议人工用真实鼠标再补一轮确认。
- 本轮 debug exe 追加验证右侧面板启动可见、标签页切换和一级折叠行点击；“展开全部”按钮已扩大为整行命中区，但坐标自动化受桌面/DPI 环境影响未稳定截到最终展开状态，需人工补一轮该按钮复测。
- 参考宽度截图确认热门二级标签区已进入右侧面板视口，chip 按 3 列排列，“更多标签⌄”按钮居中。
- debug exe 已启动并验证收藏筛选、排序菜单和结果视图切换可点击；搜索框自动输入在 Windows 自动化截图中没有可靠显示，仍需人工复测搜索输入路径。
- 本轮 debug exe 追加验证右侧标签页切换、右侧标签 chip 点击和筛选 chip 关闭；“清空全部”按钮自动化坐标未稳定触发，需后续人工或无障碍树复查命中区域。

## 2026-07-05

### 媒体库标签交互性能

- `TagQueryService.resultCounts` 改为按标签组分批统计候选数量；每个标签组只扫描一次当前视频集合，并优先使用 `videoTagIdsByPathKey` 与候选 tagId 集合求交集，避免每个候选标签都全库扫描。
- `LibraryPage` 不再在 `build()` 中同步执行筛选结果和 `resultCounts` 重计算；当前视频列表与候选数量缓存到页面 State 中，由筛选条件变化后异步刷新。
- 标签点击、清空筛选、搜索、排序和兼容一级/二级标签切换统一走 revision 保护；连续快速点击时旧的视频结果或候选数量结果不会覆盖最新筛选状态。
- 筛选刷新分阶段更新：先更新当前视频结果和播放器可消费的 filtered queue，再刷新左侧候选数量；刷新期间保留旧数量并显示轻量进度提示。
- 缩略图可见区域预取从 `build()` 的 post-frame 回调移到视频结果刷新完成后触发，避免仅因候选数量变化重复触发预取。

### 构建验证

- `flutter analyze` 通过。
- `flutter build windows --debug` 通过。

## 2026-07-04

### 响应式 UI 与平台 polish

- Chat 7 第一阶段完成：统一应用弹窗的浅色 surface、8px 圆角、边框和标题层级。
- 媒体库侧栏目录操作按钮改为可换行按钮组，compact 筛选 BottomSheet 使用统一背景和顶部圆角。
- 媒体库顶部栏在 compact 下压缩搜索提示、排序控件横向滚动、结果数量分行显示，避免搜索框、按钮组和计数溢出。
- 视频卡片网格根据宽度调整 padding、间距、卡片高度和单列布局；卡片底部操作改为弹性播放按钮 + 固定图标按钮。
- 缓存诊断页 compact 下将 AppBar 操作收进菜单，页面 padding 与媒体库统一，避免小窗口横向挤压。
- Tag Manager 从固定左右栏改为 responsive Flex：expanded 常驻 360px 管理侧栏，medium 收窄到 316px，compact 垂直堆叠列表和详情。
- 播放器 compact 下隐藏常驻右侧队列，改为 AppBar 队列入口打开底部队列面板；队列面板宽度不会超过当前窗口。
- 补充 Chat 7 macOS/Linux 适配 notes：FFmpeg bundled tools、sqlite3 动态库、文件管理器 reveal、窗口尺寸和快捷键差异。

### 项目知识库

- 新增 PROJECT.md：项目背景、技术栈、约定、运行方式。
- 新增 ARCHITECTURE.md：当前模块、核心类、数据流、后续拆分建议。
- 新增 CURRENT_TASK.md：当前状态、已知问题、下一步建议、新 Chat 启动提示词。
- 重写 README.md：作为项目入口，避免继续使用历史乱码内容。

### 播放器与标签

- 标签选择统一改为单选。
- 二级标签支持鼠标滚轮和鼠标拖拽横向滑动。
- 从二级标签筛选进入播放器时，播放器使用当前一级标签完整同层列表。
- 播放器右侧顶部显示当前一级标签下的同级二级标签。
- 播放器右侧二级标签支持点击切换列表。
- 默认专辑排序到二级标签第一个。
- 播放器右侧列表改为当前播放位置附近窗口预读，不再对整条播放列表批量读取媒体信息。
- 播放器右侧列表改为固定高度虚拟列表，列表项缓存缩略图和媒体信息 Future，降低滚动与选中刷新时的异步抖动。
- 播放器右侧列表视觉改为更紧凑的专业播放器侧栏样式，强化当前播放项、选中项和媒体信息层级。
- 播放器现在使用进入页面时的 filtered queue 副本作为播放队列；playlist 为空时兜底到 initialItem，initialItem 不在 playlist 时安全从队列首项开始。
- 播放器右侧队列标题显示当前筛选摘要，覆盖 keyword、一级/二级兼容筛选、分组 include/exclude 和收藏筛选，并保持当前序号显示。
- 播放器右侧二级标签切换只在当前 filtered queue 内切换子集，避免从播放器扩展回全量媒体库队列。
- 播放器快速切换视频时串行处理最新 open 请求，降低旧 open 覆盖新 open、dispose 后继续 setState 和 currentIndex 错位风险。
- 验收补漏：无筛选队列标题改为“当前列表”，右侧序号统一为 `1/1661` 格式，并补强 open worker 对结束瞬间 pending 请求的接续处理。

### 缓存与诊断

- 缩略图使用 FFmpeg 优先，media_kit 截图兜底。
- 媒体信息使用 FFprobe 优先，media_kit 兜底。
- 设置页展示 FFmpeg/FFprobe 路径、缩略图缓存状态、媒体信息缓存状态。
- 缩略图队列改为可见区域优先，后台批量任务单独限流，避免后台补缓存占满解码和磁盘资源。
- 后台批量缩略图默认只使用 FFmpeg；media_kit 截图兜底仅用于可见区域优先任务，降低播放卡顿风险。
- FFmpeg 缩略图输出先写临时文件，成功后再替换缓存文件，避免半截 JPEG 被当作有效缓存。
- FFmpeg/FFprobe 增加更明确的超时错误；FFprobe 只读取必要 stream 字段，减少探测输出和解析开销。
- 缓存诊断页新增后台并发统计，补缓存任务完成后按钮自动恢复，并保存缩略图/媒体信息失败原因。
- FFmpeg/FFprobe 调用收敛到 `DesktopFFmpegBackend` 兼容适配层，`ExternalMediaTools` 继续保留原 Windows bundled tools 查找行为。
- 缓存诊断页新增 FFmpeg/FFprobe 版本、缩略图后台排队上限、媒体信息排队/执行中/本轮完成/本轮失败状态。
- 缩略图 media_kit 兜底写入改为临时文件成功后替换，避免半截 JPEG 成为有效缓存。
- 已存在缩略图缓存读取时校验 JPEG 头尾和文件长度，0 字节或半截缓存文件会被丢弃并重新进入缺失状态。
- 缩略图后台批量任务增加排队上限，降低大库补缓存和播放期资源竞争风险。
- 缓存诊断页新增失败重试、清除失败记录和异常文件列表，失败原因继续保存到现有视频表错误字段。
- 缓存诊断页失败重试和清除失败记录按钮在执行中禁用，避免重复触发同一批任务。
- 播放器右键菜单支持视频信息与诊断检查。
- 播放诊断改为弹窗打开期间持续采样，暂停播放时停止采集，关闭弹窗后释放采样任务。
- 播放诊断新增连续采样次数、最近采样时间和异常原因提示，用于观察播放位置推进、掉帧、缓存与 AV 同步问题。

### 媒体库与 SQLite

- 新增 `LibraryStore` 持久化边界 focused tests，覆盖 tag aliases / hidden / favorite / sortOrder 持久化、manual child tag 与 folder child tag 分离、video upsert/delete 后关联清理。
- `LibraryStore` 拆出 `LibraryTagPersistence` 和 `LibraryVideoPersistence`：标签/别名/视频标签关联写入、视频行映射和视频删除写入进入独立 helper，扫描和 folder/manual 业务语义仍留在 store 协调。
- `deleteVideo` 同步移除内存视频索引和 `video_tags` 关联，避免删除后当前 store 与重载 store 状态不一致。
- 右侧标签筛选面板一级排序去除独立标题，选项改为“数量 / 名称 / 常用”；“常用”使用本次会话一级标签点击次数，不新增 schema。
- 右侧一级标签数量排序改为稳定数量基准，避免点击一级标签后因当前筛选结果数变化导致该标签置顶或其它标签重排。
- “全部二级标签”页签改为从标签库展示二级标签，当前筛选下结果数为 0 的标签也保留展示，避免空面板。
- 右侧一级标签行点击改为只展开/收拢，展开卡内的“默认专辑”和二级标签 chip 负责筛选，减少点击冲突和展开延迟感。
- 媒体库结果区取消筛选切换时的网格 AnimatedSwitcher，改用稳定 RepaintBoundary，降低标签筛选时的画面抖动。
- expanded 布局新增右侧标签筛选面板收纳窄条，可收起/恢复标签总列表且保留当前筛选状态。
- 媒体库筛选结果和候选数量移出 `build()` 同步路径，改为页面级缓存 + revision 分阶段刷新；标签点击先反馈选中态，再刷新视频列表和候选数量。
- `TagQueryService.resultCounts` 按标签组批量统计，每个候选组只扫描一次视频集合，并优先使用规范化 tagId 索引，降低大库标签切换时的候选数量计算成本。
- 当前筛选条新增轻量刷新 spinner，提示视频结果或候选数量正在刷新，但不阻塞网格滚动和点击。
- 媒体库顶栏新增标签管理入口，打开后基于当前筛选结果提供批量打标签范围。
- 新增 `TagManagerPage`：支持查看 tag groups、tags、tag aliases、usage count，并按 `folder` / `manual` / `rule` / `filename` / `import` / `auto` 来源展示使用数量。
- 标签管理第一阶段支持创建 manual tag，编辑 displayName、aliases、hidden、favorite、sortOrder，并可移动 tag 到其它 group。
- 当前筛选结果支持批量添加 manual tag、批量移除 manual tag；批量移除只删除 `video_tags.source = manual` 的关系，不会移除 folder 路径派生关系。
- 删除和合并标签当前保留入口和确认弹窗，会先检查 `video_tags` 引用；folder 来源 tag 不允许第一阶段硬删除。
- 分组 tag 匹配在存在规范化索引时优先按 tagId，避免同名 folder 兼容字段误命中 manual tag。
- 验收补漏：Tag Manager 左侧直接展示 tag groups；批量添加/移除只允许 manual 来源标签，避免误把 folder 来源标签作为普通 manual 操作；创建 manual tag 时阻止覆盖同分组同名的非 manual 标签。
- 媒体库首页新增网页式分组 Tag 筛选侧栏，按现有 `tag_groups` 展示标签，并显示候选结果数。
- 媒体库分组筛选支持包含标签和排除标签，排除项在当前筛选条中显示为 `-标签`。
- 媒体库中心顶部新增当前筛选 chips、结果数 / 总数、清空筛选和“保存筛选”入口；Smart List 持久化留到后续阶段。
- 媒体库首页使用 `LayoutSize` / `LayoutBreakpoints` 接入首轮响应式结构：expanded 常驻侧栏，medium 可折叠，compact 使用 BottomSheet。
- 顶部搜索入口文案扩展为文件名 / 路径 / 标签 / 别名，继续复用现有 TagQueryService 搜索能力。
- 保留常用标签、旧一级标签兼容区和二级标签展示，避免一次性删除旧 UI 能力。
- 验收补漏：旧一级/二级兼容筛选与新分组 tag 筛选会清理等价状态，避免同一条件重复叠加。
- 验收补漏：当前筛选条在窄宽度下自动换成上下两行，降低 compact / medium 小窗口溢出风险。
- 新增 `tag_groups`、`tags`、`tag_aliases`、`video_tags` 规范化 Tag 索引表，为分组 Tag、别名、来源和 locked 字段预留数据库基础。
- 扫描目录时同步 `folder` 来源一级/二级 Tag 到 `video_tags`，保留现有文件夹树生成行为。
- 手动编辑标签时同步 `manual` 来源 Tag 到 `video_tags`，为后续 folder/manual/rule/filename/import/auto 来源拆分打基础。
- 新增 `TagQueryContext` 与 `TagQueryService`，支持按 tagId/tagName/alias 匹配、组合筛选和标签结果计数。
- 标签结果计数改为忽略候选标签所在组，避免同组 OR 候选在当前筛选下计数塌缩。
- 旧库加载时会为缺失 `video_tags` 链接的视频回填 folder 来源索引，不会清空已有 manual 链接。
- 手动编辑标签时只刷新当前 manual 编辑范围，并排除路径派生 folder 标签，避免污染 folder 来源。
- SQLite 补充 tag alias 与 video tag source 查询索引。
- 搜索在文件名、路径、文件夹、一级/二级标签之外，新增匹配当前视频关联标签别名。
- 筛选结果进入播放器时作为当前播放队列传入，不再在二级筛选场景自动扩展为整个一级标签队列。
- SQLite 视频表补充根目录、相对路径、文件大小、修改时间字段。
- 旧数据库打开时自动补齐新增列，无需清空媒体库。
- 新增根目录、标题、收藏、修改时间、加入时间索引。
- 打开数据库时启用 WAL、外键、内存临时表和本地缓存配置。
- 目录扫描改为增量写入：新增、删除、标签变化、文件指纹变化时才更新对应视频记录。
- 收藏、播放时间、媒体信息、标签编辑改为单条写库，不再每次重写全部视频。
- 扫描已有视频时按当前目录结构刷新二级标签，避免旧二级标签残留。
- 媒体库路径比较改为 Windows 大小写不敏感稳定 key，避免同一路径因大小写或尾部分隔符差异重复入库。
- 添加根目录时规范化路径并去重，加载旧 metadata 时同步清理重复根目录和常用标签。
- 扫描时对不可访问根目录、不可读取文件、单个文件 stat 失败做容错跳过，避免整次扫描中断。
- 主界面扫描流程增加并发保护和失败恢复，扫描异常不会让按钮永久停留在扫描中。
- 搜索改为多关键词匹配标题、路径、文件夹、一级标签和二级标签。
- 收藏标签和标签编辑增加 trim 与大小写不敏感去重。

### 架构拆分

- 播放页拆出 `PlayerPlaybackController`，集中维护来源播放队列、当前二级标签、正在播放索引和选中索引；`PlayerPage` 继续负责播放器生命周期、mpv 打开和页面交互。
- 播放诊断弹窗迁移到 `player_diagnostics_dialog.dart`，保留持续采样、暂停停止采样和关闭释放 timer/subscription 的行为。
- `lib/main.dart` 按现有类边界拆分为 `src/models`、`src/services`、`src/pages`、`src/widgets`。
- 当前拆分采用 Dart part 机制，保持行为不变，先降低单文件维护成本。
- 明确下一阶段需要抽出平台与数据接口，再从 part 文件演进为真正独立模块。
- 新增 `src/core/TagRules` 和 `src/core/AppPaths`，先集中标签派生规则、视频扩展名判断和应用数据路径。
- PROJECT.md 新增代码注释规则，要求为规则、平台边界、异步流程添加简短必要注释。
- Architecture Baseline 0.4.3 完成：FFmpeg/FFprobe 路径、可用性、版本和调用通过 `FFmpegBackend` 兼容适配层收敛，诊断页补齐缓存失败操作入口。
### 任务规划

- 新增 ROADMAP.md：记录可采纳的跨平台计划、优先级总表、版本规则和新 Chat 读取规则。
- 新增 docs/chat_tasks/CHAT_1_ARCHITECTURE.md 到 CHAT_5_UI.md：为五个 Chat 提供职责边界、版本号、任务范围和可直接粘贴的新对话提示语。

### 构建验证

- `flutter analyze` 通过。
- `flutter build windows --debug` 通过。






