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

- 修复 expanded 顶部工具条未随窗口放大的问题：搜索框现在填满右侧动作按钮左侧的剩余宽度，红框区域会跟随主界面宽度扩展。
- 修复播放器返回主界面卡顿：播放时间更新不再触发全库标签计数、完整筛选刷新和缩略图预取；仅在当前视图依赖播放时间排序时做轻量重排。
- 使用 debug exe 真实窗口复测：最大化后顶部搜索工具条已拉伸到动作按钮前；从视频进入播放器约 980ms，点击 Back 返回主界面约 698ms。
- 主界面 expanded 布局从固定左右栏宽度改为按窗口总宽度比例计算：左侧导航、中央结果区、右侧标签筛选在窗口放大/缩小时同步变化，并在较窄 expanded 宽度下优先保护中央结果区。
- 新增主界面布局比例纯函数测试，覆盖 1280 / 1600 / 1920 宽度下左右栏与中心区的占比和总宽度守恒。
- 使用 debug exe 真实窗口验证普通窗口和最大化窗口：左侧导航、中央视频结果区、右侧标签筛选面板均按比例扩展，未发现横向 overflow 或面板遮挡。
- 新增 Git 远程提交规则：验证通过并完成本地提交后，必须 `git push` 到当前分支远程跟踪分支；远程/认证/网络失败时记录原因并保留本地提交。
- 顶部搜索框从 `SearchBar` 改为稳定 `TextField` 输入链路，保留原搜索图标、`Ctrl + K` 提示、controller 和 `onChanged` 筛选触发方式。
- 新增顶部搜索框 widget smoke test，直接输入 `lupa` 并断言 `TextEditingController` 与 `onSearchChanged` 同步更新。
- 真实窗口复测：Computer Use 的 `type_text` / `set_value` 仍受 Flutter Windows UIA 限制，但逐键输入可触发搜索筛选；后续仍需人工确认物理键盘中文/英文输入体验。
- 完成主界面第一轮真实窗口 smoke test：覆盖媒体库、最近播放、智能收藏、标签中心、设置、排序菜单、右侧标签面板收起/恢复和播放入口。
- 修复右侧标签筛选面板收起后恢复入口缺少按钮语义：收起窄条新增“展开标签筛选”语义、Tooltip 和稳定 smoke key，真实窗口复测可恢复面板。
- 新增收起窄条 widget smoke test，覆盖 key、Tooltip 和点击回调；本轮 `dart format`、`flutter test`、`flutter analyze`、`flutter build windows --debug` 均通过。
- 播放入口复测通过：从主界面底部“播放”进入播放器，右侧筛选结果队列显示 `1 / 11078`，返回主界面正常。
- 全仓库自有文档和代码注释执行中文化审查：Dart 注释英文句子已改为中文，`ROADMAP.md`、`docs/chat_tasks`、`.agents/skills`、安装说明和 FFmpeg 工具说明中的英文/乱码正文已改为中文；保留类名、字段名、路径、命令、schema/migration 等固定技术术语。
- 新增中文优先规则：除代码、第三方 API、协议、命令、路径、固定术语和外部错误信息外，文档、代码注释、任务记录和 Git 提交信息都默认使用中文。
- 清理右侧标签面板周边残留乱码注释：`_SmartFilterContextCard` 和 `TagDiscoverySmokeHarness` 的维护说明已改为中文，避免 smoke test 与面板交互语义被历史编码问题干扰。
- 本轮验证通过：`dart format lib/src/widgets/library_widgets.dart`、`flutter analyze`、`flutter build windows --debug`。
- 修复右侧热门二级标签“更多标签”不可点击：按钮现在可展开/收起热门二级标签列表，并显示当前可见数量/总数。
- 右侧“全部二级标签”页签不再复用热门区 12 个限制，改为展示完整二级标签列表；热门区只保留默认精简列表。
- 热门二级标签名发生冲突时自动显示所属一级标签，例如 `NTR 原神`、`NTR 崩铁`、`ntr mod`；无冲突标签继续保持轻量显示。
- 检查并复测媒体库/本地媒体库入口语义：媒体库点击后清空筛选并显示全部视频；本地媒体库点击后进入对应路径浏览，例如 `X:\test-media` 或其子路径，不作为标签筛选入口。
- 本轮验证通过：`dart format`、`flutter test`（18 项）、`flutter analyze`、`flutter build windows --debug`；computer-use 复测了更多标签、全部二级标签、媒体库重置和本地媒体库路径浏览。
- 修复非最大化窗口下的可视区域溢出：顶部工具条在实际行宽不足时让搜索框弹性收缩，单列视频卡片提高高度以容纳 16:9 缩略图和底部按钮，列表行动作区在中等宽度下切换为图标模式。
- 使用 computer-use 复测 debug exe：普通窗口和最大化窗口下，顶部工具条、列表行“播放 / 收藏 / 更多”、右侧标签筛选面板、本地媒体库返回入口均在可视范围内；普通窗口不再出现 Flutter overflow 条纹。
- 本轮验证通过：`dart format`、`flutter test`（16 项）、`flutter analyze`、`flutter build windows --debug`。
- 稳定 smoke harness 继续扩展：列表行“播放 / 收藏 / 更多”现在有稳定 key 和回调计数断言，覆盖真实列表行按钮入口。
- 本地媒体库文件夹返回新增列表模式 smoke：`dense=true` 下文件夹行进入子目录后，顶部返回按钮能回到 root。
- 右侧标签筛选新增结果状态 smoke：点击默认专辑 chip 后显示当前一级下全部示例结果；点击 Child01 chip 后结果收敛到 Child01，默认专辑和 Child02 结果消失。
- 列表行播放按钮改为固定尺寸自定义 `GestureDetector` 按钮，视觉保持紫色播放入口，命中路径更直接；测试等待覆盖外层列表行双击判定窗口，避免单击与双击识别冲突。
- 本轮验证通过：`dart format`、`flutter test`（16 项）、`flutter analyze`、`flutter build windows --debug`。
- 本轮把高风险点击 smoke test 从截图坐标校准改为稳定 key/harness 路径：新增 `LibrarySmokeKeys`、`LocalLibrarySmokeHarness`、`TagDiscoverySmokeHarness`，直接复用真实本地媒体库视图和右侧标签筛选组件进行 widget 点击。
- 新 smoke test 已覆盖本地媒体库文件夹进入、顶部返回按钮、鼠标后退侧键、右侧一级标签展开/收起、二级“展开全部/收起”和一级/全部二级 tab 切换；断言路径文本、面板状态和二级标签内容，不再依赖截图坐标。
- `AppPaths` 增加仅测试进程内的数据目录覆盖入口，保留 `LOCAL_TAG_PLAYER_DATA_DIR` 作为 debug exe 临时 profile 能力；默认真实数据目录不变。
- 本轮验证通过：`dart format`、`flutter test`、`flutter analyze`、`flutter build windows --debug`；debug exe 使用临时 profile 启动 3 秒保持运行并可被安全关闭。
- 新增 `LOCAL_TAG_PLAYER_DATA_DIR` 临时 profile 覆盖能力：默认数据目录不变；设置该环境变量时应用只读写指定目录，用于临时测试库和可回滚 QA。
- 使用临时 profile 完成最近播放真实鼠标复测：单条删除后仅 `Smoke Video 1` 的 `last_played_at` 清空；全选 + 删除已选后剩余播放记录清空；重置 2 条记录后点击“清空全部”也全部清空，未播放/收藏测试视频不受影响。
- 临时 profile 下补测三大入口切换耗时：媒体库首次点击约 213ms，最近播放约 63ms，智能收藏约 59ms，再回媒体库约 51ms；进程均保持响应。
- 右侧热门二级标签显示格式调整：热门区只显示二级标签名，不再附带所属一级标签灰色小标签；“全部二级标签”仍可保留所属一级提示。
- 右侧一级展开卡默认专辑去重：展开卡只保留第一个虚拟“默认专辑”chip，真实二级标签列表中的默认专辑会被过滤，避免出现两个默认专辑。
- 本地媒体库文件夹浏览增加返回能力：从文件夹项进入子目录时记录返回栈，顶部返回按钮和鼠标后退侧键都能回到上一层。
- 最近播放清理补充可测试目标选择逻辑：单选删除只命中已选播放记录，全选/清空只命中有 `lastPlayedAt` 的视频，未播放视频不会被误清理。
- 主界面三大来源入口轻量化：媒体库、最近播放、智能收藏切换不再走重型标签刷新路径；媒体库入口会即时清空筛选并重建全量结果，最近播放/智能收藏直接从内存视频集合生成可见列表。
- 最近播放改为主结果区可管理视图：支持单选、全选、删除已选和清空全部播放记录；删除只清理 `lastPlayedAt`，不删除视频、标签、收藏或播放进度。
- “我的标签库”改名为“本地媒体库”：侧栏只管理本地库路径，`+` 继续复用目录选择，单项 X 只移除 root 配置，不删除磁盘文件或已索引视频。
- 本地媒体库路径浏览新增文件夹/视频混合展示：文件夹按文件夹项进入下一层，已入库视频复用现有视频卡片/列表行，网格/列表切换继续生效。
- 设置入口从顶部工具条移除，只保留在左侧功能栏底部；已用 debug exe 验证小窗口下按实际窗口高度点击可进入设置页。
- 最近播放入口改为主结果区视图：点击左侧“最近播放”不再弹窗，而是在媒体库网格/列表区域直接展示最近播放视频，并保持播放队列来自当前可见结果。
- 左侧“媒体库”入口改为重置入口：点击后清空搜索、一级/二级/分组/排除/收藏筛选，并回到全部视频视图。
- 设置入口补齐到顶部工具条和左侧侧栏，点击后进入已有 `CacheSettingsPage`，继续承载播放解码和缩略图缓存统计。
- “我的标签库”新增标签弹窗改为可搜索过滤：输入时即时过滤已有标签，仍可输入新标签创建 manual tag；添加失败会显示 SnackBar 错误，不再静默失败。
- 从最近播放进入播放器时，队列标题改为“最近播放”，避免播放器右侧队列仍显示普通全库筛选摘要。
- 主界面侧栏做功能取舍：左侧删除重复的“播放历史”、低价值的“当前筛选”和“常用标签”，保留并修复“最近播放”入口，点击后打开最近播放弹窗。
- “目录管理”增加非破坏性移除目录能力：只从根目录配置移除，不删除磁盘文件，也不立即清理已索引视频记录，后续 missing/relink 阶段再处理视频状态。
- “我的标签库”改为可维护快捷列表：支持 `+` 添加已有标签或创建 manual 标签，支持单项移除；标签过多时使用固定高度滚动列表，移除快捷项不会删除真实标签或视频关联。
- 右侧标签计数改为使用全库稳定计数缓存，点击一级/二级筛选后其它标签的数量不再因为当前结果集收窄而消失。
- 顶部工具条修复搜索框占位过宽问题，标签中心、收藏筛选、排序和网格/列表切换在真实高宽桌面窗口下保持可见。
- 列表视图二次修复：列表行限制可读宽度并放宽行高，播放/收藏/更多按钮在宽屏列表态可见且不再出现横向或纵向 overflow。
- 本轮验证通过：`dart format`、`flutter analyze`、`flutter test`、`flutter build windows --debug`；debug exe 真实窗口确认最近播放弹窗、目录管理删除入口、顶部工具条可见、列表模式可见且无 overflow。Win32 坐标自动化仍未稳定触发列表行“更多”弹窗，需后续用人工鼠标或更稳定桌面自动化继续复测该命中路径。
- 列表视图专项修复：结果视图的 `dense/list` 模式从“缩小卡片网格”改为真正的纵向密集列表行，列表行使用左侧缩略图、中部标题/路径/标签、右侧播放/收藏/更多操作。
- 修复上一轮源码乱码清理造成的结构破损，补回右侧标签发现面板、列表切换 helper、缓存设置页、播放器横向滚动条和缩略图缓存统计类，恢复完整编译基线。
- 清理 `LibraryPage` / `library_widgets` 触达区域的剩余源码乱码注释和用户可见乱码字符串，当前触达文件乱码扫描已清零。
- 验证通过：`dart format`、`flutter analyze`、`flutter build windows --debug`、`flutter test`；现有 widget test 已覆盖列表按钮点击并断言切换到 dense list 模式。
- 主界面功能点击 smoke test 完成：排序菜单、收藏筛选、网格/列表切换、右侧标签面板收纳/恢复、一级/二级标签筛选、标签中心、播放历史、目录管理、卡片更多/编辑标签、播放入口均有可见响应。
- 补齐左侧“播放历史”和“目录管理”入口：播放历史只读展示最近播放视频并可从条目进入播放；目录管理只展示根目录并提供添加目录/重新扫描入口，不新增删除根目录等高风险操作。
- 当前筛选条新增搜索关键字 chip：搜索会参与 `FilterQuery`，现在会在“当前筛选（AND）”区域可见，并可通过 chip 的 X 单独清除，避免“看似无筛选但结果仍被关键字过滤”。
- 已用 debug exe 复测搜索输入、搜索 chip 清除、播放入口队列传递：搜索 `kafka` 后结果收敛并出现搜索 chip，点击 X 恢复 11,078 条；从主界面播放进入播放器后队列显示 `1 / 11078`。
- 右侧一级标签列表补充折叠/展开：默认只显示 7 个一级标签，“更多一级标签”可展开全部，再点可收起回默认 7 个。
- 右侧一级标签列表新增本地排序控件：支持“按数量 / 按名称”，排序只影响右侧展示，不改变筛选条件；按数量改为使用当前显示数量排序，避免按钮语义和列表顺序不一致。
- 去除“点击哪个一级标签就被置顶”的间接效果：一级列表排序不再依赖点击后变化的选中状态，默认按数量或名称稳定排列。
- 修复默认专辑和其它一级下二级标签定位不准：`FilterQuery.childTagId` 会从右侧选中的 folder.child tagId 反解为二级标签名；二级标签 fallback 匹配会把 parentId 反解为一级标签名再匹配 `VideoItem.childTags`。
- 右侧标签筛选面板滚动区域增加独立 Scrollbar 与右侧 8px 内容留白，截图确认滚动条不再压住一级标签行文字和数量。
- 右侧“标签筛选”交互继续修复：一级折叠行点击会互斥选择该一级标签的“默认专辑”并展开当前一级；切换到其它一级会清空旧一级和旧二级选择。
- 所有一级展开卡片都补入“默认专辑”虚拟二级 chip；该 chip 不写入数据库，只通过当前一级标签过滤展示该一级下全部视频。
- 右侧二级标签选择改为当前一级下互斥选择：点击新二级会替换旧二级，重复点击已选二级会回到当前一级的“默认专辑”状态。
- 一级展开标题行改为 40px 高的整行命中区域；“展开全部”继续作为当前一级本地展开开关，已支持再次点击收起。
- 已用 debug exe 做右侧面板点击 smoke test：真实点击二级 chip 后，当前筛选显示“崩铁 + 克拉拉/停云”，结果数收敛到对应二级，视频卡片路径与当前标签一致；OS 坐标自动化受当前 Windows DPI 缩放影响，一级标题折叠与“展开全部”仍建议人工按真实鼠标补测一次。
- 右侧“标签筛选”面板继续按蓝图微调：一级展开卡片默认只展示 9 个二级 chip，底部“展开全部（总数）⌄”改为可点击的轻量文本按钮，点击后只展开当前一级标签的完整二级标签集合。
- 继续补强“展开全部”命中区域：按钮从文字宽度扩大为展开卡片底部整行 32px 高命中区，降低横向点偏误触下方一级行的概率。
- “更多一级标签”按钮已弱化为一级列表底部的浅紫整行文本按钮，高度压到 30px，减少对热门二级标签区的视觉抢占。
- 右侧面板底部热门二级标签按蓝图微调垂直节奏：默认一级列表收回到 5 个让热门区进入首屏下半段，热门 chip 固定 3 列，标题字号略收，底部“更多标签⌄”按钮居中并固定为轻量 32px 高。
- 清理右侧标签筛选面板及相关候选区组件内残留乱码注释/tooltip 说明；源码注释恢复为可读中文，运行时 tooltip 继续保持中文。
- 已用 debug exe 进行右侧面板 smoke test：应用启动正常，右侧面板可见，标签页切换和一级折叠行点击有可见响应；热门二级标签区已在参考宽度截图中进入视口并呈 3 列布局；“展开全部”按钮已做整行命中补强，但坐标自动化在当前桌面/DPI 环境下仍未稳定截到展开状态，仍建议人工复测一次该按钮。
- 按蓝图重构右侧“标签筛选”面板视觉：面板宽度/外边距/圆角/轻边框/轻阴影调整为白色轻量卡片，顶部位于搜索工具栏下方，不再贴顶。
- 删除右侧面板内“一级标签 40”标题行、绿色竖条和重色 section 样式；一级标签区直接进入蓝图式展开卡片和折叠行。
- 重做右侧二级 chip：普通 chip 不再显示 tag 图标，选中态使用浅紫背景和 check，热门二级标签标题固定为“热门二级标签（可直接选择）”，底部使用轻量“更多标签⌄”按钮。
- 媒体库右侧标签筛选继续修复蓝图差异：一级标签从固定少量展示改为默认 8 个并可展开更多，点击折叠一级行会展开该一级自己的二级标签，不再固定只展示第一个一级标签的二级标签。
- 右侧一级展开行新增独立“筛选此一级标签”按钮，避免“展开一级”和“加入筛选”抢同一个点击区域；二级标签 chip 增大命中区域并恢复稳定中文 tooltip。
- 当前筛选条的“清空全部”按钮从横向 chips 滚动区移出，固定在滚动区外侧，减少被横向滚动视图吞点击的风险。
- 媒体库主界面继续按参考图红框做像素级比例微调：右侧标签筛选改为带外边距的独立卡片，展开分组减少嵌套卡片感，顶部搜索框增加最大宽度约束，避免超宽窗口被拉成横幅。
- 已用 debug exe 进行交互点击测试：收藏筛选、排序菜单、网格/列表切换、右侧“一级标签 / 全部二级标签”切换、右侧标签 chip 点击和筛选 chip 关闭均有可见响应；“清空全部”按钮在当前窗口坐标自动化中未稳定触发，后续需单独复查其命中区域或禁用态。
- 媒体库 expanded 主界面继续按参考图红框校正布局层级：顶部工具条横跨中间结果区和右侧标签筛选区，第二行才拆分为中间当前筛选条/视频网格与右侧标签筛选面板。
- 已用 debug exe 对比参考图确认：顶部工具条、当前筛选条、右侧标签筛选面板的纵向起点与区域归属已对齐；收藏筛选、排序菜单点击可用。
- 媒体库主界面顶部按参考图选中区域对齐：第一行改为搜索框、标签中心、收藏筛选、排序和网格/列表切换；第二行改为“当前筛选（AND）+ chips + 清空全部 + 结果数”的白色筛选条，并让 chips 横向滚动避免挤压结果数。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列；Smart List 草案入口继续保留为后续阶段未启用代码。
- Media Library Tag Interaction Performance + UI Response 专项完成：定位到媒体库标签点击卡顿的主要来源是 `LibraryPage.build()` 同步触发筛选与候选数量统计，旧 `resultCounts` 在上万视频场景下接近“候选标签数 * 视频数”的扫描成本。
- `TagQueryService.resultCounts` 改为按标签组分批统计；每组只扫描一次视频集合，并优先使用 `videoTagIdsByPathKey` 与候选 tagId 求交集，保持同组 OR 计数语义和 FilterQuery 入口不变。
- `LibraryPage` 将当前视频结果和左侧候选数量缓存到 State，筛选变化时 chips/选中态立即 setState，再用 `_filterRevision` 异步刷新视频结果和 resultCounts，旧请求完成后不会覆盖新筛选状态。
- 视频结果与候选数量分阶段更新：先刷新当前 filtered result 和 Grid，再刷新左侧 resultCounts；刷新期间顶部/筛选条显示小 spinner，侧栏分组标签区域显示细进度条并保留旧数量。
- 缩略图可见区域预取从 `build()` 后帧回调移到视频结果刷新完成后触发，避免 resultCounts-only 重建重复触发可见缩略图 Future。
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
- 右侧标签筛选面板一级排序去除独立标题，选项改为“数量 / 名称 / 常用”；“常用”仅按本次会话点击次数排序，不修改数据库。
- 右侧一级标签数量排序改为稳定数量基准，点击一级标签后不会因为当前筛选结果数变化而把该标签置顶或打乱其它标签顺序。
- 右侧“全部二级标签”改为从标签库展示二级标签，即使当前筛选下某些标签结果数为 0，也不会出现空面板。
- 右侧一级标签行点击改为只展开/收拢，筛选入口收敛到展开卡内的“默认专辑”和二级标签 chip，避免一次点击同时触发展开和结果刷新。
- 媒体库结果区取消按筛选 key 切换的网格动画，改为稳定 RepaintBoundary，降低标签切换时旧/新网格交叠造成的画面抖动。
- expanded 布局新增右侧标签筛选面板收纳窄条，可在不丢失当前筛选状态的情况下收起和恢复面板。
- 媒体库筛选结果和候选数量移出 `build()` 同步路径，改为页面级缓存 + revision 分阶段刷新；标签点击会先更新选中态，再刷新视频列表和候选数量。
- `TagQueryService.resultCounts` 恢复按标签组批量统计，每个候选组只扫描一次视频集合，并优先使用规范化 tagId 索引，避免候选标签数乘以视频数的重复扫描。
- 当前筛选条在刷新视频结果或候选数量时显示轻量 spinner，不遮挡视频网格滚动和点击。

## 当前已知问题 / 待观察

- 第一阶段拆分已完成，但仍是同一个 Dart library；下一阶段需要小步把低风险 core/model 文件迁移到普通 import，并逐步让实现依赖新接口。
- 本轮 `dart format`、`flutter analyze` 和 Windows debug 构建通过；历史上本机 formatter 偶发超时，后续如复现需单独确认。
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







