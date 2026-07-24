# CURRENT_TASK.md

> 本文件只保存当前活跃任务、最近稳定基线、已确认阻塞和下一步入口。已完成的详细记录进入 `CHANGELOG.md` 与对应 Chat 文档。

## 活跃任务

### 2026-07-24 原生纹理退出竞态与独立启动修复

- 目标：优先捕获并符号化原生 crash dump，围绕播放器纹理创建/销毁与退出做 N≥5 复现，再修复独立 EXE 启动、当前页面语义挂载并执行长时压力门禁。
- 原生根因已确认：既有 full dump 为 `0xc0000409`，WinDbg 精确落到 `media_kit_video_plugin` 的 `unordered_map::at`；Flutter 注册纹理时可在描述符写入 map 前同步取帧，回调又读取可变的全局 `texture_id_`，异常越过原生回调边界后终止进程。
- 构建期现从固定 SHA256 的 `media_kit_video 1.3.1` 归档生成 `video_output_ltp.cc`，GPU/软件纹理回调各自捕获稳定描述符，所有权继续由对应 texture ID 的 map 保持到注销完成；不修改 Pub Cache、`PlayerBackend` contract 或播放器队列。
- 播放器页面竞态基线 N=5 为 4 次完整通过、1 次控制条可见性脚本失败；修复后一次完整 900 秒门禁退出码 0，完成 35 个播放器创建/退出循环、0 无响应，门禁 WER 目录 0 dump，seek P95 28ms、dispose P95 5265.7ms。最终候选按用户指令停止，并在进程树收口前完成到第 30 轮、剩余约 140 秒，期间门禁目录 0 dump、日志 0 原生异常。
- 独立 EXE 旧配置无窗口根因是只保存尺寸/最大化、不保存坐标，却在有快照时传入 `center:false`；改为始终居中恢复尺寸后，真实现有配置直接启动 N=5 全部在 0.78–1.05 秒获得可响应 HWND。
- 当前实际挂载的紧凑排序控件补齐字段、方向和 6 个菜单项语义。真实 Windows UIA 点击确认全部 `qa.sort.*` 节点可达，菜单无溢出/遮挡并已恢复用户原“日期/倒序”偏好。
- `flutter analyze`、完整 268 项测试和 Windows Debug build 通过，3 项显式真实媒体 benchmark 按设计跳过。SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缓存队列、稳定身份和用户数据语义均未改变。
- 剩余风险：独立 EXE 启动可见性验证后的整进程关闭在全局 CrashDumps 产生同一 PID 的 `0xc0000005` / `0xc000041d`；本地符号栈显示纹理线程在 registrar 已为空后仍调用 `FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable`。它与已通过的播放器 Route 退出门禁不同，本轮未宣称修复。
- 下一步：优先把宿主关闭纳入独立 WER 门禁并收敛 registrar 生命周期；随后排查压力日志仍输出媒体 basename 的隐私缺口，并用更长门禁确认媒体库空闲阶段句柄缓慢上行是否属于驱动/DevTools 缓存还是可回收资源泄漏。

### 2026-07-23 未授权功能删除事故治理

- 目标：把播放器隐藏态细进度被误删的生产事故转化为仓库级容错，确保重构、布局调整或性能优化不能再次用孤立组件测试掩盖真实功能不可达。
- 当前状态：已完成规则与确定性保护。所有删除默认拒绝，修改前必须建立受保护行为/获授权删除清单，编辑后审计 diff 删除项；关键行为必须同时具备页面/Route 可达性证据与真实点击，证据不足时禁止提交推送。
- 生产或真实窗口发现的未授权功能删除固定升级为 Level 3 `independent`。新增播放器挂载合同测试、Agent 事故回归和 `required_validation_records` 评分硬门，完成项状态或验证方法不匹配直接零分。
- 零模型成本验证为 62 个用例、44/6/12 分布、17 项评分器测试与有效 Skill 目录；修正首轮过弱的 Level 2 预期后，隔离 N=5 回归达到 5/5、平均 100 分、`stable=true`、0 基础设施错误。
- 未修改播放器运行时、SQLite schema、过滤语义、filtered queue、`PlayerBackend`、缓存队列、播放设置、稳定身份或用户数据。

### 2026-07-22 播放器隐藏态细进度回归修复

- 目标：恢复完整控制条自动收起后贴在视频底边的 3px 只读播放进度，避免既有功能在未获授权时随控制层重排被删除。
- 当前状态：已完成。历史定位确认提交 `5271f63` 删除了 `PlayerPage` 中独立的 `PlayerHiddenProgressBar` 挂载，但遗留组件与孤立测试；现已按原 Stack 层级恢复，并增加边界注释禁止把它并入透明控制条子树。
- `flutter analyze`、完整 264 项测试与 Windows Debug build 通过，3 项显式真实媒体 benchmark 按设计跳过。真实 Debug 点击覆盖“进入播放器 → 3 秒自动隐藏 → 底部细进度保留 → 鼠标进入底部唤回控制条”，两态截图位于 `.local/qa/player-hidden-progress/`。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend` contract、缓存队列、播放设置、稳定身份或用户数据。

### 2026-07-22 播放器快速切换与预览纹理交接

- 目标：修复播放器连续切换不同分辨率视频时的 Windows 原生闪退，并让快速输入直接收敛到最新选择，不等待旧视频达到可播放状态。
- 当前状态：已完成。媒体卡进入正式播放前会先停止悬停预览媒体输出并取消旧异步代次；缩略图只承担首次进入播放器的冷启动占位，不再参与队列切换或跨媒体复用图片流。
- open worker 在滤镜清理、性能配置、`openPath` 返回和首帧校验等异步边界后都会检查更新请求；旧请求立即退出，损坏媒体总判定窗口仍约 1.5 秒，新选择检测粒度从 250ms 缩短到 80ms。
- Windows 事件日志确认修复前存在 `flutter_windows.dll` 的 `0xc0000005` / `0xc000041d` 原生异常记录。修复后真实悬停预览出画再进入播放器，日志显示预览纹理先释放并销毁，再创建正式播放器纹理。
- 第一轮跨 1080p / 2048×1080 / 4K 往返 20 次稳定；第二轮 20 次毫秒级输入用时 4.19 秒，只完成 5 次实际媒体 open，15 个过期请求被合并，最终第 1 条正常出画。进程保持响应，本轮新增 Application Error 为 0，截图与日志位于 `.local/qa/player-switch-crash-after/`。
- `flutter analyze`、完整 264 项测试和 Windows Debug build 通过。SQLite、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、`PlayerBackend` contract、缩略图调度、稳定身份和用户数据均未改变。

### 2026-07-22 启动后卡片预览与首播冷启动

- 目标：修复应用启动后首次悬停视频卡片永久 loading，并降低首次点击卡片进入播放器时的原生冷启动与 loading 闪烁。
- 当前状态：实现与 focused test 已完成。MediaKit 在 Flutter 首帧提交后统一预热，悬停预览和正式播放器共用可重试的幂等初始化门；悬停 Player 构造也纳入异常保护，失败会释放资源并复位 loading。
- 播放器跳转复用媒体库已验证缩略图覆盖原生纹理接管窗口；open 成功后至少保持 500ms 再按系统动效策略淡出。正常本地打开 800ms 内不闪 loading，真正慢盘或损坏媒体继续显示加载与失败反馈。
- Debug 真实启动测得首帧后 MediaKit 预热约 210ms；真实鼠标悬停连续出画。点击后约 575ms 显示缓存首帧占位且无 loading/黑屏，再约 700ms 由正在播放的原生视频帧接管；截图位于 `.local/qa/hover_preview_cold_start/final-hover-preview.png` 与 `final-player-playing.png`。
- `flutter analyze`、6 项聚焦回归、完整 263 项测试与 Windows Debug build 均通过，3 项显式真实媒体 benchmark 按设计跳过。SQLite、标签查询、filtered queue 内容/顺序、PlayerBackend contract、缩略图调度、稳定身份和用户数据均未改变。

### 2026-07-22 暗部增强闭环与 HDR 能力正式化

- 目标：补齐“画质增强路线”中未完成的 SDR 暗部增强，并将已具备活动 LUID、Compute 门槛和会话回滚的 HDR 映射从内部实验文案收敛为真实可选能力。
- 当前状态：已完成。新增默认关闭的“暗部细节增强”，仅对后端明确报告的 SDR、1080p 及以下、当前硬解会话应用保守 gamma 曲线；未知传递函数、4K 或软解保持关闭。
- 暗部曲线与自动去块/时空降噪/锐化合成单条 `vf` 快照，不在 UI 线程处理视频帧；独立压力计数在新增掉帧、缓冲或停滞时只回滚当前媒体，不改写用户持久开关。
- 最终固定样本 A/B：关闭/开启态各 60 秒、12 个诊断样本，均为 0 掉帧、0 停滞、窗口 0 无响应；进程 GPU Engine P95 均为 5.0%，显存 committed P95 为 299.4 / 300.1 MiB。像素预检保持 Limited 黑位 `YMIN=16`，`YAVG` 从 43.6642 提升到 45.4358。
- 同轮 HDR 60 秒样本在新增 1 个总掉帧后立即恢复 `auto`，验证运行时熔断真实生效。设置页删除内部“画质增强路线”卡，展示暗部增强与“HDR 动态映射”真实开关。
- `flutter analyze`、完整 258 项测试、Windows Debug build 和三组真实 MediaKit 固定样本均通过。Debug 真实点击确认开关可操作、恢复关闭后状态正确，页面无截断、遮挡、错位或溢出；两态截图位于 `.local/qa/settings-quality-completion/`。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 全屏边缘播放列表开关与命中修复

- 目标：提高全屏右缘播放列表的触发可靠性，避免鼠标到达最右边时列表反向消失，并把自动边缘唤出收敛为播放器交互页的单一开关。
- 当前状态：实现与 focused test 已完成。未展开时使用固定 32px 热区；展开后按实际 320–476px 列表宽度加 12px 容错保持，最右透明热区不再覆盖列表；离开完整列表后使用固定 450ms 宽限。
- 设置页删除热区宽度和隐藏延迟滑杆，只保留默认开启的“全屏边缘播放列表”开关。开关关闭只禁用鼠标边缘自动唤出，播放器显式列表按钮仍可使用；旧 JSON 参数继续兼容读取但不再参与运行时命中。
- `flutter analyze`、完整 255 项测试和 Windows Debug build 均通过，3 项显式真实媒体 benchmark 按设计跳过。Debug 真实点击确认：关闭开关时最右缘不触发；开启后约 320ms 展开，最右缘停留超过 850ms 保持，移回画面 700ms 后收起；设置页和全屏覆盖队列均无截断、遮挡、错位或溢出。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 播放器全屏返回与会话恢复

- 目标：播放器从全屏点击返回时，底层主界面和其他页面恢复为窗口最大化；同一应用会话再次进入播放器时恢复全屏。普通最大化进入播放器时继续使用原窗口路径。
- 当前状态：实现与 focused test 已完成。媒体库 Route 只持有内存态的播放器全屏会话标记，不写入 `PlaybackSettings` 或窗口布局文件；播放器返回前以 `window_manager` 实际全屏状态兜底，只有全屏路径执行“退出全屏 → 最大化 → Route 返回”。
- 用户在播放器内手动退出全屏会立即清除会话标记；从普通窗口或最大化窗口返回不会最大化窗口，也不会让下一次播放器误进全屏。
- 最终 `flutter analyze`、完整 255 项测试与 Windows Debug build 通过，3 项显式真实媒体 benchmark 按设计跳过。真实点击确认普通最大化进入/返回、播放器进入全屏、Esc 主动退出后清除恢复状态并在重进时保持窗口播放器；自动化运行时不支持鼠标侧键，直接全屏返回与重进全屏由 focused 状态测试和同一 `_exitPlayer` 代码路径覆盖，仍建议用实体鼠标侧键补一次人工验收。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缓存队列、稳定身份、播放设置或用户数据。

### 2026-07-22 全屏队列语境显隐与 Debug 独立启动

- 目标：全屏底部控制条可见时移除顶部队列语境遮挡，并修复手动双击 Windows Debug 包后进程存在但窗口不出现。
- 当前状态：已完成。全屏队列语境改为与控制条互斥；控制条出现时淡出，3 秒自动收起后恢复，不新增 Timer、队列查询或逐帧视频处理。
- Debug 启动根因是组合根在应用首帧前同步调用 `MediaKit.ensureInitialized()`；独立 exe 卡在该原生加载路径时，Dart VM 中 `_initialized=false`、窗口服务尚未创建。默认 MediaKit 后端现只在真正创建播放器时初始化，原生实验后端不受影响。
- 新 Debug exe 从构建目录直接启动后 864ms 获得非零窗口句柄并保持响应；真实点击覆盖“媒体库首项 → 播放器 → 全屏 → 控制条显示 → 3 秒收起”，两态截图位于 `.local/qa/fullscreen-controls/`。
- focused test、完整 254 项测试、`flutter analyze` 与 Windows Debug build 均通过，3 项显式真实媒体 benchmark 按设计跳过。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缓存队列、稳定身份或用户数据。

### 2026-07-22 HDR 长播、会话回滚与 SDR 暗部基线

- 目标：固定 HDR 样本验证长播观感、掉帧、GPU 功耗和显示输出；运行时压力自动回滚本次 HDR 会话；暗部增强继续使用独立 SDR 基线。
- 当前状态：已完成。主设置页把原“播放与继续观看”拆为“播放与解码”和独立“视频画质与增强”；继续观看、硬解和码流缓存留在前者，比例、缩放、色彩、自动画质、超分与 HDR 实验进入后者，仍共用同一设置快照与保存链。
- Windows DXGI 输出探针现返回每块 adapter 的桌面输出、分辨率、位深、色彩空间、HDR 信号和亮度元数据。当前活动 RTX 4070 SUPER 的 `DISPLAY1` 为 3840×2160、8 bit、`rgb-full-g22-p709`、HDR 信号未活动、峰值 417 nits；本轮 HDR 结论是映射到 SDR 显示输出，不宣称 HDR 直通。
- 固定 1080p HDR10/PQ 样本长播 302 秒，共 60 个 5 秒诊断样本：解码/输出/总掉帧最大值均为 0，停滞 0，全部 `smooth=true`，会话结束仍为 `hable + hdr-compute-peak=yes` 且无自动回滚。进程 GPU Engine 中位/P95 为 6.7% / 9.6%，GPU committed 为 458.5 / 470.4 MiB；NVIDIA-SMI 整卡功耗中位/P95 为 157.77 / 168.31 W，不能冒充进程功耗。
- 固定 1080p SDR 暗部样本长播 182 秒，共 36 个诊断样本：解码/输出/总掉帧最大值均为 0，停滞 0，全部 `smooth=true`。进程 GPU Engine 中位/P95 为 5.1% / 5.7%，GPU committed 为 301.4 / 308.4 MiB；近黑梯度与相邻灰阶可辨，作为暗部增强关闭态原始对照。
- HDR 压力保护复用两秒播放健康样本：新增掉帧、缓冲或音视频停滞立即回滚；帧推进、缓存或 FPS 中等压力连续两次才回滚；seek/暂停不评估，回滚锁存到下一媒体且不改写持久开关。释放期进入退出态，避免销毁停顿误触发。
- 真实点击已覆盖“设置 → 视频画质与增强 → HDR 实验 → 确认 → 关闭”，首页拆分、画质页和两态截图均无截断、遮挡、溢出或状态歧义，证据位于 `.local/qa/hdr-mapping/`；固定样本 JSON、进程指标、后端帧和窗口截图位于 `.local/qa/fixed-quality-baseline/`。
- 最终 `flutter analyze`、完整 253 项测试、Windows Debug build、活动 LUID / Compute / 显示输出 integration test、设置真实点击和固定样本长播/短复测均通过；3 项显式真实媒体 benchmark 按设计跳过。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 原生 GPU 能力矩阵与第三阶段闸门

- 目标：从实际 MediaKit / ANGLE 渲染设备返回活动 adapter LUID，在该 LUID 上建立 1080p / 4K Compute 帧预算，只选择一个第三阶段功能做默认关闭、可回滚实验；暗部增强保持独立观感与性能基线。
- 当前状态：已完成。构建期只替换固定 SHA256 的 MediaKit `ANGLESurfaceManager` 单个源文件，在真实 D3D11 device 创建/销毁处登记 LUID；不修改 Pub Cache，不按枚举顺序、Feature Level、名称或显存占用推断活动显卡。
- 当前设备矩阵：RTX 4070 SUPER（约 11.72 GiB 专用显存）与 AMD Radeon Graphics（约 460 MiB 专用显存）均为 D3D 12_1、Compute 已验证、Vulkan 已匹配；Microsoft Basic Render Driver 标记为软件适配器，不参与活动硬件卡选择。完整证据见 `docs/qa/player_gpu_capability_matrix_20260722.md`。
- 实际生产渲染设备返回 LUID `00000000:00016bec`，精确匹配 RTX 4070 SUPER。D3D11 HDR 类 Compute kernel 在 60fps 的 4.167ms 预留切片下，1080p P95 为 0.036ms、4K P95 为 0.129ms，两档均通过；JSON 位于 `.local/qa/gpu-capability-matrix/active-device-compute-budget.json`。
- 该阶段只选择了“HDR 动态映射”做可回滚验证；后续已保留默认关闭、HDR 源、精确 LUID、Compute 能力与会话压力门槛，并收敛为正式用户文案。运动补帧保持未启动；`hqdn3d` 已以保守时域参数参与时空降噪。
- `tool/run_gpu_capability_matrix.ps1` 可重建活动 LUID、设备矩阵和 1080p / 4K 预算；压测显式触发并在原生后台执行，普通播放启动不运行 Compute 基线。
- 暗部增强不与第三阶段 Compute 功能共用结论；后续已使用固定 SDR 暗场样本完成独立开/关 A/B，并只在 SDR、1080p 及以下、实际硬解边界内提供默认关闭的手动开关。
- 隔离 Windows integration test 真实点击“设置 → 播放与继续观看 → HDR 实验 → 确认 → 关闭”，开启/回滚两态无遮挡、溢出或状态歧义；截图位于 `.local/qa/hdr-mapping/`。真实 MediaKit 会话另行核验 `hable/yes → auto/auto` 回滚。
- 最终 `flutter analyze`、完整 251 项测试、Windows Debug build、活动 LUID / Compute 基线 integration test 与 HDR 两态真实点击 integration test 全部通过，3 项显式 benchmark 按设计跳过。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 自动画质协调器与 GPU 能力检测

- 目标：先建立 1080p / 4K 的 GPU、CPU 与丢帧基线，再让第二阶段去块、降噪和适度锐化只在实时余量允许时动态启用；第三阶段功能必须先经过真实显卡能力检测。
- 当前状态：已完成。主界面“播放与继续观看”设置新增默认关闭的“自动画质协调器”，隔离 Debug 窗口已完成设置开关、1080p / 4K 播放、队列滚动与诊断真实点击。
- 隔离实测稳定段：1080p 硬解 CPU / GPU Engine 中位 64.9% / 43.3%，软解 142.4% / 1.0%，两者解码/总掉帧均为 0；4K 硬解 66.5% / 59.2% 且 0 掉帧，4K 软解 216.1% / 1.0%，出现 27 帧总掉帧与 0.114 秒 AV 偏移。完整口径见 `docs/qa/player_quality_baseline_20260722.md`。
- 协调器复用原播放健康 Timer，每两秒采集扩展样本；连续 8 个健康样本且满足 10 秒冷却才升级。1080p 硬解最高锐化、1080p 软解最高降噪、4K 硬解最高去块、4K 软解保持关闭；新增掉帧、缓冲、停滞或 FPS 压力立即降级。
- 去块、`hqdn3d` 和 `unsharp` 使用 FFmpeg 官方滤镜参数，并作为单条 `vf` 快照经既有 `PlayerBackend` 串行应用；Flutter 不读取视频帧，不新增 UI Timer，不触碰 filtered queue 或后台媒体队列。
- `PlayerGpuCapabilityDetector` 在媒体可播放后读取实际输出驱动、GPU API/上下文、D3D11 Feature Level、当前硬解和 HDR 源信号；后续原生设备矩阵已补齐 Compute / Vulkan 能力，但多卡环境仍须唯一确认活动适配器才可解锁。
- 最终 `flutter analyze`、完整 244 项测试与 Windows Debug build 通过，3 项显式 benchmark 跳过。真实诊断中 1080p GPU 档升至“去块 + 降噪 + 锐化”，4K GPU 档封顶“去块”，两者解码/总掉帧均为 0；截图保存于 `.local/qa/2026-07-22-quality-live/`，不进入仓库。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缩略图/媒体详情队列或用户数据。

### 2026-07-22 播放器第一阶段画质能力与队列密度

- 目标：减小播放器队列卡片的无效内间距，并把第一阶段画质、解码、缓存与诊断能力集中到主界面设置页；第二、三阶段只展示真实路线，不提供尚未满足流畅度门槛的假开关。
- 当前状态：已完成。队列卡片横向内边距、序号占位和内容间距已收紧，缩略图与标题略增大，11176 项队列仍按可见项构建。
- 播放设置新增原始高清码流缓存、正确画面比例、Bicubic / Lanczos 缩放和自动 / Limited / Full 输出色彩范围；自动硬解显式允许连续失败三帧后回退软件解码，默认高质量缓存使用 96 MiB 前向与 32 MiB 回看内存窗口，不复制源文件。
- 既有 FFprobe 媒体详情缓存继续负责编码、分辨率与时长；播放诊断补充实际亮度/色度缩放器、源色彩范围、矩阵、原色、传递函数和输出范围，并保留实际硬解、缓存、解码/输出/总丢帧。
- 第二阶段“去块、降噪、适度锐化、暗部增强、自动画质”和第三阶段“AI 超分、时域降噪、运动补帧、HDR 映射、Vulkan / Compute Shader”在设置页标记为待性能基线/能力检测，避免默认打开高开销滤镜导致播放或 UI 卡顿。
- 精确 Debug 真实点击覆盖设置入口、缩放器切换并恢复、播放器入场、队列滚动和播放诊断；实测 `d3d11va-copy`、Lanczos、自动输出范围、源 `limited / BT.709 / BT.1886`，解码与总丢帧为 0，缓存约 111 秒，视频/音频持续推进。
- `flutter analyze`、完整 238 项测试与 Windows Debug 构建通过，3 项显式 benchmark 跳过；截图保存于 `.local/qa/2026-07-22-player-quality/`，不进入公开仓库。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容/顺序、稳定身份、缩略图/媒体详情队列或用户标签/收藏数据。

### 2026-07-22 播放器控制显隐、全屏覆盖队列与快进档位

- 目标：降低播放画面上的常驻遮挡，在不改变 filtered queue 和视频纹理尺寸的前提下提供流畅的全屏覆盖队列、自定义快进快退档位与左上角文字反馈。
- 当前状态：已完成。控制条首次进入默认显示，3 秒无交互后自动收起，仅鼠标进入底部进度区域时重新显示；全屏队列以根层覆盖动画出现并铺满高度，不再挤压或缩放画面。
- 更多播放设置新增 5 / 10 / 15 / 30 / 60 秒离散滑动档位，前进/后退按钮与快捷键统一读取；按键连发只在左上角显示一次轻量文字水印，不再使用中央 HUD。
- 真实 Windows 复测覆盖 1249×714 窗口、2560×1440 全屏、11176 项队列滚动、控制条自动隐藏、快进水印和更多设置。复测发现设置页内部 `AnimatedSwitcher` 与视频纹理叠加会触发 Flutter Windows 引擎访问冲突，改为内容树直接切换后连续打开和停留均稳定。
- Apple 式动效使用 320ms 淡入/短距离右滑和更短退出，动画只改变合成属性；reduced motion 继续缩短/移除位移，不为队列滚动增加全列表动画或新 I/O。
- 最终 `flutter analyze`、完整 238 项测试与 Windows Debug 构建通过，3 项显式 benchmark 跳过。测试后的 GPU 超分开关已恢复关闭。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、`PlayerBackend` contract、缩略图/媒体详情队列或用户标签/收藏数据。

### 2026-07-22 播放器 GPU 画质超分

- 目标：在播放器进度条齿轮设置中提供可即时开关的画质超分，同时保持视频播放、filtered queue 与 Flutter UI 响应流畅。
- 当前状态：代码、持久化、focused tests、全量测试、静态分析与 Windows Debug 构建已完成；显式启动 Debug 路径时 Windows 应用激活实际路由到已安装 Release 进程，随后又检测到用户正在窗口输入，自动化按安全规则中止，因此仍需补做新构建的准确人工点击与截图复验。
- 当前打包的 libmpv `v0.36.0-403` 不包含新版 Intel/NVIDIA `d3d11vpp scaling-mode` 厂商扩展；本轮使用其已支持的 `ewa_lanczossharp` GPU 高质量上采样，不宣称 RTX/Intel AI 超分。
- 设置默认关闭；开启后显式使用 `scaler-resizes-only=yes`，仅在源画面需要放大时运行，高质量亮度缩放与 sigmoid 变换留在 GPU renderer，Flutter UI 不处理视频帧。
- 关闭后恢复 Lanczos 基线；每次媒体 open 前后重新应用设置，播放诊断显示开关、实际 `scale` 与 resize-only 状态。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、解码设置或用户标签/收藏数据。

### 2026-07-21 GitHub 首次公开发布与隐私收口

- 目标：让首次访问仓库的人能理解产品目的、特色功能、技术框架和架构边界，并通过 GitHub Release 获取 Windows / macOS 安装包。
- 当前状态：README、隐私过滤和 `v0.1.0` GitHub Release 已完成；Actions 运行 `29821115757` 的版本解析、Windows、macOS 与公开发布 job 全部成功。
- README 已按“问题场景 → 核心闭环 → 特色能力 → 技术栈 → 架构思想 → 下载/隐私/边界”重写，明确本项目不是 VLC / PotPlayer 的替代品。
- `vX.Y.Z` 标签发布改为 Windows 与 macOS 双端成功后原子创建 Release，同时上传 `.exe`、`.dmg` 和两份 SHA-256；普通分支与手动构建不创建公开 Release。
- 已清理公开 `master` 历史中的个人邮箱、本机用户名/盘符路径和 `.codex/config.toml`，提交者统一为 GitHub noreply 身份；公开分支和标签均只引用脱敏后的历史。
- 本地开发配置和路径上下文继续保留，但由 `.gitignore` 隔离；数据库、日志、媒体样本、环境变量、签名证书、安装包和本地私有配置均加入上传过滤。
- 定向审计未发现已跟踪的媒体文件、数据库、日志、环境变量、私钥、签名证书或 API token。公开仓库仍包含随桌面包使用的 FFmpeg/FFprobe 第三方二进制，属于依赖与许可证审查项，不是个人隐私。
- 公开 Release：Windows x64 安装器 108,566,180 字节，SHA-256 `74b733522c32eef027d9c1b0e846d3bfc6d740e6725fb30544a6f0f1e03c6ea6`；macOS DMG 42,757,651 字节，SHA-256 `6bbdf24c2b288dab2277bc3592557595f31c3bca37abaa7268c15c3b7bb8320a`。

### 2026-07-21 Windows / macOS 正式版安装包

- 目标：基于 `pubspec.yaml` 的 `0.1.0+1` 构建 Windows x64 Release 安装器与 macOS Release DMG，不改变业务、数据或播放语义。
- 当前状态：已完成。Windows 本地 Release 安装器、隔离安装/启动/卸载冒烟均通过；独立 macOS runner 已完成 Release 构建、10 秒启动检查、DMG 生成与上传。
- Windows 安装器使用当前用户目录安装，卸载时保留用户数据库、标签、收藏和播放记录。
- macOS bundle identifier 已从模板占位符收敛为 `com.zero1412.localtagplayer`，Finder 展示名为 `Local Tag Player`。
- 仓库当前没有 Windows Authenticode 与 Apple Developer ID / notarization 凭据；生成的安装包必须明确标记为未签名或未公证，不能宣称通过系统信任链。
- Windows 安装器：108,571,720 字节，SHA-256 `0ad9b542bed463d9036111c1a2a7acc2e1e0fe4ff4d4261339665890a506fe36`。
- macOS DMG：42,757,735 字节，SHA-256 `536c53e804e2267ccecc3d6991da66561e25bc6676cf94119e5d3222b03a5094`；Actions 运行 `29815594317` 的 Windows / macOS job 均成功。

### 2026-07-21 媒体卡片文件菜单收口

- 目标：让媒体卡片“更多”只承担当前文件定位与删除，移除与播放器详情重复的标签编辑和文件重命名，并缩小悬浮菜单。
- 当前状态：已完成。
- 网格卡片、紧凑列表和本地目录视图共用“打开文件 / 删除文件”双项菜单；播放器详情中的标签编辑与重命名能力保持不变。
- “打开文件”仍通过 `FileSystemAdapter.revealInFileManager(item.path)` 定位当前卡片的完整视频路径，不打开媒体库 root 或资源目录。
- 菜单宽度限制为 136–156px，条目最小高度 40px，外层垂直留白 4px；真实窗口无遮挡、溢出或文字截断。
- 页面级回归直接记录平台边界收到的路径，并断言等于被点击卡片；同时锁定菜单不再出现“编辑标签 / 重命名文件”。

## 当前稳定基线

- 产品边界：Tag 驱动的本地视频发现播放器，不扩展字幕、音轨、逐帧或 A-B loop 等专业播放器能力。
- 数据边界：SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容与顺序、标签来源语义均未改变。
- 验证：247 项测试通过，3 项显式 benchmark 跳过；播放器控制显隐、全屏覆盖队列、快进档位、左上角文字反馈、GPU 超分、自动画质协调与原生显卡设备矩阵回归、`flutter analyze`、Windows debug build 均通过。真实窗口完成设置开关、1080p / 4K 播放、队列滚动与诊断复测；低分辨率超分两态、自动画质和 GPU 设备矩阵诊断截图已保存。
- 架构基线：`Architecture Baseline 0.5.54`。

## 已确认阻塞

- 外部跨平台规划 `<private-planning-document>` 当前不存在；本轮依照仓库内长期规则和现有跨平台边界实施。
- GitHub 服务端仍暂存重写前的无引用提交对象；公开 refs、普通历史浏览和 clone 均已脱敏，但已知旧哈希仍可通过 Commit API 命中。仓库侧没有删除无引用对象的 API，需由仓库所有者向 GitHub Support 请求 cached views / references purge，完成后再验证返回 404。
- GitHub 仓库顶部 About 简介仍是旧的“替代手动文件夹 + PotPlayer”定位，会进入浏览器标题和搜索摘要；当前 GitHub 连接没有仓库元数据写接口，验收浏览器也未登录。需所有者在仓库首页 About 设置中改为“用标签发现、组合筛选与当前结果队列管理和播放大型本地视频库的 Flutter 桌面应用。”

## 下一步入口

1. 向 GitHub Support 提交重写前提交对象与 cached views 的服务端清除请求，并在仓库 About 设置同步新的单句定位；完成后确认旧 Commit API 返回 404、公开页标题不再显示旧描述。
2. 对外扩大分发前配置 Windows Authenticode 证书、Apple Developer ID Application 证书与 notarization 凭据，重新验证 SmartScreen / Gatekeeper。
3. 补充脱敏的真实产品截图，并确定项目级许可证及 FFmpeg/FFprobe 再分发说明。
