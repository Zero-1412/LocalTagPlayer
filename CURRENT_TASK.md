# CURRENT_TASK.md

## 当前状态

项目已能运行并构建 Windows debug 版本。

架构版本状态：`Architecture Baseline 0.5.29` 已完成。

最近一次验证：

```powershell
flutter analyze
flutter test
flutter build windows --debug
```

结果：通过；103 项测试通过，2 项显式基准跳过。

## 最近完成

- 查明全屏画面不一致来自源视频显示比例：对照样本第 3 项为 `1920×1080`（16:9），第 5 项为 `1728×1080`（16:10）且源内带上下黑边；默认 `contain` 会保留完整画面，因此后者在 16:9 全屏中出现左右留边，并非进度条顶动画面。
- 播放设置改为参考图式紧凑分组浮层，提供真实可用的播放方式、`自动 / 4:3 / 16:9 / 铺满`、倍速、快捷键和播放诊断；不展示未接通的解码策略或音量均衡占位。
- `PlayerBackend.buildVideoSurface` 增加可选 `BoxFit` / 显示宽高比；“铺满”同时使用 media_kit `cover` 与 mpv panscan 等比裁边，自动模式继续完整显示。设置浮层 focused tests、播放队列模式测试、`flutter analyze` 与 Windows debug build 通过，未运行全量测试。
- 真实窗口确认 1728×1080 自动模式留边、比例按钮选中反馈及设置入口；验证中先后发现并修正复杂菜单不显示、浮层过宽和仅 mpv 裁边仍保留外层留边。最终构建重启后自动化进程意外退出，截图器返回 `no screenshot targets found`，400px 浮层和最终 `cover` 仍需按记录路径人工复测。

- 播放器队列搜索默认收起，在 `当前序号 / 总数` 后新增搜索图标；点击后才在标题行下方挂载搜索框，再次点击可恢复紧凑头部。
- 搜索、定位已选中与删除三个入口统一为固定尺寸并保留明确间距；展开搜索后自动聚焦，原有当前 filtered queue 内定位逻辑不变。
- 新增展开/提交/收起 focused test，并复跑队列搜索语义测试；`flutter analyze`、Windows debug build 通过，未执行全量测试。真实启动 debug 程序完成默认、展开、收起三态点击截图，未见遮挡、溢出或对齐问题。

- 精简播放器筛选队列头部：删除固定“当前筛选（AND）”、重复总数徽标和不可操作的“全部视频 / 时长 / 大小”展示条，将当前序号提升到标题行。
- 头部现只保留队列名称、`当前序号 / 总数`、定位已选中、删除和下一行搜索；真实二级标签筛选、filtered queue 与返回播放行为不变。
- 队列布局与搜索 2 条 focused tests、`flutter analyze`、Windows debug build 通过，未运行全量测试；真实启动最新 debug 程序进入播放器截图，头部无遮挡、溢出或对齐问题，首屏多显示约一条视频卡片。

- 移除播放器队列顶部与“回到播放”语义重复的“定位当前播放”准星入口；顶部只保留“定位已选中”和删除，底部离屏提示继续提供“回到播放 / 回到选中”。
- 保留的回调与方法统一改名为“回到播放”，避免后续维护再次把顶部定位与底部返回误认为两个独立功能；filtered queue、播放/选择索引及搜索定位未改变。
- 影响范围侧栏 focused test、`flutter analyze`、Windows debug build 通过；真实窗口确认顶部入口移除，并滚动后点击“回到播放”正确返回第 1 项，未运行全量测试。

- 播放器右侧“列表 / 详情”改为蓝图要求的连续分段控件：两侧等宽且无间隙，选中半区使用明亮紫色渐变、高亮描边和外侧圆角，未选中半区保持深色低强调。
- 图标与文字同步放大并居中，列表/详情切换继续只替换侧栏内容，不修改 filtered queue、当前播放项或缓存行为。
- 仅执行本次影响范围的侧栏 focused test，另完成 `flutter analyze`、Windows debug build 及真实窗口列表/详情点击截图；两种选中态均无遮挡、溢出或状态错位。

- 修复播放器队列滚动到下方后点击“定位当前播放”可能残留轻量占位卡片的问题：快速滚动期间仍延后缩略图/媒体信息工作，滚动结束后显式恢复完整可视项。
- Windows 滚轮与程序化跳转可能缺少稳定的结束通知，队列可视层增加 120 ms 停稳防抖兜底；计时器随 widget 释放，不改变队列、选择或播放状态。
- focused 66 项、完整 103 项测试、`flutter analyze` 与 Windows debug build 通过；真实窗口滚动到第 29–31 项后确认缩略图、序号、标题和编码信息完整恢复。定位点击已触发，但随后截图仍被已知 Windows Flutter 无障碍桥异常阻断。

- 播放器底部当前视频信息卡已移除，播放画面直接使用释放出的垂直空间；原文件名、标签、媒体参数、路径与操作统一迁入右侧“详情”。
- 右侧侧栏新增同级“列表 / 详情”切换：列表继续消费当前 filtered queue，详情始终展示实际正在播放的视频，并复用编辑标签、打开位置、收藏和完整视频信息入口。
- 详情只读取当前 `VideoItem` 已缓存的数据，不在切换时重新访问文件系统或启动媒体探测；隐藏的列表页不挂载，避免不可见队列继续触发列表构建和缩略图工作。
- widget focused 65 项、完整 102 项测试、`flutter analyze` 与 Windows debug build 通过；真实窗口已点击验证列表/详情切换、详情滚动和底部清空，未见遮挡、溢出或状态错位。

- 播放器继续消费 `LibraryPage` 传入的当前筛选结果会话快照，不重新查询媒体库；快照保留同一批 `VideoItem`，因此已持久化的媒体详情和缩略图缓存可直接复用。
- 媒体库与播放器队列都按实际构建的可视/近可视条目提升缩略图和媒体详情优先级；播放期间继续冻结后台缩略图，只允许一个可视优先任务，避免与视频解码争抢。
- 播放器队列恢复“单击选中、双击播放”；定位当前播放会同步选中态，定位当前/已选中使用居中即时跳转并对首帧未挂载的滚动控制器有限重试。
- 真实窗口完成“原神 → 雷神”173 条筛选、播放器首屏详情/缩略图、单击选中和双击第 2 条播放验证；Windows 桌面自动化在整体队列定位后的无障碍树刷新中触发 `flutter_windows.dll` 异常，定位落点由纯函数/控制器测试覆盖，仍需无自动化辅助的人工点击复核。

- `LibraryPage` 不再接收完整 `LocalTagPlayerDependencies`，改为只接收页面应用服务、文件系统边界及转交播放器所需的两个 backend factory；AppPaths、FFmpeg、Repository loader 与 debug 配置保持在组合根创建的 `LocalLibraryPageApplicationService` 内。
- 已生成 macOS/Linux Flutter runner，补齐各平台 media_kit 运行库与 macOS 本地文件访问配置；GitHub Actions 分别执行 adapter contract、静态分析、debug build 与启动存活 smoke。
- 跨平台 contract test 会验证组合根在对应宿主选择 `MacOsFileSystemAdapter` / `LinuxFileSystemAdapter`；SQLite 测试在 Windows 使用仓库 DLL，在 macOS/Linux 使用系统 SQLite，Dart 单写边界不变。
- Windows 真实窗口回归通过：当前 debug 构建首屏加载 11165 项，展开“原神”并选择“雷神”后显示 173 项；chips、计数、网格与层级面板无重叠、溢出或状态错位。
- GitHub Actions run `29324080724` 的 macOS/Linux job 均通过：两个宿主都完成 adapter/架构 contract、`flutter analyze`、debug build 与 10 秒启动存活 smoke。

- 57 个 Dart `part` 已全部迁移为独立 import，Store 私有 persistence/coordinator、播放器/缩略图实现、应用服务、页面与 widgets 均形成真实 library 边界。
- 新增 `LocalTagPlayerDependencies` 组合根 contract、`LibraryStoreAccess` 私有协作端口与共享集合规则；页面继续依赖 `LibraryApplicationFacade` 和平台接口。
- 架构 contract test 新增零 `part` 守卫；96 项完整测试、`flutter analyze` 与 Windows debug build 已通过。
- 真实窗口回归通过：一级标签“原神”展开后二级标签“雷神”得到 172 条结果；本地 root 显示 477 项，进入“丽莎”显示 9 项并可返回，截图未见遮挡、溢出或状态错位。

- `AppPaths` 已改为组合根注入的实例，`SqfliteDatabaseProvider` 独占 database factory 与数据库路径选择；SQLite schema、stable identity 和写入仍由 Dart `LibraryStore` 单写。
- `LibraryApplicationFacade` 集合改为只读视图，收藏、root 替换与播放位置改走明确命令；Tag/Cache/Playback repository 已由同一个 Store 实现并注入。
- 已移除静态媒体工具、窗口单例与旧文件位置 service；debug 环境解析和诊断写入已退出页面。
- `part` 已从 57 个清零；后续不允许通过重新导入单一大 library 恢复隐式私有符号共享。
- contract/fake tests、analyze、Windows debug build 和真实窗口“原神 / 雷神”172 条筛选通过。macOS/Linux 已有显式 adapter；原生 build 需对应宿主验证。

- `DesktopFileSystemAdapter` 已接管目录选择、异步目录浏览、文件存在/stat、截图写入、删除和文件管理器定位；媒体库本地路径浏览不再在 Widget build 中同步遍历磁盘。
- `LibraryStore` 已实现真实 `LibraryRepository` contract，`LibraryApplicationFacade` 成为媒体库、标签管理和 missing/relink 页面的上层依赖；页面不再出现 `LibraryStore` 具体类型。
- `bootstrapLocalTagPlayer()` 成为 composition root，统一选择 Desktop 文件系统、Rust/Dart 扫描、C++/兼容媒体探测、MediaKit/实验原生播放器与 FFmpeg backend。
- `FileSystemAdapter`、领域模型、Repository/平台实现、应用服务和页面均已脱离 `part`；SQLite、标签筛选与 stable identity 写入继续留在 Dart。
- 88 项 focused tests、`flutter analyze`、Windows debug build 通过；真实窗口点击 root“原神”、子目录“丽莎”和标签“雷神”，分别正确加载 477 个直接子项、9 个目录视频和 172 条过滤结果，截图未见遮挡、溢出或状态错位。

- Windows CMake 固定依赖改为临时文件下载、SHA256 校验后原子落盘并有限重试；mpv/ANGLE 的已校验归档直接复用给 media_kit 插件，Android Studio 重建不再解压网络中断留下的半成品。

- `pages`、`services`、`widgets` 已按 library/player/tags/media/relink/window 职责形成独立 Dart library；`app.dart` 仅保留组合根、应用壳与兼容 export。

- 压力测试产物统一写入带安全标记的 `artifacts` 子目录；每次运行前自动清理超过 7 天的已标记目录，成功后只保留汇总报告与压缩清单，失败时保留完整诊断现场。
- 媒体库增删与真实播放器 runner 支持 `-KeepRawArtifacts` 和可配置保留天数，避免隔离 profile、缩略图、临时数据库、录像及原始采样再次把仓库扩张到数十 GiB。

- debug 压测为媒体库卡片增加 `card_shell`、`preview`、`metadata`、`tags`、`actions` 五个子树边界；直接 builder P95 均低于 0.1 ms，而包含式 layout 的主要热点落在卡片外壳与操作按钮链，不能把后代 Widget build 或重叠子树耗时错误相加。
- 播放器真实 `released` 后连续采样 60 秒：Private 643.5→591.7 MiB、线程 128→125、GPU committed 144.7→104.6 MiB；Flutter ImageCache 全程固定 19,611,648 bytes，未调用 GC 或清理 ImageCache。剩余约 52 MiB Private 高位应继续在 PlayerBackend/libmpv/驱动边界归因。
- 三轮真实快速滚动、六次播放与 18 次 seek 通过，卡片无遮挡或溢出；首次添加扫描 106.34 秒为冷存储异常值，卡片探针同期仅记录亚毫秒直接 build，不能据此归因为卡片构建。

- 媒体库后台缩略图新增 24 个候选校验并发上限；最多 500 条候选不再同时启动 cache key/JPEG 文件 I/O，可见卡片仍进入优先队列并在三轮真实快速滚动停稳后显示 8–9 张缩略图。
- 三轮真实库剖析确认滚动主要瓶颈是 Dart build/layout：新增库 build P95 中位 86.69 ms、raster 3.39 ms，移除后为 51.87/1.86 ms；缩略图抢占已生效，但不能把构建长帧误报为 GPU 光栅问题。
- 播放器退出改为 stop 完成后再 dispose；`MediaKitPlayerBackend.released` 在 Windows 上覆盖 media_kit 1.2.6 内置的 5 秒 `mpv_terminate_destroy` 延迟，压测等待真实销毁后才创建下一会话。
- 点击详情未知的视频时执行单项高优先级媒体预检，播放器页面及队列仍只读缓存。真实 7680×4320 H.264 样本两次在纹理创建前被阻止，不再允许自动放行软件解码。
- 三轮共 6 个实际播放会话全部使用 `d3d11va-copy`，音视频停滞与无响应均为 0，seek P95 28 ms；Private/GPU committed 峰值降至约 1,157/712 MiB，但多轮返回媒体库后的原生/驱动高位仍未完全消除。

- 移除媒体 root 改为单 SQLite 事务删除 root 配置、仅属于该 root 的视频行及标签关系；磁盘文件不动，重叠 root 仍覆盖的记录保留，媒体库总量在事务完成后立即差量刷新。
- 视频卡片“更多”新增删除入口，可选择仅移出媒体库或同步删除本地文件；数据库关联、收藏、播放进度、媒体详情与缩略图缓存一并清理。
- 快速滚动产生的新可见缩略图请求提升到遗留队列之前；删除中的活动生成任务会被作废，不能把旧 JPEG 写回。
- 播放器持续区分 `hwdec-current` 不可读与明确软件解码；打开前以 `hwdec-codecs=all` 允许高分辨率编码尝试 D3D11VA，连续三次确认 `no` 后只记录真实回退，不在播放中热切换后端。诊断会显示具体编码与分辨率。
- 真实 11,135 条窗口验证：卡片删除弹窗无遮挡，快速滚动停止约 0.9 秒后当前可见缩略图均已显示。8K H.264 7680×4320@60 样本被 RTX 4070 SUPER/mpv 明确回退为 `no`，总掉帧 4,240、AV offset 约 2.4 秒；运行时 `auto-copy` A/B 会直接触发 `media_kit_error`，因此已撤回，不把该硬件边界伪装成修复。
- 79 项 store/widget tests、`flutter analyze` 与 Windows debug build 通过；测试实例已正常关闭，未执行真实删除或 root 移除。

- 缩略图可见卡片改为等待共享的受限队列生成 Future，同一 cache key 只生成一次；后台预取连同 cache key/JPEG 验证阶段一起限制在 500 个请求内。
- 媒体库卡片移除 build 期间同步文件 stat，并对历史 4K fallback JPEG 使用 384px 解码尺寸；真实窗口像素截图中可见缩略图均已显示。
- 扫描 UI 诊断按大量差量/零差量连续采样 3 秒：11,133 条差量的 folder 侧边栏重算约 102 ms、filter 替换约 73 ms；零差量不再触发两者。全流程更大峰值仍在 11,000 条 Application 合并/SQLite 提交。

- 真实 11,135 条媒体库启动分解为 SQLite 打开/维护、视频 SQL、对象构建、标签与关系 hydration、folder 覆盖检查、首屏排序和标签计数；定位 38.55 秒来自启动时无条件 stable identity 回填的 Windows NOCASE 相关全表扫描。
- 增加 NOCASE path 索引并只迁移缺失身份/重复关系；root 直属视频合法零 folder 标签不再反复补写。隔离副本加载从 43.99 秒降至 0.844 秒，真实窗口首帧诊断为 1.42 秒。
- 建立 `LibraryScanBackend` / 不可变 `LibraryScanDelta` / generation 取消 / `LibraryScanCommitResult`，Dart Application 继续独占 stable identity、relink 唯一性与 SQLite 单 batch 提交。
- Windows Rust 只读扫描 sidecar 已随构建供应并保留 Dart fallback；父子 root 最上层优先去重。11,133 条稳定态 Rust 端到端扫描 240 毫秒且零差量。
- 首帧不等待目录统计或媒体探测；扫描后缩略图与 `MediaProbeBackend` 只处理新增/内容变化项，并在下一代扫描前取消旧 generation。
- focused store/scan/widget tests、Rust test/release build、`flutter analyze`、Windows debug build通过；真实窗口完成首屏、一级展开、二级标签 172 条切换、两轮 Rust 扫描与截图检查。

- 五轮真实媒体进出播放器完成分阶段内存采样：Player构造、纹理就绪、media open、pause/stop、dispose、返回媒体库0/500/2000 ms均记录RSS、Flutter ImageCache、纹理ID和mpv demux状态；Windows同步记录GPU Dedicated/Shared/Committed。
- Flutter ImageCache稳定在约93–100 MiB；mpv demux约96 MiB并在stop后清零，RSS同步下降约132–156 MiB；两者均不是退出后数百MiB高位保留主因。
- D3D共享纹理在dispose后纹理ID变为-1，并在约2秒内从20–79 MiB回落到5–6 MiB，确认VideoController注册到Player release的释放契约生效。
- NVIDIA Dedicated/Committed返回媒体库2秒后仍约531–624 MiB，但第三轮峰值约931 MiB后可回落且非单调增长；结合线程/句柄回落，当前归因为驱动D3D缓存/复用池，而不是活动Player、共享纹理或单调泄漏。

- 完成 180 秒、30 fps、AMF 硬件编码的无 UIA 压测录屏及逐帧分析。录屏实际得到 4597 帧，捕获链路存在 803 个均匀单帧缺口，但没有超过 66.7 ms 的录屏断档。
- 逐帧差分发现播放器画面以约 12 秒为周期阶梯更新；根因是集成测试误把 `pumpAndSettle(Duration)` 的位置参数当成超时，实际把单次 pump 步长设成 12 秒，测试绑定主动制造了长时间只提交一帧。
- 压测所有长等待已改为每 50 ms 连续 pump；媒体库启动改为持续驱动帧直到真实播放按钮出现，不再依赖固定等待猜测大库初始化完成。
- 修正后两轮 `open_player → queue_scroll_start` 均约 12 秒，不再是约 48 秒；退出后约 0.18 秒进入 dispose，视频帧号与音频 PTS 持续推进且停滞事件为 0。

- 完成 PlayerBackend 长驻实例可行性评估：连续两轮退出的原生 dispose 仅约 2–20 ms，且下一轮线程不累积；长驻 libmpv/D3D11 实例只会让约 150 个原生/驱动线程在媒体库页面继续驻留，不能降低播放峰值，因此本轮明确不采用全局 Player 单例。
- Windows 推荐硬解由枚举候选后端的 `auto-copy` 收敛为已验证的 `d3d11va-copy`；真实媒体峰值线程从 283 小幅降至 279，Private 峰值约从 1023 MiB 降至 993 MiB，两轮视频帧与音频 PTS 均持续推进。

- 播放器单实例资源对照确认：播放阶段约从 131 线程增加到 281–283 线程；固定 `vd-lavc-threads=4` 后线程峰值未下降，增量主要属于 media_kit/libmpv 初始化 D3D11/NVIDIA 视频输出后的原生及驱动线程，不能归因于队列 rebuild 或 FFprobe。
- 播放缓存组合预算由 128 MiB Player buffer + 256/128 MiB mpv 前后缓存收敛为 64 MiB + 96/32 MiB；真实媒体库对照中工作集峰值约从 1016 MiB 降至 789 MiB，Private 峰值约从 1300 MiB 降至 1023 MiB。
- 播放器后台每秒分别采样 mpv `estimated-frame-number` 与 `audio-pts`，独立识别视频冻结、音频停顿和两路同时停顿；退出链路记录请求、pause 确认、pop、dispose 开始/结束时间。
- 两轮真实媒体随机循环均使用 `d3d11va-copy`，视频帧与音频 PTS 持续推进、停滞事件为 0；pause 确认约 0–2 ms，原生 dispose 约 1–19 ms。56 项 focused tests、`flutter analyze`、Windows debug build 和真实窗口截图通过。

- 播放器大队列快速滚动期间改用轻量占位，停止创建会触发缩略图磁盘校验与 FFprobe 的完整队列项；列表预建范围收窄到相邻约两项。
- 播放开始后的详情预取只保留当前视频，避免前后队列探测与 4K 解码争抢磁盘；播放器输入缓冲提升到 128 MiB，并为 mpv 增加受限 30 秒预读与缓存耗尽暂停策略。
- 本轮 54 项 focused widget tests、`flutter analyze`、Windows debug build 通过；隔离 Windows 播放器用例首次通过，但截图被并存默认窗口污染，关闭默认窗口后复跑出现测试宿主 `did not complete`，不作为 UI 通过证据。仍需隔离真实 4K 三小时样本完成滚动与长播 soak。

- 全屏播放列表从覆盖层改为与视频同级的 Row 右栏：展开时视频宽度同步减少 440px，隐藏后恢复占满全屏。
- 普通队列与全屏队列使用独立 `ScrollController`，共享 filtered queue 和当前索引但不再发生布局切换期双挂载。
- 设置卡新增“恢复默认”，只恢复热区 12px 与隐藏延迟 180ms；测试确认解码、继续观看和快捷键保持不变。
- 长视频自动验证按钮展开、隐藏恢复、边缘唤出及视频宽度变化，并完成两张同级布局截图。

- 设置页新增“全屏播放列表”卡片，可调整右侧边缘热区宽度（4–40px）和离开后的自动隐藏延迟（0–1000ms）。
- 默认值保持 12px / 180ms；旧设置文件缺字段自动补默认，手工异常值会约束到安全范围。
- 滑杆拖动只更新预览，松开后才写入现有播放设置文件；隔离 profile 修改后重新进入播放器，按钮展开、自动隐藏和边缘唤出均通过。

- 全屏播放列表取消模态悬浮窗，改为播放器根布局右侧抽屉；点击播放列表按钮或悬停屏幕右侧 12px 热区均可滑入。
- 鼠标离开 440px 队列范围后延迟 180ms 自动隐藏；隐藏时卸载列表，避免普通侧栏切换全屏时短暂共用 `ScrollController`。
- 600 秒长视频自动验证“按钮展开 → 离开隐藏 → 右边缘再次唤出”，两种展开状态均完成 DPI-aware 窗口截图。

- 播放器路由前预热当前项附近缩略图，并让队列首帧同步复用进程内已验证缓存；消除先显示异常占位底色再加载列表数据的闪烁。
- 大文件首次 `open` 完成并确认可播放 600ms 后才启动相邻队列详情与缩略图预取，避免 FFprobe/磁盘任务与解码启动争抢资源。
- 音量区域支持鼠标滚轮按 5% 调整；控制层空闲后从半透明改为完全隐藏；全屏播放列表改用根 Overlay 右侧面板，确保位于视频纹理之上。
- 600 秒隔离长视频完成首帧、队列折叠/恢复、音量滚轮、控制层隐藏、全屏队列五段真实点击与窗口截图验证。

- 使用 Flutter VM Service 驱动真实 Windows 窗口，并通过桌面像素采集补拍队列折叠与恢复；该链路不创建 Windows UIA 客户端，两次状态切换均未触发进程退出。
- 修复队列首次挂载/恢复动画期间 `ScrollPosition` 尚无 viewport 尺寸时的空值竞态；新增可重复的播放器队列桌面集成测试与截图脚本。
- 隔离验证 Flutter stable 3.44.4 与 beta 3.46.0-0.3.pre 均通过无 UIA 用例；beta 的问题 UIA 客户端验证未能枚举测试窗口，缺少 bridge 已修复证据，因此暂不升级生产 SDK。

- 使用 600 秒长视频隔离样本复测，确认设置菜单在 `topEnd` 对齐后从齿轮下方向下展开。
- 短视频并非退出原因：长视频下同样可由 Windows UI 自动化触发 Flutter `accessibility_bridge.cc` AXTree 连续失败，最终进入 `ax_platform_node_win.cc` unreachable code。
- 日志未发现 Dart、media_kit、mpv、FFmpeg 或 filtered queue 错误；不通过关闭语义树规避，以免破坏屏幕阅读器能力。
- 队列折叠/恢复截图受辅助功能桥崩溃阻塞；本轮 71 项测试、analyze、Windows debug build 通过。

- 播放设置菜单固定从齿轮下方展开；队列折叠按钮改为播放队列图标。
- 宽屏队列折叠后顶栏不再显示重复播放队列入口，窄屏底部队列入口保持不变。
- `AGENTS.md` 已要求所有业务代码修改自动启动并点击测试，UI 改动必须触发后截图分析。
- 本轮 71 项测试、`flutter analyze`、Windows debug build 通过；隔离播放器触发浮层后进程退出，截图验证仍需在稳定长视频环境复点。

- 当前帧截图恢复为独立控制按钮；播放速度和播放模式改为齿轮菜单二级列表，一级菜单保持简洁。
- “更多”菜单改为按钮下方展开；筛选队列折叠改为保活压缩，恢复时沿用原列表、缩略图和滚动状态。
- 全屏时 Escape 优先退出全屏且不返回媒体库，设置页以固定安全快捷键显示 `Esc / 退出全屏`。
- 本轮 71 项测试、`flutter analyze`、`flutter build windows --debug` 和 `git diff --check` 通过。

- 播放器控制栏将倍速、播放模式、快捷键、截图和诊断收纳到齿轮；全屏后新增侧栏折叠按钮。
- 全屏改为桌面窗口全屏并隐藏非视频区域，真实窗口截图确认视频铺满显示器；全屏 resize 不写入普通窗口恢复快照。
- 信息卡“更多”移除播放模式和诊断，筛选结果队列头部移除诊断，避免同一功能出现多处入口。
- 本轮 71 项测试、`flutter analyze`、`flutter build windows --debug` 和 `git diff --check` 通过。

- 标签编辑器、视频信息和播放诊断弹窗内部统一为同一套图标标题、分组卡片、字段行和主次按钮层级；全局弹窗外框与菜单主题保持不变。
- 标签编辑器保留 folder 来源锁定与 manual 标签编辑边界；视频信息只重排已有字段；诊断定时采样、隐私摘要和关闭清理逻辑未改变。
- 隔离真实窗口完成标签输入/Enter 添加/Escape 取消、视频信息打开、诊断打开与复制反馈截图，长路径与详细指标均位于可滚动区域。
- 本轮 71 项测试、`flutter analyze`、`flutter build windows --debug` 和 `git diff --check` 均通过。

- 新增跨平台桌面窗口状态服务，应用会恢复上次窗口大小与最大化状态；窗口尺寸独立持久化，不影响播放设置或媒体库数据。
- 播放器快捷键提示从页面移除并迁入设置页，可修改十项功能绑定、自动交换冲突按键并恢复默认；旧设置向后兼容。
- 全局 Dialog、PopupMenu、Menu、BottomSheet、SnackBar 统一圆角、边框和表面颜色；播放器更多菜单使用高对比暗色主题。
- 隔离真实窗口已截图确认设置页、快捷键下拉与交换、播放器无提示栏和更多菜单清晰度。

- 播放器信息卡按蓝图重构为两层：标题补扩展名与编辑入口，路径和媒体摘要分组展示，标签 chips 与添加标签恢复到独立标签行，收藏迁入“更多”。
- 快捷键栏对齐 Space、J/L、T、F、S，并连接播放、快退快进、编辑标签、全屏和截图；隔离真实窗口确认红框布局无溢出。

- 按用户红框截图精确重排播放控制层：拉开前后项、播放、音量与时间间距，延长音量轨道，时间固定三段格式；右侧补齐快捷键、截图和播放模式真实入口。
- 当前帧截图复用 media_kit，并在用户确认保存位置后写入 JPEG；播放模式继续只消费当前 filtered queue，中窄窗口使用底部队列避免控制栏拥挤。

- 使用隔离 profile 和三条真实视频完成播放器截图对比：进度/音量改为蓝紫细轨，控制顺序按蓝图重排，信息卡压缩并提高标题/路径层级，快捷键栏铺满左侧区域。
- 筛选队列新增只读“全部视频 / 时长：全部 / 大小：全部”状态 chips，搜索框改暗色，播放项采用蓝紫边框并放大缩略图与元信息；真实窗口确认主要布局无溢出。
- 明确保留 Windows 原生标题栏，并继续排除蓝图中的“打开文件”、字幕和画中画占位，避免绕过筛选闭环或误导用户。

- 播放器右侧筛选队列按窗口宽度保持约 30% 占比并限制在 360–500px；队列顶边与视频画面统一对齐，补充响应式宽度测试。

- 播放器页面按产品蓝图继续对齐：新增品牌顶栏和当前队列搜索，明确不增加右上角“打开文件”，避免绕过媒体库筛选闭环。
- 视频身份卡补齐路径、时长、文件大小、封装、编解码和分辨率摘要，保留收藏、编辑标签、打开文件位置与更多操作；右侧队列增加总数徽标和蓝紫色卡片容器。
- 新增仅展示已实现能力的快捷键提示栏；`Ctrl+K` 可聚焦顶部当前队列搜索，搜索仍只遍历既有 filtered queue。
- 本轮 `flutter test`（68 项）、`flutter analyze`、Windows debug build 均通过；真实 debug 窗口持续停留在大型媒体库初始化加载层，尚需隔离小媒体 profile 补点播放器布局与控件。
- 播放器控制层重排：画面底部统一进度、播放/暂停、上一条、下一条、时间、倍速、音量与全屏；播放中空闲三秒淡化，鼠标进入或移动立即恢复。
- 删除视频信息卡中的大尺寸前后项描边按钮；标题单行省略并提供完整 tooltip，队列序号保持醒目。
- 标签改为紧凑特色按钮；打开文件位置、视频信息、播放诊断和播放模式移入“更多”菜单。
- 筛选摘要统一简化为“原神 / 雷神 · 172 项”形式；右侧队列顶部只保留一条短摘要和当前序号，避免重复信息。
- 继续观看迁入设置页成为“默认打开行为”：默认从上次位置继续，不再每次弹窗；仍可选择从头播放或每次询问，旧设置文件向后兼容。
- 播放解码收敛为推荐自动安全、性能优先自动零拷贝、兼容优先软件解码三档；具体 d3d11va/nvdec/cuda/vulkan 后端移入默认折叠的高级选项。
- 缩略图缓存明确展示总数、已缓存、缺失、失败、活动任务/并发上限、排队任务和平均耗时；刷新入口增加可见“刷新统计”标签。
- 隔离 profile 真实窗口确认三块设置卡片、默认恢复值、解码高级展开与缓存统计无布局溢出，测试配置未写入用户 profile。
- 修复搜索结果闭环：顶部立即显示实际标签、关键词和当前命中数，例如“原神 / 雷神 + 关键词 raiden · 41 个结果”；标签旁计数继续允许延后刷新。
- `Ctrl+K` 增加页面级真实键盘处理，页面容器持有焦点时也能稳定聚焦同一个 `TextField`；搜索文字使用真实按键输入后清晰可见。
- 播放器右侧改用媒体库同源筛选摘要并显示当前队列项数，不再因新 folder 分组标签未进入旧 `activeTags` 而错误显示“全部视频”。
- 播放器底部操作和播放模式菜单提升暗色主题对比度；“下一条”使用主色填充，可用与禁用状态保持可辨识。

- 使用独立 `LOCAL_TAG_PLAYER_DATA_DIR` 和两条真实 18 秒 H264/AAC 媒体完成第四阶段窗口 smoke：播放模式菜单、随机 EOF 切换、六档倍速、1.5x 状态、全屏队列序号与标签入口均可用。
- smoke 发现全屏标签弹窗的 Escape 会继续冒泡并误返回媒体库；播放器现已在标签编辑期间屏蔽底层 Escape，回归确认关闭弹窗/全屏后仍停留在原 filtered queue 播放页。

- 完成第四阶段轻量播放体验：可切换顺序、随机、单曲循环和列表循环；默认仍为顺序播放并在队尾停止，所有模式只消费当前 filtered queue。
- 新增 0.5x 至 2x 六档倍速，以及空格播放/暂停、J/L 前后 5 秒、`[`/`]` 调整倍速等少量高频快捷键。
- 全屏控制层新增当前序号、筛选队列标题和“编辑标签”入口；字幕、音轨等专业能力继续等待真实用户反馈。
- Windows debug exe 可启动，但默认资料库在 20 秒观察窗口内持续停留于启动加载层，未能进入媒体卡片执行模式、倍速与全屏点击；仍需使用隔离小媒体 profile 复点这三条路径。

- 批量路径预览新增本地搜索，可匹配标题、旧/新路径和状态，不访问 SQLite 或重新扫描文件系统。
- 新增可复制审计摘要，汇总预览分类、批事务成功/失败数量，并强制隐藏本地路径与文件标题。
- ready Relink 改为单个 SQLite batch 原子提交；执行前统一重验 missing、路径占用、目标文件和 fingerprint，事务异常回滚内存索引。
- 预览后失效或事务失败的 videoId 会保留在弹窗中，可恢复文件后定向重新预览并重试，不重复提交已成功项。
- 隔离真实窗口 smoke 已确认旧/新前缀、预览搜索、复制审计、生成预览和应用按钮在 1280×720 桌面布局中无溢出；无预览时复制与应用保持禁用。
- 完成 20 条隔离视频的真实 C:→E: 跨盘移动 soak：复制删除式移动、missing 标记、批量预览、Relink 和数据库重载后，videoId、manual 标签、收藏与播放进度全部保留。
- Missing 管理页新增批量路径前缀替换预览：按目标不存在、路径冲突、指纹不一致和可更新分类；应用前二次确认，不移动或删除磁盘文件。
- 新增按 videoId 合并的 `PlaybackSnapshotWriteQueue`：同一视频只保留最新待写快照，不同视频严格串行落库；离开播放器前 flush，写入失败提供稳定提示。
- 隔离真实窗口 smoke 已确认 missing 列表、批量替换入口、旧/新前缀字段、只读预览区和禁用的零项应用状态。
- Stable Video Identity 第三阶段完成：播放位置、总时长和完成态与稳定 videoId 同行保存；旧库幂等增加默认字段，不使用 mutable path 建立临时记录。
- 再次打开有效未完成视频时提供“从上次位置继续 / 从头播放”；恢复选择期间暂停写入，避免刚打开的 0 秒覆盖旧进度。
- “最近播放”升级为“继续观看”，只展示至少观看 3 秒且未进入动态完成阈值的条目，卡片/列表展示稳定进度条。
- 短视频完成阈值为 1-2 秒，长视频采用约 5% 且封顶 30 秒；完成或接近结尾的记录不反复恢复。
- filtered queue 中 missing 条目显示明确“缺失 / 路径失效”状态，不派发失效路径 I/O；打开后可直接 Relink，记录不会删除。
- 隔离 profile 真实 30 秒 H264/AAC smoke 已确认“继续观看”入口与进度条、`00:08 / 00:30` 恢复选择，以及继续后播放器从 8 秒位置起播。
- 播放器 manual 标签弹窗补齐桌面键盘链路：自动聚焦、Tab 遍历候选、Enter 添加、Ctrl+Enter 保存、Escape 取消。
- 新增 50,000 条 filtered queue 最坏命中性能基准，本机约 24ms；只遍历播放器已持有队列。
- 新增“缺失与重新关联”管理页；只有 fingerprint 一致时才更新 mutable path，并保留稳定 videoId、manual 标签、收藏与播放记录。
- 隔离 profile 真实窗口 smoke 已确认侧栏入口、0 条空状态和返回媒体库路径；匹配/拒绝 relink 由真实临时文件与 SQLite focused test 覆盖。
- 完成标签播放器差异化第二阶段：播放页“编辑标签”只维护 manual 来源，folder 标签以锁定路径来源展示；弹窗支持最近使用、收藏标签和即时搜索/新建。
- 播放页新增“打开文件位置”，Windows/macOS/Linux 命令收口到 `DesktopFileLocationService` 平台边界；缺失文件显示稳定提示。
- 右侧 filtered queue 新增轻量搜索定位，只遍历当前队列的标题、路径和标签，不访问或重新扫描全媒体库，也不替换来源队列。
- 播放器内收藏和打标只写当前视频及必要 `video_tags` 索引；返回媒体库时仅刷新可见结果，不触发全库标签计数重算。
- 使用隔离 profile 和两条真实 H264/AAC 媒体完成窗口 smoke：确认连续播放期间可打开编辑标签、folder 来源保持锁定、收藏/manual 候选可见并可保存，当前 filtered queue 保持 2 项不变。
- 完成 Stable Video Identity 第一阶段：`VideoItem` 新增稳定 `videoId`，`path` 改为可变位置，SQLite 启动时幂等回填旧记录与 `video_tags.video_id`，收藏、标签关系、最近播放和进度均随稳定条目保留。
- 媒体 fingerprint 升级为与路径和修改时间无关的“文件大小 + 首尾各 4KB 内容采样哈希”；扫描仅在新旧两侧 fingerprint 都唯一时自动 relink，冲突时保守新建，避免串档。
- 扫描不再删除路径失效记录：可访问 root 中未找到的文件标记为 `missing`；唯一 fingerprint 重新出现时更新 mutable path 并保留 manual 标签、收藏、播放记录和进度。
- 播放器每约 5 秒低频保存当前 videoId 的进度，切换/退出时补写；重新打开时恢复安全位置，距离结尾不足 5 秒则从头播放，EOF 后清零。
- 隔离 profile 的真实 debug exe 已完成旧库迁移启动和真实 H264/AAC 卡片加载；播放器点击复测受其它全屏置顶窗口持续抢占系统焦点阻塞，进度写入、重载、移动后保留与恢复边界已由 focused tests 替代覆盖，仍需在无置顶窗口环境复点“播放约 8 秒 → 返回 → 重开”。
- 使用独立 `LOCAL_TAG_PLAYER_DATA_DIR` 和隔离媒体目录完成真实坏文件 smoke：0-byte MP4 会进入稳定 `unplayable_media` 错误态，诊断可见错误类型，“跳过此项”可继续播放队列中的正常 H264/AAC 文件，不会阻塞剩余队列。
- 播放器上下文面板新增“编辑手动标签”入口；弹窗锁定 folder 来源标签，只允许增删 manual 标签，保存时优先按已关联 `tagId` 操作，并兼容同步旧视频标签字段。
- 隔离 profile 真实窗口验证播放器内新增 `smoke-manual` 后立即显示、队列不变，重启应用后标签仍持久化；播放进度记忆明确等待 Stable Video Identity 后实施。
- 完成播放器连续播放闭环：订阅 `media_kit` EOF，在当前 filtered queue 内顺序进入下一条，队尾停止且持续显示完成提示，不默认循环到队首。
- 播放器上下文面板新增显式上一条/下一条按钮；视频打开失败新增稳定恢复面板，可重试、跳过到下一条或打开诊断详情。
- 播放诊断入口移到播放器顶部，支持复制不含本地路径的诊断摘要，并在弹窗内部显示复制成功状态。
- 新增播放器 focused tests 覆盖顺序队列边界、队尾不循环、open 失败重试和成功清理；全量测试、analyze、Windows debug build 通过。
- 真实窗口验证 11,078 条队列中短视频 EOF 自动从第 1 条进入第 2 条；`mona-fis` 单条筛选队列在结束后停止并持续显示队尾提示，返回媒体库后筛选仍保留。

- 修复设置页硬件解码下拉的取消确认状态：解码切换控件抽为 `PlaybackDecoderDropdown`，取消弹窗会清理下拉框内部临时选中态，只有确认后才保存并显示新解码选项。
- 固化 Agent Harness 结构原则：主规则稳定、能力按需加载、长程任务持久化记录、验证结果决定是否晋级；后续较大功能或真实媒体目录 QA 不再把临时规则堆进 `AGENTS.md`，而按 `docs/agent_harness.md` 和对应任务文档记录。
- 为主界面压测补稳定语义标签：排序、本地媒体库、一级/二级标签和视频操作入口现在暴露 `qa.*` 辅助树标签，自动化不再优先依赖窗口坐标。
- 新增 `scripts/qa/main_window_stress_semantic.mjs` 语义优先压测脚本：随机点击一级标签、二级标签、排序字段、正倒序、本地媒体库路径和视频入口，并在应用退出、窗口丢失、连续找不到目标或重复命中同一目标时停止。
- 主界面压测脚本的残余失败已从笼统“目标暂时不可见”拆成 `ui_state_wait`、`list_visibility`、`tag_expansion` 三类，并返回 `failureDetails` 按阶段和原因聚合，方便沉淀为长期 smoke 门禁。
- 重新压测发现：旧脚本偶发“应用消失”更符合动态 UI 刷新后 `element_index` 过期导致的误点风险；加入双快照稳定校验和窗口 chrome 过滤后，5 分钟真实窗口压测执行 28 轮，未出现应用退出、异常停止或重复点击同一目标。
- 压测 stderr 中出现 Flutter Windows accessibility bridge `AXTree` 更新错误；当前判断为高频辅助树刷新噪音，进程仍 `Responding=True`，Windows Application 日志未记录 `local_tag_player` 崩溃。

- 标签计数刷新收口到 `LibraryCountRefreshCoordinator`：页面不再内联维护计数延时和 revision，高频标签/搜索交互会取消旧计数任务，低频库结构变化才安排空闲计数刷新。
- 新增 focused test 覆盖计数刷新协调器：旧任务被取消后不会执行 `resultCounts`，只保留最新空闲计数结果，防止标签点击再次退化为多次全量计数排队。
- 新增 `docs/qa/main_window_latency_smoke.md`：记录真实窗口标签点击、搜索和本地媒体库路径切换的耗时采样模板，后续复测可输出每轮 `elapsedMs` 与结果摘要。
- 升级真实窗口耗时采样模板：采样脚本优先从 Computer Use 辅助树解析标签文本和 `element_index`，普通窗口/最大化窗口坐标漂移时只把相对坐标作为二级 chip 的最后回退，并在结果中标记 `method`。
- debug exe 真实窗口耗时采样：普通窗口下连续 10 轮一级/二级点击，单轮约 874-1129ms；脚本固定等待约 700ms，未观察到窗口无响应或全页空白。普通窗口二级 chip 坐标仍可能命中一级区域，后续最大化窗口采样需重新校准 chip 坐标。
- 修复搜索框真实键盘输入链路：主页面持有独立 `FocusNode`，`Ctrl+K` 从页面和顶部栏两层都能请求搜索框焦点并选中现有文本，`TextEditingController` 监听继续作为唯一筛选入口。
- 优化标签/搜索切换流畅度：标签点击和搜索输入默认只刷新可见视频结果，不再同步触发全量标签计数刷新；需要计数刷新时走 revision 保护的延后任务，避免旧计数任务覆盖新筛选状态。
- 新增搜索 smoke 覆盖：widget 自动化覆盖 `Ctrl+K -> 输入 firefly -> onChanged -> 结果计数/列表更新`；debug exe 真实窗口复测 `Ctrl+K -> 逐键输入` 可触发搜索筛选，计数从 11078 收敛到 245，列表同步更新。
- 新增媒体库/标签交互复测记录：真实窗口随机选择不同一级标签并点击其下二级标签两次，连续执行 10 轮，未观察到全页空白或冻结；后续媒体库或标签改动仍需重复该路径。
- 修复标签点击/切换标签后媒体库加载卡顿：右侧标签组按库版本、root 签名和标签数量缓存，标签点击不再反复全库派生文件夹标签；筛选刷新不再立即触发额外“刷新中” rebuild，普通标签切换不再执行全标签计数，库/标签结构变化时才延后重统计。
- 修复本地媒体库路径跳转卡顿感：本地目录条目增加按路径、排序和库版本缓存，重复进入同一路径不再重新读取目录和排序；库数据变化时统一清理派生缓存。
- 新增规则：凡是媒体库或标签相关改动，必须验证点击标签、切换标签后的媒体库加载状况；可运行桌面端时补真实窗口点击/切换标签流畅度 QA。
- 修复 P1 标签中心重复/大小写混杂展示：Tag Manager 列表不再直接摊平 `tagsById`，展示层按来源、分组、父级和大小写归一标签名聚合；NTR/ntr 这类同边界变体合并为一行并聚合使用数，不同一级父级下的同名二级 folder 标签保留父级路径展示。
- 修复 P2 播放器队列单击语义：队列项单击现在直接切换播放，双击仍兼容；悬停提示同步改为“单击播放”，减少“已选中但未播放”的认知负担。
- 修复 P2 更多按钮语义：视频卡片/列表“更多”先展开明确菜单，目前提供“编辑标签”菜单项，不再点击后直接打开标签编辑弹窗；新增 smoke key 覆盖菜单出现。
- 修复 P2 设置页解码器误触风险：硬件解码下拉变更前增加确认弹窗，取消时保留原配置，避免坐标误触直接写入播放设置。
- 新增规则：标签中心必须大小写归一聚合展示；更多入口必须先展示菜单；高影响设置下拉必须提供确认或可撤销路径。
- 修复 P0 搜索输入可靠性：主搜索框继续使用 `TextField`，并由 `TextEditingController` 监听驱动筛选刷新；真实键盘、自动化输入和 controller 文本变化走同一条路径，页面内部清空搜索使用静默更新，避免进入本地媒体库/最近播放时被误切回全库。
- 优化 P1 切换卡顿路径：最近播放、本地收藏和本地媒体库路径浏览的排序结果增加轻量缓存，排序/播放时间/库数据/路径变化才重算；本地路径浏览不再每次构建全库 path map，减少列表 rebuild 时的 UI 线程开销。
- 修复右侧“全部二级标签”直接点击的层级语义：二级文件夹标签会先绑定所属一级标签，再以一级+二级组合参与筛选；当前筛选 chips 优先使用路径派生标签，避免历史 SQLite folder 标签污染展示。
- 新增项目规则：用户体验优先；标签筛选、排序方式、路径切换和搜索输入必须优先保护界面流畅度；二级标签必须始终归属在一级标签下面，不能越界与一级标签同层展示或脱离父级筛选。
- 新增 `docs/agent_harness.md`，把长程执行规则整理为 Agent Harness 迭代闭环；后续较大功能或真实媒体目录 QA 需要按该文档在 `CURRENT_TASK.md` 或对应 `docs/chat_tasks/CHAT_*.md` 记录 champion/challenger、baseline、patch、验证结果、真实媒体 smoke 和是否晋级。
- 新增 `test/library_store_test.dart` focused tests，使用临时 profile 和真实小型文件树覆盖目录扫描、folder 标签派生、manual 标签添加/移除、`save/load` 持久化读写。
- `LibraryStore` 新增 `close()` 释放 SQLite 句柄，测试和未来 repository 拆分可安全清理临时数据库目录。
- 新增 `services/library_scan_service.dart`，把文件系统扫描、folder 标签派生和轻量媒体指纹从 `LibraryStore.scan()` 中拆出；`LibraryStore` 继续负责 SQLite 写入、标签索引同步和用户维护数据。
- `player_page.dart` 继续拆分：底部播放上下文面板迁到 `pages/player_context_panel.dart`，右侧筛选结果队列迁到 `pages/player_queue_sidebar.dart`，队列可见性 helper 保持测试覆盖。
- 继续拆分主界面 UI 大文件：本地媒体库视图迁到 `widgets/library_local_view.dart`，右侧标签筛选面板迁到 `widgets/library_tag_discovery_panel.dart`，视频网格/列表行/卡片迁到 `widgets/library_video_results.dart`。
- `library_page.dart` 的筛选摘要、播放队列标题、排序比较和排序状态切换迁到 `pages/library_page_helpers.dart`，页面主体继续只协调视图和用户交互入口。
- 评估 `library_store.dart` 后确认它同时包含 SQLite 读写、目录扫描、标签索引同步、手动标签维护和统计查询；本轮不在测试覆盖不足时强拆，后续应先补持久化/扫描/标签维护边界测试。
- 完成第一轮低风险模块化拆分：`library_widgets.dart` 中的 smoke test key 迁到 `widgets/library_smoke_keys.dart`，顶部排序控件迁到 `widgets/library_sort_control.dart`。
- 结构分析确认当前最大耦合点仍是 `library_widgets.dart`、`player_page.dart`、`library_page.dart` 和 `library_store.dart`；本轮先拆纯 UI / 测试基础设施，避免触碰筛选、播放队列或 schema。
- 拆分后 `library_widgets.dart` 从约 5001 行降到约 4647 行；`flutter test`、`flutter analyze`、`flutter build windows --debug` 和 debug exe 排序下拉真实窗口 smoke 均通过。
- 排序字段弹层从浮动菜单改为贴合排序字段按钮底部的抽屉式下拉面板，展开时向下生长，避免与按钮视觉重叠。
- 排序 smoke test 改为验证下拉面板与字段按钮底部对齐且同宽；debug exe 真实窗口确认“添加时间 / 名称 / 目录”列表不再压住按钮。
- 修复“本地收藏”叠加右侧标签后收藏条件丢失的问题：左侧本地收藏入口现在同步设置 `favoriteOnly`，后续选择一级/二级标签会以 AND 关系保留收藏条件。
- 排序字段菜单增加下移偏移，避免弹层贴住或压住顶部排序按钮；widget smoke 新增菜单位置断言。
- debug exe 真实窗口复测：本地收藏播放队列标题保持 `本地收藏 | 1 / 11078`；叠加 `mod + ntr` 后 chips 同时显示“本地收藏 / mod / ntr”并收敛到 0 条；网格/列表下“添加时间 / 名称 / 目录”和正倒序控件未发现重叠或布局跳动。
- 顶部工具栏移除重复的“收藏筛选”入口，收藏来源只保留左侧“本地收藏”入口，避免同一收藏视图出现两个入口语义。
- 左侧“智能收藏”改名为“本地收藏”，当前筛选摘要、结果 chips 和播放器队列标题同步使用新名称。
- 排序控件改为与顶部工具栏一致的分段式外观，排序字段和“正序 / 倒序”独立切换；新增 widget smoke 断言覆盖重复收藏按钮移除和排序方向点击。
- 修复列表模式视频行操作按钮对齐：移除列表行内容 980px 宽度上限，播放、收藏、更多操作区固定到卡片右侧，按钮间距保持 8px，右侧留白约 8px。
- 新增宽屏列表行 smoke 断言，验证“更多”按钮右边缘贴近列表行右边缘；debug exe 真实窗口复测通过。
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
- `lib/main.dart` 已按现有类边界拆分为一级技术模块；文件较多的 `src/services`、`src/pages`、`src/widgets` 再按业务职责进入二级目录，当前采用 Dart part 机制保持无行为变化。
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

- 2026-07-08 本轮补充 `LibraryStore` focused tests，覆盖标签别名/隐藏/收藏/排序持久化、手动二级标签与 folder 二级标签分离、视频直接 upsert/delete 后的标签关联清理。
- 2026-07-08 `LibraryStore` 已拆出 `LibraryTagPersistence` 与 `LibraryVideoPersistence`，store 继续负责扫描、folder/manual 语义和内存状态协调；本轮未修改 SQLite schema、`FilterQuery` / `TagQueryService` 语义。
- 2026-07-08 播放页已拆出 `PlayerPlaybackController` 和 `player_diagnostics_dialog.dart`；播放器仍消费媒体库传入的当前过滤队列，未修改 `PlayerBackend`、mpv 打开流程或缩略图/media 队列。
- 2026-07-08 继续补充 metadata / scan / tag maintenance focused tests，并拆出 `LibraryMetadataPersistence`、`LibraryScanCoordinator`、`LibraryTagMaintenance`；播放器侧拆出 `PlayerOpenRequestController` 和 `player_delete_dialog.dart`。
- 2026-07-08 继续补充 `LibraryScanCoordinator` / `LibraryTagMaintenance` 异常路径测试：内容变化清理旧媒体缓存、缺失 root 不误删仍存在视频、非 manual 标签批量操作被拒绝。
- 2026-07-08 修复右侧标签层级展示：一级页签只展示 `folder.primary` 文件夹一级标签，二级标签只在“全部二级标签”页签展示，避免一级页签混入热门二级标签。
- 2026-07-08 继续加固右侧一级列表：展示候选会校验 `folder.primary` + `folder` 来源 + 无父级 + `folder.primary:*` id 形态，历史污染的二级/manual 标签不会混入一级列表；二级候选也校验 `folder.child` + 父级。
- 2026-07-08 右侧 folder 一级/二级候选改为从真实视频路径和本地媒体库 root 重新派生；多个 root 命中时优先用最上层 root，确保 `X:\test-media\崩坏三` 是一级、`X:\test-media\崩坏三\李素裳` 是二级。
- 2026-07-08 排序切换改为直接重排当前 `FilterState`，不再触发完整筛选刷新和标签计数重算；“添加时间”按 `addedAt` 排序，播放器返回更新 `lastPlayedAt` 不再导致主媒体库默认排序重排。
- 2026-07-08 媒体库排序偏好保存到独立 `library_sort.json`；全量媒体库、标签筛选、本地收藏和最近播放统一使用 `sortedLibraryVideos`，进入媒体库不再重置排序字段/方向。
- 2026-07-08 顶部排序字段对齐 Windows 文件排序：展示“名称 / 日期 / 类型 / 大小 / 目录 / 添加时间”；“日期”优先按文件修改时间排序并兼容旧 `recent` 偏好 key，名称使用自然排序。
- 2026-07-08 修复二级标签筛选路径层级不一致：`FilterQuery` 携带当前媒体库 roots，按最上层 root 重新派生一级/二级后匹配视频，避免子 root 历史扫描把二级当一级导致结果为 0。
- 2026-07-08 排序和标签筛选流畅度继续加固：排序预计算自然排序 token、扩展名、日期和路径 key；筛选后排序复用同一入口，标签计数延后到可见结果更新之后。
- 2026-07-08 本地媒体库路径浏览的视频项接入同一 `sortedLibraryVideos` 排序规则；文件夹继续固定在视频前面。
- 2026-07-08 播放器 controller tests 覆盖二级队列切换回退和 open 请求失败后继续保留最新打开请求；未修改播放器 filtered queue 来源或 `PlayerBackend`。
- 本轮验证：`flutter test`、`flutter analyze`、`flutter build windows --debug` 通过；debug exe 已启动到主界面。当前会话未暴露可调用的 Computer Use 控件工具，使用 Windows UIA/截图替代 smoke，UIA 只能看到 Flutter 根视图，交互路径由 widget smoke 覆盖。
- 第一阶段拆分已完成，但仍是同一个 Dart library；下一阶段需要小步把低风险 core/model 文件迁移到普通 import，并逐步让实现依赖新接口。
- 本轮 `dart format`、`flutter analyze` 和 Windows debug 构建通过；历史上本机 formatter 偶发超时，后续如复现需单独确认。
- 播放时仍可能有轻微卡顿感，需要继续结合持续诊断结果，从缩略图队列、mpv 参数、硬解模式三个方向排查。
- media_kit 对精确掉帧、AV offset 暴露有限，诊断页中部分指标来自 mpv property，仍需验证不同机器/显卡下是否可用。
- 缩略图缓存队列已降低后台资源占用并限制后台排队；后续仍需观察不同硬盘/显卡环境下 FFmpeg 超时、失败重试和播放时暂停效果。
- 当前 README 已重写为简洁入口，历史乱码内容已不再保留。

## 下一步建议任务

优先级从高到低：

1. 小步迁移平台与数据接口实现：让 `LibraryStore`、媒体工具和页面逐步依赖 `FileSystemAdapter`、`DatabaseProvider`、Repository 接口，迁移时必须保持 Windows 行为不变。
2. 继续针对大库交互做性能拆分：把标签计数刷新移到更明确的后台/空闲协调层，并记录排序/标签切换耗时。
3. 继续收敛 `LibraryStore` 剩余职责：tag usage summary 查询、schema/default groups 初始化、legacy JSON 导入可继续拆成更小 helper，但先补 focused tests。
4. 播放器侧下一步可拆视频信息弹窗和诊断采样 builder，继续缩小 `PlayerPage`。
5. 排查播放卡顿：结合新增后台并发统计，确认播放时缩略图队列暂停后是否仍有已启动任务造成 I/O 抖动。
6. 完善诊断能力：继续增加 FFmpeg/FFprobe 实际调用耗时、可复制诊断摘要和播放诊断入口联动。
7. 继续优化媒体库 schema：推进 `videoId + fingerprint + mutable path`，增加 `missing` 标记、单文件 relink 和批量路径替换。

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







# 2026-07-13 PlayerBackend 完整边界第一轮

- 扩展 `PlayerBackend`，覆盖播放命令、轻量状态、纹理通知、诊断属性、截图、视频表面和释放完成信号。
- 新增 `MediaKitPlayerBackend`，集中持有 Player、VideoController 与 libmpv 属性访问；`PlayerPage` 和诊断弹窗不再直接依赖 media_kit 实例。
- `PlayerPage` 支持注入 `PlayerBackendFactory`，默认仍使用 media_kit/libmpv，后续 Windows C++ 后端可在组合根做 A/B 切换。
- 74 项测试、`flutter analyze`、Windows debug build 通过；真实媒体库 90 秒回归完成 4 轮，硬解均为 `d3d11va-copy`，视频/音频停滞事件为 0，seek 为 26–27ms，退出后纹理 ID 均变为 `-1`。
# 2026-07-13 Windows C++播放器骨架

- Windows runner新增原生播放器方法通道、2×2假像素纹理、单工作线程命令队列与纹理释放协议。
- 新增`WindowsNativePlayerBackend`，仅当`LOCAL_TAG_PLAYER_BACKEND=windows-native-stub`时启用；默认media_kit路径不变。
- 假后端真实媒体库30秒回归完成2轮纹理、滚动、全屏、seek和退出，退出后纹理ID均变为`-1`；默认media_kit对照2轮保持`d3d11va-copy`、AV offset接近0且无音视频停滞。
- 同时段资源峰值为：假后端173线程、565.6MiB工作集、558.9MiB GPU committed；media_kit为315线程、830.3MiB工作集、781.8MiB GPU committed。假后端不执行解码，该数据只用于确认桥接开销，不能作为播放器性能结论。
- libmpv DLL虽存在于运行目录，但头文件、导入库和ANGLE当前只存在于生成目录；真实D3D11后端不得依赖这些本机临时路径，下一轮先固定可重复构建的第三方依赖供应。

# 2026-07-13 Windows 原生 libmpv/ANGLE 实链与同媒体 A/B

- CMake 固定并校验 libmpv、ANGLE 和 media_kit_video Windows C++ 源码，安装 DLL、许可证及第三方告知；不读取 Pub Cache 或机器相关临时链接路径。
- `NativePlayerBridge` 以单工作线程拥有一个 `mpv_handle`、一个 `mpv_render_context` 和一个 ANGLE/D3D11 共享纹理，更新回调只发出渲染请求，避免在 mpv 回调中重入渲染死锁。
- 原生快照补齐 EOF/错误计数、实际硬解、AV offset、音频 PTS、缓存时长、帧号、掉帧和帧率；Flutter 适配器恢复完整完成流和错误流。
- 开关 `LOCAL_TAG_PLAYER_BACKEND=windows-native-mpv` 仅用于显式 A/B，默认 MediaKit 不变；`windows-native-stub` 仍保留生命周期回归入口。
- 同 `Seed=20260713`、同真实媒体、同 20 秒随机循环下，两端均无视频/音频停滞且实际硬解均为 `d3d11va-copy`。原生 seek 7 ms、dispose 约 25 ms，对照 28 ms、约 8 ms；两端进程始终响应，短测线程峰值均为 315，原生 GPU committed 峰值更高，暂不切换默认后端。
- 74 项测试、原生桥接集成测试、analyze、Windows debug build、真实播放与截图均通过。

# 2026-07-13 4K 长视频分阶段 A/B 与原生优化

- 压测可通过环境变量匿名锁定同一真实媒体，并在 CSV 中记录启动、稳定播放、释放和媒体库空闲阶段；新增 `summarize_player_stress_metrics.ps1` 生成阶段中位数、P95、峰值与 seek/dispose 摘要。
- 同一 3840×2160/60fps、约 29 分钟真实视频在 MediaKit、原生基线、原生优化下分别运行 480 秒和 18 轮；三组实际硬解均为 `d3d11va-copy`，视频/音频停滞、无响应和崩溃均为 0。
- 原生渲染只在 `MPV_RENDER_UPDATE_FRAME` 时提交纹理，表面从 1280×720 起按 Flutter 请求量化并封顶 1920×1080；新增渲染请求、实际帧、跳过、纹理复制、表面重建与尺寸诊断。
- 原生缓存收敛到 12 秒预读、64 MiB 前向和 16 MiB 后向预算。相对原生基线，稳定期工作集/Private 中位数约下降 63/68 MiB，GPU committed P95 约下降 73 MiB，seek P95 从 118 ms 降至 27 ms。
- 优化原生稳定期中位数为 CPU 63.2%、279 线程、922.5 MiB 工作集、1492.4 MiB Private、1001.7 MiB GPU committed；MediaKit 为 75.4%、269、967.6、1296.6、812.5。原生仍有 Private/GPU/线程代价，默认继续使用 MediaKit。
- 下一步只保留一个有门槛的底层调查：确认额外 D3D11/ANGLE device context 和驱动 committed 来源；若无法把 Private/GPU P95 收敛到 MediaKit 的 110% 以内，则停止默认替换路线，仅保留实验后端。

# 2026-07-13 原生媒体探测与 11,000 条大库扫描决策

- D3D11/ANGLE 最终调查确认双 1080p BGRA 共享纹理仅约 15.8 MiB，不能解释原生相对 MediaKit 的约 196 MiB Private 差额；主要来源是额外 libmpv/FFmpeg 解码池、D3D11VA 表面和多设备驱动缓存。
- 原生稳定期 Private/GPU committed P95 分别约为 MediaKit 的 114.5%/113.8%，未进入 110% 门槛；停止默认播放器替换路线，不继续下沉 seek、状态机和诊断判定，实验开关保留。
- 新增 `MediaProbeBackend`、不可变请求/结果 DTO，以及 Windows C++ FFmpeg 8.1 `probeBatch/cancelGeneration`；原生库首次探测才加载，SQLite 仍只由 Dart Repository 写入。
- 真实 11,135 条索引库、6 个根目录、15,958 个文件基准：数据库加载约 40.2 秒、纯目录枚举 84ms、首次冷盘 stat+指纹 272.7 秒；复用 size/mtime/fingerprint 后热扫描 2.72 秒，事件循环 P95 16.95ms、最大 18.34ms。
- 扫描瓶颈属于未变化文件的随机磁盘读取而非 Dart 事件循环，已在现有 Dart 边界消除，因此不引入 Rust `LibraryScanBackend`。下一步应单独优化约 40 秒的 Repository/SQLite hydration。
- 76 项测试、原生媒体探测集成测试、`flutter analyze`、Windows debug build和隔离真实媒体两轮滚动/全屏/seek/诊断/退出通过。

# 2026-07-14 4K 硬解兼容矩阵与超规格提示

- RTX 4070 SUPER / 驱动 595.97 下，以 MediaKit `d3d11va-copy` 分别测试真实 3840×2160/60 H.264、HEVC、AV1，每种两轮随机队列滚动、seek、全屏和退出；六轮实际硬解均为 `d3d11va-copy`，音视频停滞为 0，AV offset 最大约 0.000445 秒。
- 新增不可变 `HardwareDecodeCompatibilityAssessment` 与只读 `PlayerHardwareCompatibility`；预检只消费数据库缓存详情，未知规格不猜测、不触发 FFprobe。
- 已确认回退软件解码的 7680×4320/60 H.264 在 `PlayerBackend` 创建前要求确认；首次入口取消不会创建播放器，队列切换取消会恢复已打开项，确认后才提交新 open。
- 弹窗提供 4K H.264 代理与 4K HEVC 转码建议及复制命令，要求保留源文件；不自动转码、不覆盖用户媒体。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 和缩略图/media 队列未修改。
- 87 项测试、`flutter analyze` 和 Windows debug build 通过；真实窗口截图确认 1268×714 下弹窗无遮挡/溢出，取消保持媒体库，继续可进入 8K 视频且返回后停止播放。
# 2026-07-14 媒体库增删与播放器十轮专项压测

- 新增 debug-only 媒体库压力控制边界和 Finder/VM Service 十轮驱动，以隔离 profile 对真实 `X:\test-media` 执行添加、滚动、播放、3 次 seek、移除和剩余库播放，全程录屏并采样 SQLite、队列、帧耗时、进程、I/O、GPU 与播放器诊断。
- 修复三项真实竞态：异步未入库统计遍历可变 roots、root 移除未失效过滤数据 revision、旧媒体探测回调在移除后重新 upsert 已删记录。
- 10 轮均保持 4,827 → 11,135 → 4,827 的 Store/UI 一致性；添加 P95 2.405 秒、移除 P95 0.773 秒，UI 追平均小于 1 ms。
- 快速滚动仍有明显长帧：添加后/移除后阶段 P95 中位数约 62/52 ms；20 个播放样本有 6 个 8K H.264 软件解码，进程 Private/GPU committed 峰值约 2,342/941 MiB。
- 完整证据和下一步见 `docs/qa/library_add_remove_player_stress_20260714.md`。
