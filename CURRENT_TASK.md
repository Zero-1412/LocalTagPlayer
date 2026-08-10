# CURRENT_TASK.md

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
- 发布阻塞：`v0.2.7` 的发布说明、架构门禁、IME 与键盘 focused tests、`flutter analyze`、
  Windows Debug/Release 构建均已通过；GitHub 全量测试仍被两个既有独立用例阻塞：
  `library_card_file_menu_test.dart` 的启动新增视频检查在 Windows runner 超时 10 分钟，以及
  `windows_native_hwnd_surface_test.dart` 的控制区高度断言期望 3、实际 12。未创建 tag、Release 或安装包资产，
  后续须先分别复现并修复/确认这两个门禁，不能直接放宽断言或跳过测试。

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
