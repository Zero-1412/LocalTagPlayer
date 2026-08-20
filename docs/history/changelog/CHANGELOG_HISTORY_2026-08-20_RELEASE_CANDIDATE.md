# CHANGELOG 历史快照（2026-08-20 发布候选）

根目录 CHANGELOG.md 的旧条目在收敛治理预算时完整迁移至此，内容未删除。

# CHANGELOG.md

本文件只保存未发布变更和版本索引。完整历史位于
`docs/history/changelog/`，不要把旧条目复制回根文件。

## Unreleased

### 播放器稳定性矩阵反向 seek trace

- 自动长按桌面像素探针改为 Down 后立即采样至 Up，按住期间出现首帧时 Up→首帧保持 null；正式 PlayerPage QA 走 scan-code 输入语义，并在同机 4K H.264/HEVC/AV1 各 3/3 复核 `81/98`、`186/201`、`83/99 ms` 的 Down→DWM p50/p95。该数字仅是自动化按住期间推进基线，不代表实体 QPC 或反向落点已达专业播放器水平。
- 反向 latest-only 预览新增按帧让渡与最短 Texture dwell，写出 `reverse_preview_frame_wait_start/complete` trace；仅抑制命令洪水，不宣称原生反向连续解码。
- 正式 MediaKit 通过可选边界接入原生逐帧、A-B loop 和外挂字幕：上下文菜单提供逐帧/A-B/字幕入口，逗号与句号提供逐帧快捷键；A/B 不持久化，字幕不写入媒体库或播放队列。当前只完成命令边界与 focused contract，尚未完成三编码实窗运行验收。
- 独立 precision controls Debug QA 已在真实 PlayerPage/MediaKit Texture 的 H.264、HEVC、AV1 会话中验证逐帧推进、A/B 设置与清除、外挂字幕加载和资源释放；逐帧证据仍是后端估算帧号代理，不冒充 DWM/QPC 首帧。
- Debug QA 新增强制软件解码与一次性自动恢复开关；真实 4K HEVC PlayerPage 已观察 `hwdec_current=no`、`software_decode_confirmed`，并由同一安全 open worker 将 `open_generation` 从 1 推进到 2。该开关不进入正式组合根，正式用户仍需明确点击降级条的“重新打开”。
- 强制软件解码安全恢复 Debug E2E 已补齐 H.264/HEVC/AV1；三种编码均确认实际 `hwdec_current=no`、一次性安全重开 `open_generation=1→2` 和资源释放。该证据仍只覆盖 QA 强制软件路径，不代表跨 GPU 的发布级回退矩阵。
- 稳定性矩阵同时识别当前 `native_rendered_frame` / `presented_frame_fallback` 首帧阶段与历史音频门禁阶段，不再把有效帧观察误统计为零。
- 从匿名 `PLAYER_SEEK_LATENCY` 输出提取 `reverseKeyframeTrace`，挂载到 `qaReverseKeyframeTrace`，保留 cache、decoder/VO、硬解、Texture 代次差和失败样本；不改变播放命令或默认渲染后端。
- 反向 trace 新增 `segmentTrace`，显式分出命令完成、命令后 cache/decoder/VO 快照、后端帧代理、Texture 代次和 DWM unavailable；integration 证据不再被误写成屏幕呈现。
- Debug-only seek trace 进一步在命令完成、首个后端帧和实际帧 timeout 三个节点写出同一组 cache/decoder/VO/Texture 快照，并以串行旁路读取避免诊断争用播放命令；生产路径不增加属性采样。
- 持久硬解降级条增加请求档位、实际 `hwdec-current` 和确认样本数，用户无需打开诊断弹窗即可判断当前是否已回退；重新打开仍沿用原有安全 open worker。
- 最新真实 1080p H.264 Debug smoke 已验证 7/7 `segmentTrace` 落盘（`d3d11va-copy`、反向命令 p95 `0 ms`、后端帧代理 p95 `15 ms`、Texture 代次差 `0`）；DWM 仍明确为 integration 不可观测，不生成桌面 p50/p95。
- 最新 Debug 4K AV1/144 DPI/900ms virtual-key 长按快退矩阵 7/7 `pixel_change_timeout`，门禁保持失败且不生成 p50/p95；5 个完整会话仍保留 Texture generation `0/1/3`、2 次重建、decoder/total drop `0`，`hwdec-current` 短暂回退 `no` 后恢复 `d3d11va-copy`，并在 `native_rendered_frame_timeout_runtime` 中保留 2016ms 等待证据。动作没有实体 QPC 输入窗口，不写入实体键盘结论。
- 同机真实 4K 长 GOP H.264/HEVC/AV1 Debug smoke 新增 `keyboardExperience.smoothScanTrace.summary` 聚合：三组首帧分别为 `314/284/292 ms`，seek p95 为 `241/199/259 ms`，扫描命令到音频恢复最长为 `133.417/153.990/127.842 ms`，停止 cache 最长为 `13.317/11.483/57.365 s`，Texture 代次均为 `2`、实际硬解均为 `d3d11va-copy`。证据仍是 `backend-runtime-snapshot-not-desktop-pixels`，只用于 cache/decoder/VO/恢复分段定位，不生成实体输入到 DWM 的 p50/p95。
- 新增 QA-only 的 mpv `play-direction=backward` 可行性实验：同一 Debug MediaKit 会话对 H.264/HEVC/AV1 各采样 20 次位置，均未观察到持续反向推进（最大反向距离 `-9/3/0 ms`），运行态临时方向为 `backward`，最终均恢复 `forward`；硬解均为 `d3d11va-copy`、Texture 代次均为 `2`。该实验不改变正式长按后退的 latest-only keyframe preview；反向播放的可行性仍受 mpv 官方“脆弱且通常更慢”限制。
- 稳定性矩阵报告新增 `qaReverseDirectionExperiment`，独立保留反向实验的方向、位置样本、cache/解码/VO/硬解和恢复结果；未启用时保留 `enabled=false/status=not-run`，不把缺少 QA 开关误报成产品失败。
- seek 协调器启用位置确认窗口时额外写出 `position_confirmation_start/complete|superseded|timeout`；该逻辑等待与桌面首帧分离，键盘预览的 `confirmationTimeout=0` 不产生这些阶段。
- 增强后的首帧观察和反向 trace 同步写回每个 backend 的 `reportPath`，独立审查单份报告时不会丢失分段证据。
- Debug 像素门禁的 `desktop-pixel-trace-correlation.json` 改为动作窗口关联：原生实体消息同时写入 QPC/UTC，按 Down 前 500ms 至首像素/松键后 1s 筛选 `PLAYER_SEEK_TRACE`，只有唯一动作窗口才匹配，重叠窗口标记 `ambiguous-overlapping-pixel-action-windows`，不再把窗口外或重叠窗口最近邻误归因；UTC 仍不参与 QPC→DWM 延迟或 p50/p95。
- `PLAYER_SEEK_TRACE` 现在优先写入 `wall_utc_us`，兼容旧 `wall_utc_ms` 并输出精度标记；新增保守的 `actionTraceSummaries`，仅在唯一动作窗口和唯一 trace id 时计算阶段到首像素的差值。修复 PowerShell 有序字典初始化/展开导致的关联 parse-failed，并用 standalone Debug PlayerPage 拖动 smoke 复核 `unique-trace` 输出；该自动化 Slider 样本仍不进入实体键盘 p50/p95。
- 修正桌面探针对原生 `qpcUs`/`utcUs` JSONL 的字段边界解析；`qpcUs` 不再被后续 `utcUs` 拼入整数，避免真实 WM_KEYDOWN 被误报为未收到 QPC。门禁在缺少桌面摘要时现在优先回传原始探针失败分类，不再以“缺少摘要”覆盖根因。
- 桌面 correlation 现在同时保留原生 QPC/UTC、PlayerPage `player_keyboard_event` 或 `progress_slider_*` 语义事件及唯一 `PLAYER_SEEK_TRACE`，并写出 `traceLinkEvidence`；缺失可选字段和单事件数组在 PowerShell StrictMode 下不会再触发 parse-failed。最新真实 PlayerPage Slider smoke 已验证 `playerInputEventCount=2` 与 `unique-trace` 落盘，仍不替代实体键盘/DWM 统计。
- correlation 语义筛选覆盖自动化 `win32-keyboard-*` 与实体 `manual-keyboard-*` 两类输入；自动化键盘若有页面回执会保留为估算 UTC 关联，但只有原生 QPC/UTC 侧车才能升级为实体输入证据。
- 修复桌面 correlation 在 StrictMode 下把无 trace 的空数组展开成 `$null` 后访问 `.Count` 的问题；自动化 PlayerPage 现在会保留页面键盘事件和 `ambiguous-multiple-traces-in-input-window`，不再生成 `trace-correlation-parse-failed`。同一 4K H.264 窄窗口自动化门禁在重置外部 UIA 观察器后通过，污染会话的 `flutter_windows.dll` 崩溃被单列为无效环境证据。
- 新增正式 PlayerPage 的 Debug-only `playerFullscreen` 桌面门禁：干净 4K H.264/144 DPI 单样本有效捕获 `115.5 fps`，Enter→窗口几何变化 `50 ms`；`renderer-events.jsonl` 证明全屏稳定后 Texture generation 未继续增加，但启动阶段仍发生 `1920×1080 → 3840×2160 → 1600×900` 尺寸重建。该证据仅用于全屏/Texture 结构审查，不改变正式渲染策略，也不进入 seek p50/p95。
- 同一 `playerFullscreen` 合同补齐 HEVC/AV1：HEVC `113.0 fps`、Enter→几何 `44 ms`，AV1 `115.7 fps`、`50 ms`，两者启动均为 `1920×1080 → 1600×900`、稳定后 generation `3`；与 H.264 的 `1920×1080 → 3840×2160 → 1600×900` 不同，保留为编码相关 Texture 生命周期证据，未提高正式 Texture 上限。
- QA-only 固定尺寸对照确认 HEVC/AV1 在关闭自适应时都会创建 `3840×2160` Texture（generation `2`；有效采样 `121.5/113.9 fps`），而正式自适应路径收敛到 `1600×900`、generation `3`。该结果用于评估合成压力，不把 4K 原生表面直接晋级为正式默认。
- 干净 Debug 会话补齐真实 PlayerPage 7 轮 virtual-key 对照：前进 Down→DWM p50/p95 `94/107 ms`、后退 `93/96 ms`，两组均 `7/7`、有效采样约 `112–117 fps`；证据固定为 `win32-keyboard-virtual-key`，只证明 Focus/页面输入链可达，不进入实体 WM_KEYDOWN/QPC p50/p95。
- 桌面像素 QA 新增显式 `HoldMilliseconds` 自动化长按对照，并在首个 virtual-key forward Down 后恢复隔离页面播放，避免暂停状态下 `setRate` 不推进时钟造成假性全程静帧。4K H.264/144 DPI/900ms 长按 7/7 的前进/后退 Down→DWM p95 为 `912/916 ms`，最长静帧 `9/7 ms`；证据固定为 `win32-keyboard-virtual-key-long-hold`，不改变正式 PlayerPage、实体键盘门禁或用户 seek 语义，且首帧约 900ms 仍不代表专业级体验。
- 同一自动化长按合同补齐 HEVC/AV1：HEVC 前进/后退 p95 `1029/916 ms`、最长静帧 `108/4 ms`；AV1 前进 p95 `1040 ms`、最长静帧 `1025 ms`，后退 7/7 全部 `pixel_change_timeout` 且 trace 明确进入 `new_video_frame_timeout`/`native_rendered_frame_timeout`。三编码硬解均为 `d3d11va-copy`；这些是 Debug virtual-key 证据，不是实体输入 p50/p95，也不改变正式 seek 语义。
- 独立桌面像素矩阵新增匿名 `runtimeEvidence` 聚合，保留最终硬解、首帧证据、Texture generation/重建事件/尺寸、resize 状态和 decoder/VO 掉帧最大值；空属性保持 `null`。三轮 4K H.264 PlayerPage 自动化前进以 `112.5–115.2 fps` 通过，Down→DWM p50/p95 `98/105 ms`，最终硬解 `d3d11va-copy`，Texture 重建事件 `2–3` 次；该结果仍不进入实体键盘 p50/p95。
- Debug PlayerPage 键盘 QA 回执现在记录固定枚举的 `action`/`phase`/`utcUs`，用于证明真实 KeyDown/KeyRepeat/KeyUp 是否进入 Flutter Focus 链；旧长按样本没有这些新字段或 `smooth_scan_*` 阶段，不能被回填成连续扫描分段结论。
- 实体键盘 Debug 门禁把前进/后退动作传入隔离 QA 页面，提示与 ready 握手分别显示 `L`/`J`，避免人工验收按错方向；正式页面不读取该环境变量。
- Debug-only 实体长按门禁新增 `manualLongForward/manualLongBackward`，以真实 Down/Up QPC 和最小时长校验长按合同，并在首个像素后保留短尾采样；不注入按键、不修改正式播放器语义。
- 修正实体键盘 QA 观察器只收到 ready 而收不到按键的消息路由缺口：Debug-only `FlutterWindow::MessageHandler` 现在在交给 Flutter 前旁路记录 J/L 的匿名 QPC，并对 runner subclass 的重复消息去重；合成冒烟仅证明输入证据链接通，不作为桌面性能样本。
- 同一真实 4K H.264 的 MediaKit Texture/QA-only child HWND 后端 trace 已分别落盘；两者均明确标为后端帧代理而非桌面像素，稳定性矩阵的精确位置失败也不会被其余样本补成有效 p95。
- 稳定性矩阵在集成测试提前失败时会写出匿名 `failed-no-report` backend 报告和固定失败分类，保留可审查的失败证据而不生成伪 p95。
- 稳定性矩阵修正短循环样本跨文件尾部回绕的队列判定；最终真实 H.264/HEVC/AV1 矩阵中 MediaKit Texture 全场景通过（18 次交互 seek 无失败，`d3d11va-copy`），QA-only child HWND 保留 `2/18` 精确 seek 未确认和 `15` 次首帧观察超时（`d3d11va`），双后端门禁继续保持 failed。
- 修正 QA trace 将 child HWND 的 `native-rendered-frames` 误标为 `native-rendered-texture` 的证据混淆；现在分别记录 `native-rendered-child-hwnd` 与正式 Texture 复制代理，避免把原生窗口计数当成 Flutter Texture 呈现。
- 将输出证据类型下沉到可选后端边界；未声明表面的兼容后端现在写 `native-rendered-output-unknown`，不再猜测 Texture/HWND。
- 实体键盘像素门禁补齐首批真实 PlayerPage 单样本：短按前/后 Down→DWM 首帧分别为 `159/10 ms`，长按前进按住 `2478 ms` 后首个稳定像素为 `2380 ms`；全部具备原生 QPC、PlayerPage 语义回执和有效桌面采样率。长按前进的 Debug QA 会在首次真实按下后恢复暂停基线的播放时钟，避免把“暂停无时钟”误判为播放器掉帧；该秒级长尾仍只作 P0 调查证据，不生成 p50/p95，也不改变正式页面语义。
- 连续扫描新增 `smooth_scan_start/command_start/command_complete/stop_*` 匿名 trace 节点，供下一轮按 cache、decoder、VO、Texture/DWM 分段定位长尾；不改变扫描速度、恢复顺序或默认后端。
- 在显式 Debug QA 环境下，连续扫描节点追加 `_runtime` 匿名快照（cache、decoder/VO 掉帧、硬解/同步、Texture 尺寸/代次和输出证据）；真实 1080p H.264 smoke 7/7 次落盘，`d3d11va-copy`、Texture `1920×1080`、代次 `1`，长按前进帧代理 p95 `108 ms`。VO 计数变化仍不是 DWM 像素掉帧结论，integration 报告继续标记 DWM unavailable。
- 稳定性矩阵 runner 现在把 Windows 显示器 inventory（边界、原生分辨率、当前刷新率、逻辑 DPI）写入报告，并明确标记为 `display-inventory-only`；显示器模式观测不能替代真实跨屏移动、全屏合成或跨 DPI 实机证据。
- 新短时同机对照已保留 `.local/qa/current-display-inventory-matrix-20260819`：MediaKit Texture 自动场景通过且实际硬解为 `d3d11va-copy`，QA-only child HWND 的精确 seek/首帧代理仍失败；该运行明确是 10 秒/6 次切换环境刷新，不作为完整发布门禁。

### 播放器进度条快速预览与准确收敛

- 进度条松手后先发起一次目标附近关键帧请求，再以既有 100ms 容差的精确 seek 收敛最终落点；拖动期间仍只更新本地滑块和缩略图，不连续向解码器派发命令。
- 预览阶段保持临时静音，最终位置确认后仍经既有新视频帧门禁才恢复用户音量；快速关键帧落点绝不作为准确定位结果保存或显示。
- 同机 4K/150% DPI 的独立 DWM 矩阵中，H.264 首画面 p95 从 367ms 降至 351ms，AV1 从 454ms 降至 287ms；HEVC 为 293ms，对比 286ms 未出现实质回退。默认后端、Texture 上限、播放队列、用户设置与数据不变。
- 修正 seek 延迟基线口径：integration 键盘回归不再等待长 GOP 关键帧预览的逻辑位置精确确认（`confirmationTimeout=0`），避免把约 2.7 秒的协调器等待误报为首帧呈现延迟；仍单独保留后端帧代理与桌面像素两种证据。

### 播放器长按快进连续播放

- 键盘短按前进/后退在松键时只提交一次关键帧跳转；收到首个长按前进重复事件后，播放器以至少 2× 进入临时连续扫描，松键即恢复用户原播放速度和音量。
- MediaKit/libmpv 扫描期临时切换为音频同步、关闭时间插帧并采用 `framedrop=vo` 输出端丢帧；扫描与恢复都在同一原生锁内读回确认。结束或换片时恢复原有倍速及呈现属性；属性快照不完整或读回不匹配时安全回退仅临时倍速，不覆盖用户设置。
- 长按快进不再连续提交随机 seek，避免长 GOP 或高码率媒体反复中断解码；临时状态不会写入播放设置。进度条精确定位、继续观看恢复、长按快退、播放会话、来源 filtered playback queue 和用户数据保持不变。

### 播放器硬解运行时恢复

- 用户已启用硬解而播放器连续三次确认实际回退软件解码时，会显示“当前视频已回退为软件解码”的运行时提示，并在视频表面保留持久降级条；降级条提供“重新打开”和只读“诊断详情”动作，避免一次性提示消失后用户失去上下文。
- 重新打开只按当前硬解偏好重新建立该媒体会话；不在正在播放的 NativePlayer 上热切换硬解，不修改持久化设置、队列或用户数据。
- 诊断详情同步显示实际呈现输出路径与软件解码回退确认/连续样本数，区分正式 Texture、QA child HWND 和未知兼容输出，避免把硬解请求或原生计数当成已呈现证据。

### 播放器进度条精确收敛

- 进度条拖动期间继续只更新本地滑块和缩略图预览；松手后只提交一次精确 seek，并在目标新视频帧交付后恢复音频。
- 精确拖动使用独立 latest-only 协调器和 100ms 位置容差，不再将 keyframe 预览的前置落点当作准确定位；拖动过程不连续派发解码命令。

### 全局 UI 标准盘点与主功能栏状态持久化

- 新增共享 `AppNavigationItem`，统一媒体库主功能栏展开/折叠入口的交互表面、选中语义、命中高度和 tooltip；品牌折叠入口复用 `AppInteractionSurface`。
- 主界面功能栏首次默认折叠，并通过既有 `library_sort.json` 保存展开/折叠状态；旧偏好缺少字段时安全回退为折叠。
- 保留主功能栏入口、稳定 key、回调、过滤、来源 filtered playback queue、缩略图/媒体详情队列、schema、stable identity 和用户数据。
- 全局 UI 盘点与后续组件族迁移边界见 `docs/design/UI_STANDARD_AUDIT_2026-08-17.md`。

### 媒体库筛选工具栏高度统一

- 媒体库搜索表面、筛选状态区和筛选动作统一使用 48px 顶栏控件高度，修复紧凑与普通布局相邻控件上下边界不齐。
- 保留收藏 chip、移除/清空筛选、搜索输入、结果统计和筛选语义；不修改 `FilterQuery`、`TagQueryService`、来源 filtered playback queue、
  缩略图/媒体详情队列、schema、stable identity 或用户数据。

### 设置首页可见工作区布局

- 宽桌面设置首页改为左侧“设置导航 / 当前策略”摘要、右侧“播放设置 / 数据与维护 / 应用”分组入口；窄窗口保留
  原有可滚动单列和入口顺序。
- 保留 `CacheSettingsPage` 的 section owner、`settings.category.*` key、设置持久化、二级页回调和返回路径；不修改
  schema、`FilterQuery`、`TagQueryService`、filtered playback queue、`PlayerBackend`、缩略图/媒体详情队列、stable identity
  或用户数据。

### 播放器启动首帧与精确恢复解耦

- 普通新视频在事件重绑后立即显式播放，首帧交付不再等待继续观看所需的精确恢复和画质属性收敛。
- 损坏媒体仍保留有界时长/codec 检测；继续观看与“每次询问”候选仍先完成精确恢复门禁。
- 不修改 `PlayerBackend`、`PlaybackSession`、来源 filtered playback queue、缩略图/媒体详情队列、schema、stable identity 或用户数据。

### 播放器短按快进停顿修复

- 键盘短按快进/快退恢复为单次关键帧预览，KeyUp 不再追加第二次绝对精确 seek，避免长 GOP 视频重新建立解码链造成停顿。
- 进度条提交与继续观看仍保留独立的精确定位入口；不修改 `PlayerBackend`、播放会话、来源 filtered playback queue 或用户数据。

### 播放器上下文菜单 UI 外壳重构

- 新增播放器上下文菜单 Before/After 视觉目标；视频信息与诊断入口显式使用播放器局部菜单表面，补齐菜单语义和稳定
  item key，同时保留原有 anchor、overlay 门禁、返回值和动作分发。
- 根据隔离 Windows 实窗反馈，菜单项的 `ListTile`、`Text` 和 `Icon` 显式使用播放器文字 token，修复菜单进入动画完成后
  的深色表面低对比度问题；未改变信息/诊断动作或播放器队列。
- 不修改播放器会话、来源 filtered playback queue、诊断采样、媒体详情/缓存队列、schema、stable identity 或用户数据。

### 目录管理共享 Tooltip 外壳收口

- 目录 root 路径提示改用 `MaintenanceTooltip`，统一维护页深色实色浮层、边框和等待时序；保留完整路径消息、页面返回、
  添加/重新扫描/解除管理回调和确认路径。
- 不新增目录读取、扫描重算、查询、blur 或持续动画，也不修改 schema、标签、filtered playback queue、稳定身份或用户数据。

### Missing / Relink 共享 Tooltip 外壳收口

- 单条缺失路径和批量预览路径映射改用 `MaintenanceTooltip`，统一维护页深色实色浮层与完整路径消息。
- 保留单条 relink、批量预览/执行、fingerprint 校验、确认、审计摘要和返回路径；不修改 stable identity、mutable path、缓存或用户数据。

### 播放器文件动作弹窗 UI 外壳重构

- 新增删除文件与重命名文件 Before/After 视觉目标；两个动作弹窗显式复用播放器局部主题，统一不透明深色浮层、
  描边和挂载证据。
- 保留回收站删除、影响范围、不再提示、重命名扩展名保护、输入校验、确认和取消动作；不修改文件事务、播放状态、
  filtered playback queue、缩略图/媒体详情队列、schema、stable identity 或用户数据。

### 播放器启动决策与能力警告 UI 外壳重构

- 新增继续观看与硬解能力警告 Before/After 视觉目标；两个启动前弹窗显式复用播放器局部主题，保留起播选择、
  硬解门禁、代理命令、复制和取消动作。
- 增加继续观看弹窗根 key，硬解规格正文改用播放器局部文字主题；不修改 `PlaybackSession`、`PlayerBackend`、
  filtered playback queue、缩略图/媒体详情队列、schema、stable identity 或用户数据。

### 播放器信息与诊断 UI 外壳重构

- 新增视频信息与播放诊断 Before/After 视觉目标；两类内容弹窗显式复用播放器局部主题，分组从匿名
  `DecoratedBox` 收敛为带实色、弱描边、统一圆角、裁切和容器语义的 `Material` 表面。
- 补充视频信息/诊断弹窗与主要分组的稳定 key；保留字段读取、诊断采样与 timer 生命周期、滚动、复制摘要、关闭和
  播放器上下文菜单入口。
- 不修改 `PlayerService`、`PlayerBackend`、`PlaybackSession`、filtered playback queue、`FilterQuery`、
  `TagQueryService`、缩略图/媒体详情队列、schema、stable identity 或用户数据。

### 播放器媒体控制 UI 外壳重构

- 新增媒体控制弹窗 Before/After 视觉目标；音轨、字幕、音画同步和章节从默认 `Card` 收敛为播放器嵌套
  工作区表面，使用实色、弱描边、圆角、裁切和稳定 Semantics/key。
- 弹窗显式复用 `playerWorkspaceTheme` 与已有 high contrast 策略；保留读取快照、选轨、关闭字幕、章节跳转、
  延迟调整、刷新、关闭和入口覆盖层生命周期。
- 不修改 `PlayerService`、`PlayerBackend`、filtered playback queue、播放会话、缩略图/媒体详情队列、schema、
  stable identity 或用户数据。

### 标签中心 UI 外壳重构

- 新增标签中心 Before/After 视觉目标；Tag Manager 从匿名双栏 `DecoratedBox` 收敛为带稳定 Semantics/key 的
  “标签中心工作区”、 “标签导航工作区”和“标签 inspector 工作区”，使用实色 Material、弱描边和统一圆角。
- 空详情与选中标签详情共用 inspector 边界；保留搜索、分组、选中态、属性编辑、别名、隐藏/收藏/排序、批量
  manual 标签、folder 来源门禁、合并/删除影响检查、焦点顺序和返回媒体库路径。
- 不修改 `LibraryApplicationFacade`、标签模型、`FilterQuery`、`TagQueryService`、filtered playback queue、
  ThumbnailService、schema、stable identity 或用户数据。

### 播放器交互 UI 外壳重构

- 新增播放器交互 Before/After 视觉目标；页面从通用 `Card` 收敛为“全屏播放列表工作区”和“播放器快捷键
  工作区”，使用实色表面、弱描边和稳定 Semantics/key，保留原有控件顺序和页面返回路径。
- 保留全屏边缘播放列表意图转发、快捷键录制、冲突就地提示、恢复默认、错误反馈和 Esc 全屏安全出口；不改变
  `CacheSettingsPage` 状态 owner、设置持久化或播放器命令边界。
- 不修改 `PlayerBackend`、`PlaybackSession`、filtered playback queue、ThumbnailService、媒体详情/缓存队列、
  `FilterQuery`、`TagQueryService`、schema、stable identity 或用户数据。

### 视频画质与增强 UI 外壳重构

- 新增视频画质与增强 Before/After 视觉目标；设置页从通用 `Card` 收敛为带稳定 Semantics 和挂载 key
  的“视频画质与增强工作区”，保留比例、缩放、色彩、流畅度、增强、HDR 和能力状态行。
- 保留既有 key、控件顺序、确认/取消、流畅度撤销、Dropdown/Switch focus 与页面返回路径；不改变播放
  偏好持久化、播放器会话应用、诊断或设备门槛语义。
- 不修改 `PlayerBackend`、PlaybackSession、filtered playback queue、ThumbnailService、媒体详情/缓存队列、
  schema、stable identity 或用户数据。

### 播放与解码 UI 外壳重构

- 新增播放与解码设置 Before/After 视觉目标；页面从通用 `Card` 收敛为带稳定 Semantics 和挂载 key
  的“播放与解码工作区”及“播放会话缓存工作区”，保留恢复策略、后端说明、解码器选择、流缓存开关。
- 保留既有 key、控件顺序、回调、键盘/focus/ink 反馈和页面返回路径；不改变 MediaKit Texture、
  decoder confirmation、demux window、缓存开关或设置持久化语义。
- 不修改 `PlayerBackend`、`PlaybackSession`、filtered playback queue、ThumbnailService、媒体详情/缓存队列、
  schema、stable identity 或用户数据。

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
