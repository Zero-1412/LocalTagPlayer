# Chat 4：播放器与筛选结果队列

## 2026-08-19 · 桌面像素证据链收口

- 稳定性矩阵现在识别 `native_rendered_frame`、`presented_frame_fallback` 和超时阶段，并把 `reverseKeyframeTrace`、缓存/解码/VO/Texture 分段差异同时写回总矩阵和每个 backend 的 `reportPath`，避免独立审查报告丢失证据。
- 最新同机真实 4K 长 GOP H.264/HEVC/AV1 integration smoke 已将连续扫描聚合为 `keyboardExperience.smoothScanTrace.summary`：首帧 `314/284/292 ms`、seek p95 `241/199/259 ms`，扫描命令到音频恢复最长 `133.417/153.990/127.842 ms`，停止 cache 最长 `13.317/11.483/57.365 s`，停止累计掉帧最多 `10/13/9`，Texture 代次均 `2`、实际硬解均 `d3d11va-copy`。证据等级固定为 `backend-runtime-snapshot-not-desktop-pixels`，只用于 cache/decoder/VO/恢复定位，不替代实体键盘→DWM 首帧验收；日志在 `.local/qa/turn-4k-{h264,hevc,av1}-scan-summary-20260819.log`。
- 2026-08-20 QA-only 反向播放实验：临时设置 mpv `play-direction=backward` 并每 100ms 采样 20 次，H.264/HEVC/AV1 均为 `no-sustained-backward-position`，目标到最小位置分别为 `336607→336616`、`291769→291766`、`258601→258601 ms`；三种编码均为 `d3d11va-copy`、Texture 代次 `2`，最终方向恢复 `forward`。这不是正式功能验收，正式长按后退仍保持 latest-only keyframe preview；mpv 官方文档将该方向标为脆弱且通常更慢。
- 稳定性矩阵每个 backend 报告同步保留 `qaReverseDirectionExperiment`；未设置 QA 开关时保留 `enabled=false/status=not-run`，不把“未运行”混成“反向失败”。
- 桌面 correlation 修复 StrictMode 下空 trace 数组被展开为 `$null` 导致的 `PropertyNotFoundException`；自动化 PlayerPage 现在保留页面键盘事件和 ambiguous trace 状态。一次外部 UIA/Accessibility 观察器污染会话曾让 Debug 4K PlayerPage 触发 `flutter_windows.dll 0xc0000005`，重置观察器后同一 960 窗口和 H.264 长素材以 115.8–117.4 fps 稳定通过；该污染样本不计入播放器性能，真人矩阵前必须关闭或重置语义树客户端。
- 正式 PlayerPage 新增 `playerFullscreen` Debug-only 实窗门禁；干净 4K H.264、1280×720 逻辑窗口、144 DPI 单样本以 `115.5 fps` 捕获，Enter→窗口几何变化 `50 ms`，全屏稳定后 Texture generation 仍为 `3`。同一会话的启动尺寸轨迹为 `1920×1080 → 3840×2160 → 1600×900`，保留了 Texture 重建成本证据；该动作只验证全屏/Texture 结构，不进入 seek p50/p95。
- 同一门禁已补 HEVC/AV1：HEVC `113.0 fps`、Enter→几何 `44 ms`，AV1 `115.7 fps`、`50 ms`；两者启动尺寸均为 `1920×1080 → 1600×900`，稳定后 generation `3`。三编码全屏各只有一次几何切换，但 H.264 的 `3840×2160` 中间 Texture 代次没有在 HEVC/AV1 重现，说明生命周期受编码/解码器时序影响，不能外推为统一路径。
- QA-only 关闭自适应尺寸的 HEVC/AV1 对照均创建 `3840×2160`、generation `2`（有效采样 `121.5/113.9 fps`），而正式自适应路径收敛到 `1600×900`、generation `3`；该证据支持继续测合成压力，不支持直接提高正式 Texture 上限。
- 干净 Debug 真实 PlayerPage virtual-key 7 轮对照：前进 Down→DWM p50/p95 `94/107 ms`、后退 `93/96 ms`，两组均 7/7、约 112–117fps；`inputMode=win32-keyboard-virtual-key`，仅证明 Focus/页面输入链可达，不能替代真人 QPC 门禁。
- 桌面像素矩阵新增 Debug-only `HoldMilliseconds` 长按对照；QA 页在首个自动化 forward Down 后恢复播放，避免暂停状态下只改速率不推进时钟。4K H.264、144 DPI、900ms virtual-key 长按 7/7：前进 Down→DWM p50/p95 `908/912 ms`、最长静帧 `2–9 ms`；后退 latest-only 预览 `907/916 ms`、`1–7 ms`，有效采样均约 `110–121 fps`。这是 `win32-keyboard-virtual-key-long-hold` 自动化证据，不是实体 WM_KEYDOWN/QPC，也不代表约 900ms 首帧已经达到专业播放器体验。
- HEVC/AV1 同合同补测：HEVC 前进/后退 7/7，Down→DWM p95 `1029/916 ms`、最长静帧 `108/4 ms`；AV1 前进 p95 `1040 ms`、最长静帧 `1025 ms`，后退 7/7 全部 `pixel_change_timeout`，但页面 repeat 与 trace 均到达并最终出现 `new_video_frame_timeout`/`native_rendered_frame_timeout`。三编码实际硬解均为 `d3d11va-copy`；该差异保留为 P0 呈现/寻址证据，不升级为正式功能结论或实体键盘统计。
- 独立桌面像素矩阵现把每轮 `ready`、renderer 事件和运行态日志聚合为 `runtimeEvidence`，明确保存硬解、首帧证据、Texture 重建次数/尺寸与 decoder/VO 掉帧 null 语义；三轮真实 PlayerPage 4K H.264 自动化前进的 Down→DWM p50/p95 为 `98/105 ms`，最终 `d3d11va-copy`，Texture 重建事件 `2–3` 次。PlayerPage 前进/后退现在按 virtual-key 标记，避免把自动化输入误写为 scan-code；该样本仍不是实体键盘验收。
- 反向 trace 新增 `segmentTrace`：分别列出命令完成、命令后运行态、cache/decoder/VO、后端帧代理、Texture 代次和 DWM unavailable；integration 测试明确不观测 DWM，必须由桌面像素侧车补齐。
- 位置确认窗口现在单独写出 `position_confirmation_start` 与 `position_confirmation_complete|superseded|timeout`；这段协调器等待不再混入桌面首帧延迟，键盘预览的零超时路径保持无该阶段。
- Debug 像素门禁成功后另写 `desktop-pixel-trace-correlation.json`；原生实体消息现在同时写 QPC/UTC，关联器按本次 Down 前 500ms 到首像素/松键后 1s 的动作窗口筛选 `PLAYER_SEEK_TRACE`，只有唯一动作窗口才匹配，重叠窗口标记 `ambiguous-overlapping-pixel-action-windows`，不再把窗口外或重叠窗口按最近邻误归因。UTC 仍只做窗口筛选，不能替代不同源时钟之间的 QPC→DWM 延迟。
- 关联器优先读取 `wall_utc_us`，旧日志回退 `wall_utc_ms` 并标注精度；每个动作只有在唯一 trace id 时才生成 `actionTraceSummaries` 和 `commandCompleteToFirstChangedPixelMs`，否则保留无归因状态。独立 standalone Debug PlayerPage 拖动 smoke 已复核 `117.6–119.8 fps`、Down→DWM 首变更 `497–528 ms`、Up→首变更 `291–296 ms`，但这是自动化 Slider 输入且首帧仍是估算帧回退，只验证证据管线，不进入实体键盘 p50/p95。旧长按样本没有 `utcUs` 与 `smooth_scan_*` 阶段，不能倒推连续扫描分段；自动化键盘 smoke 未收到 PlayerPage 语义回执，也未被解释成性能结论。
- correlation 的页面语义筛选同时覆盖 `win32-keyboard-*` 与 `manual-keyboard-*`；自动化键盘有回执时只保留估算 UTC 窗口，只有 native QPC/UTC 侧车才可进入实体输入证据。
- 后续复测发现原生 JSONL 新增 `utcUs` 后，探针的 `qpcUs` 截取仍假设字段在对象末尾，曾把真实消息误判为未收到 QPC；现已按逗号/对象结束解析并补合同、编译门禁。门禁缺少摘要时也优先回传探针原始失败分类，避免覆盖“缺少实体输入”等根因。
- 当前 Debug 4K H.264 只读 integration trace（`current-4k-h264`）中，短按后退帧代理 p95 为 `99 ms`、长按后退为 `238 ms`，反向 trace 命令 p95 `0 ms`、命令到帧代理 p95 `3 ms`，7 次 Texture 代次差均为 `0`，硬解为 `d3d11va-copy`；旧 `2.7 s` 是旧协调器口径，不在该后端分段中重现，仍需桌面像素/实体键盘复核。将 integration 键盘协调器的位置确认统一为正式页面的 `Duration.zero` 后，同一真实素材七次复测为短按后退 `80 ms`、长按后退 `139 ms`、命令到帧代理 `39 ms`、Texture 代次差 `0`；仍只代表后端帧代理，摘要保存在 `.local/qa/current-reverse-trace-zero-confirmation-20260819-summary.json`。
- Debug-only 实体键盘门禁在 `SetChildContent` 建立父子 HWND 关系后安装 `FLUTTERVIEW` 与 runner 观察器；`manualForward`/`manualBackward` 传递方向并分别提示 `L`/`J`。现在已取得短按前/后各 1 条、长按前进 1 条真人样本，但仍未达到独立七会话 p50/p95 的统计门槛。
- 实体键盘门禁新增 `manualLongForward`/`manualLongBackward`：长按动作要求匿名 QPC 文件同时出现 Down/Up、默认至少 `600 ms`，并在首个稳定像素后保留 `250 ms` 尾部采样；它与短按使用不同 input mode，不把松键边界伪造成短按延迟。
- 稳定性矩阵 runner 现在把 Windows `displayInventory`（原生分辨率、当前刷新率、逻辑 DPI、边界）和
  `physicalCrossDpiEvidence.evidenceKind=display-inventory-only` 写入报告；`physicalWindowMoveConfirmed` 保持
  `false`，显示器模式探测不能替代真实跨屏/全屏合成证据。短时同机报告为
  `.local/qa/current-display-inventory-matrix-20260819`，正式 Texture 自动场景通过，QA-only child HWND 仍失败。
- 首批正式 PlayerPage/Texture 实体像素样本（144 DPI、高码率 H.264 1080p60）为短按前进 `159 ms`、短按后退 `10 ms`；长按前进按住 `2478 ms`，Down→首个稳定像素 `2380 ms`、最长静止段 `450 ms`。长按前进的 QA 页在首次真实 L 按下后才恢复播放时钟，修复“暂停基线无新帧”的测量前置条件；`2380 ms` 仍是 P0 长尾，不作 p50/p95，后续必须继续按 cache/decoder/VO/Texture 分段。
- 连续扫描现在写出 `smooth_scan_start → smooth_scan_command_start → smooth_scan_command_complete/failed → smooth_scan_stop_*` trace，可与桌面 QPC/UTC 侧车关联；命令完成仍不等价于实际呈现帧。
- 在显式 `LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA=1` 下，上述节点的 `_runtime` 变体会串行记录 cache、decoder/VO 掉帧、硬解/同步属性、Texture 尺寸/代次与输出证据；真实 1080p H.264 integration smoke 7/7 次完整落盘，`d3d11va-copy`、Texture `1920×1080`、代次 `1`，长按前进帧代理 p95 `108 ms`，扫描结束 VO 总掉帧计数为 `2–3`。这些是后端运行态分段，DWM 仍 unavailable，不得直接写成桌面体验通过。
- 输入路由修正：Debug-only runner 顶层 `FlutterWindow::MessageHandler` 现在在 `HandleTopLevelWindowProc` 前旁路记录 J/L QPC，并按 `lParam` 去重 subclass 重复消息；合成冒烟已同时产生 native 与 PlayerPage 回执，但因桌面采样只有 `6.6 fps` 被拒绝，不能作为性能证据。
- 同一真实 4K H.264 的独立后端 trace 对照中，正式 Texture 的反向命令到帧代理 p95 `39 ms`，child HWND 为 `73 ms`；Texture 使用 `d3d11va-copy` 且代次差为 `0`，HWND 使用 `d3d11va`，其原生计数证据标为 `native-rendered-child-hwnd`，估算帧回退才标为 `child-hwnd-visible+estimated-frame-number-proxy`。完整 PlayerPage 稳定性矩阵因精确位置未收敛而失败，未把失败样本混入对照；两者仍需实体键盘→DWM 像素合同才能比较正式体验。
- 稳定性矩阵在集成测试未写出正式报告时会生成匿名 `failed-no-report` backend 报告并保留固定失败分类；`current-texture-hwnd-matrix-20260819c` 的失败分类为 `exact_seek_position_unconfirmed`，不会被空对象吞掉。随后 latest-only seek 的每个 Future 都立即挂接错误处理并等待收敛，并修正 `loop-file=inf` 短片跨尾部回绕的判定。`current-texture-hwnd-matrix-20260819h` 显示正式 MediaKit Texture 三种真实样本全场景通过，`seekFailureCount=0`、`d3d11va-copy`、帧代理观察 p95 `261 ms`、Texture 代次差 `0`；QA-only child HWND 的布局/全屏/模拟 DPI/快速切换/长播通过，但 `2/18` 精确 seek 未确认、首帧观察 `15` 次超时、`d3d11va`，所以双后端总体仍 failed，失败作为 HWND 闭环证据保留。
- 保护：正式 MediaKit Texture、来源 filtered queue、播放会话、硬解偏好、schema 和用户数据均不变；本节只修 QA 证据和 Debug-only 提示。
- 诊断补充：只读诊断快照同时记录 `framePresentationEvidenceKind`、软件解码回退确认和连续样本数；它不把 `hwdec` 请求值当成实际状态，也不把 child HWND 的原生计数当成 Texture 呈现。

## 2026-08-18 · 真实性能基线与 Texture/HWND 对照

- 范围：本轮只建立 Debug 性能证据，不修改用户可见播放逻辑、默认后端或持久化设置。样本为本机私有 H.264/HEVC/AV1、1080p/4K、高码率/长 GOP 组合；路径、文件名和视频 ID 不进入仓库或报告。
- 正式 MediaKit Texture：六个样本均确认 `d3d11va-copy`。精确 seek p95 为 1080p H.264/HEVC/AV1 `480/223/199 ms`，4K `931/574/255 ms`；首帧 `294–340 ms`。1080p 长 GOP H.264 的 controller-level p95 为短按前进/后退 `59/2702 ms`、长按前进/后退 `102/2729 ms`、拖动 latest-only `158 ms`。后退长尾是下一轮需要优先定位的事实，不得用前进扫描优化掩盖。
- 稳定性：正式 Texture 的 10 秒长播四次采样无停滞、无掉帧；全屏 6 次、队列布局 6 次均保持同一 Texture 代次。页面最新 seek 的“开始观察新帧后”代理为 p50/p95 `154/303 ms`、0 超时，但 evidence 是 `estimated-frame-number-fallback`，不是桌面像素呈现。
- HWND QA 对照：H.264 1080p/4K seek p95 `312/507 ms`，但 4K HEVC 与 1080p AV1 首帧都超过 30 秒；1080p 三样本长播从约 1.2 秒停住，4 次采样中 3 次 video/audio stall，页面路径还有 18 次 `native-rendered-frames=0` 导致的新帧观测超时。因此 child HWND 不能作为正式 Texture 的替换候选，亦不能反向修改正式预览节流。
- 证据等级：`native-rendered-frames>0` 才是原生共享 Texture 复制的直接代理；正式 MediaKit 当前为位置/估算帧号回退，child HWND 为“可见子窗口 + 估算帧号”代理。两者都不是实际桌面像素，因此发布级“输入到首个实际画面”必须补固定帧率录屏或桌面捕获并与 `PLAYER_SEEK_TRACE` 单调时间对齐。
- 保护：MediaKit Texture 继续是正式默认；`PlaybackSession`、来源 filtered queue、当前索引、标签筛选、缓存/详情队列、schema、stable identity、用户数据和媒体文件不变。

## 2026-08-18 · 长按快进连续扫描呈现修复

- 现象：即使交互式 seek 已指定 `absolute+keyframes`，长按仍以约 64ms 的 KeyRepeat 节奏持续提交新的随机跳转；命令已接受并不等于新画面已稳定，长 GOP/高码率媒体会反复中断尚未完成的解码，表现为卡住或跳顿。
- 第一层调整：页面级物理 KeyDown 先保留短按意图；KeyUp 才提交唯一的关键帧跳转。收到首个“前进” `KeyRepeat` 后，取消尚未派发的预览，进入至少 2× 的连续播放快进并静音；松键后恢复原速度和音量，不持久化临时速度，也不追加随机或精确 seek。长按快退仍保持既有 latest-only 关键帧预览。
- 第二层根因：常规媒体展示可使用 `video-sync=display-resample` 与时间插帧；在高速播放时它们会等待显示节拍与参考帧。再叠加默认配置中的 `framedrop=no`，Flutter Texture 即使保留了解码链仍可能呈现停顿感。
- 第二层调整：新增可选 `PlayerFastForwardScanBoundary`。MediaKit 在同一个 `NativePlayer.lock` 内读取并保存真实倍速、`video-sync`、`interpolation`、`framedrop`、`audio-pitch-correction`；扫描期改为 `video-sync=audio`、关闭插帧、`framedrop=vo` 与关闭保音调滤镜，并在该锁内读回验证，松键或换片前按安全顺序恢复并验证。任何旧属性无法完整读回、扫描档位未确认或恢复不匹配时只使用临时倍速，禁止猜测默认值或覆盖用户呈现配置。
- 依据：mpv 官方明确 `exact` seek 需要从先前关键帧解码、可能耗时；`keyframes` 是快速跳转模式。其文档还把 `framedrop=vo` 定义为推荐模式，指出 decoder 级丢帧不可预测、可能导致卡顿或冻结；`display-*` 同步模式在中断后也可能丢弃应显示的帧。因此长按快进既要保留连续解码链，也要临时移除只适用于常速的显示同步压力。
- focused 回归覆盖页面短按只有 KeyUp 的一次预览、长按前进零随机 seek、专用扫描档位优先于普通倍速、松键恢复，以及服务专用/回退边界；位置栅栏和快捷键门禁保持覆盖。

## 2026-08-17 · 普通启动首帧与精确恢复解耦

- 现象：媒体库点击新视频进入播放器后，`open(play: false)` 仍先等待清滤镜、画质/呈现属性和完整打开门禁，首帧出现前有明显等待。
- 调整：无有效恢复点的媒体在事件重绑后立即显式 `play()`，播放就绪状态先解除打开占位；损坏媒体检测和画质属性收敛仍在同一串行
  worker 尾部执行，避免与下一次 `open` 并发。
- 继续观看及“每次询问”候选仍先完成有界可播放性检测、画质属性收敛，再通过 `seekExactlyWithDiagnostics` 精确恢复；重播和无效旧进度
  不被误判为精确恢复场景。
- focused 回归覆盖播放就绪不结束 worker、普通启动先播放后收敛属性和原有 MediaKit `play:false` 后显式播放契约。

## 2026-08-17 · 短按快进恢复单次关键帧预览

- 现象：短按快进先完成关键帧预览，松键又追加一次绝对精确 seek；长 GOP 视频因此重新建立解码链，产生明显停顿。
- 调整：`PlayerKeyboardSeekController` 的 KeyUp 只等待并收敛当前关键帧预览，移除短按专用的 `exactSubmit` 和
  `short_exact_seek_*` trace；短按与长按都不在同一次输入中追加第二次 seek。
- 精确定位仍由 `seekExactlyWithDiagnostics` 独立服务进度条提交与继续观看恢复，不改变 `PlayerBackend`、播放会话或来源 filtered queue。
- focused 回归覆盖短按只提交一次预览、长 GOP 预览落回原关键帧时不追加精确 seek，以及独立精确入口仍挂载。

## 2026-08-16 · 普通属性/诊断超时与健康/NVIDIA 交叉身份

- `PlayerService` 与页面 `getMpvProperty()` 对普通 native 属性读取增加统一超时；内存阶段日志逐项读取也有界，
  释放协调器对事件取消和诊断阶段设置独立上限，stop 失败进入 `releaseFailed`/失败阶段。
- 健康采样在每次属性 await 后校验 `videoId + mediaGeneration + requestRevision`；NVIDIA 探测、联合滤镜、驱动
  状态轮询、CPU 回滚和用户设置入口统一传入当前 task context。
- focused 回归新增普通属性超时、事件取消/诊断日志卡住、stop 失败状态，以及“旧媒体采样完成后切换新媒体”交叉门禁。
- 真实 Windows 窗口验收已通过最新 Debug 包：短按 `L` 快进后画面和进度继续前进；全屏播放列表单击第二项可更新
  选中态；退出播放器返回媒体库后重新进入可正常重建普通播放器、队列和 Texture。验收未改变 schema、筛选语义或来源 filtered queue。

## 2026-08-16 · native 命令超时、释放失败与 GPU 异步身份

- 对抗式检查发现 native seek 无边界会让同一尾链上的后续 open/stop 永久等待，且 Dart `Future.timeout` 本身不会取消底层调用。
  `PlayerService` 现在只对已派发命令计时；超时后封锁当前服务代次，尚未派发命令立即失效，禁止并发触碰旧 Player。
- 资源协调器对事件取消、`dispose`、`released` 分阶段限时并保留失败阶段；失败时记录 `player_release_failed`，Route 协调信号仍只表示释放尝试结束。
- GPU 能力探测支持总超时和取消检查；GPU/NVIDIA/健康回滚/超分结果统一绑定 `videoId + mediaGeneration + requestRevision`，不再用 mutable path 作为主要保护。
- 播放错误走安全 stop；退出等待 `maybePop()` 并在被拒绝时恢复 `isExiting`，避免停留在不可交互页面。
- 直接 focused 回归覆盖命令超时不并发、释放两段超时、GPU 总超时/取消和稳定身份源码合同。

## 2026-08-16 · 全屏筛选结果队列 airspace 覆盖回归

- 现象：全屏模式打开筛选结果队列后，显式 child HWND 路径仍可能由原生视频表面覆盖列表或抢走点击命中。
- 根因：全屏队列虽已挂在 Flutter 根 Stack，显示/隐藏却没有接入既有 `PlayerOverlaySurfaceBoundary` 裁剪合同，
  且快速显隐时原生裁剪命令可能乱序完成。
- 修复：按队列右侧实际矩形串行提交裁剪，等待原生让出后再挂载 Flutter 侧栏；隐藏和全屏切换恢复完整表面，
  菜单/设置弹层优先于全屏队列；过期显示请求不再把旧侧栏写回页面。截图测试同步到当前“不压缩视频宽度”的覆盖层语义。
- 保护：默认 MediaKit Texture、来源 filtered queue、当前序号、播放会话和视频尺寸不变。

## 2026-08-16 · 短按快进关键帧回退

- 现象：单次按下快进偶发先显示前进目标，随后回到原点；长按因为连续发送多个预览目标反而能继续前进。
- 根因：短按只使用 `absolute+keyframes` 交互式 seek，长 GOP 的目标前关键帧可能就是当前落点；目标栅栏
  只能保护 UI 状态，不能把后端实际关键帧变成精确目标。
- 修复：键盘控制器区分 `KeyRepeat`；短按 KeyUp 在预览完成后补一次精确 seek，长按仍只走 latest-only
  关键帧预览，避免每个重复事件堆积绝对 seek。
- focused 回归模拟 25 秒目标落到 20 秒关键帧的情况，确认短按最终稳定在 25 秒。

## 2026-08-16 · 播放器列表删除返回后的媒体库刷新时序

- 现象：播放器右侧队列删除视频并返回主界面后，旧视频仍停留较长时间才消失。
- 根因：播放器返回后的删除差量刷新位于原生资源释放、最多 15 秒等待、内存采样和播放进度刷盘之后；
  主界面虽已恢复显示，查询结果仍未收到已提交的 stable `videoId` 删除差量。
- 修复：Route 弹回并恢复媒体库语义后立即调用播放器差量发布，继续复用
  `LibraryQueryController` 的 stable-ID 局部查询和延后计数刷新；资源释放与刷盘仍在后续尾部完成。
- focused 回归固定“删除差量发布早于 release wait”，防止后续把可见状态再次放回资源释放尾部。

## 2026-08-16 · seek 位置回跳竞态

- 根因：后端 seek 命令返回后，命令前已排队的 `time-pos` 位置事件仍可能迟到；精确与交互式
  seek 也可能从两条独立 Future 同时进入后端，旧完成结果覆盖最新目标。
- 修复：`PlayerService` 统一串行执行两类 seek；新增短暂目标栅栏，确认窗口内将迟到旧位置投影为
  最新目标，确认超时后才回退实际后端位置。`PlayerBackend` 方法签名、来源 filtered queue 和
  播放/暂停意图不变。
- focused 回归覆盖“新目标后旧位置事件”和“精确/交互式 seek 交错”两种顺序。

## 2026-08-07 · click → seek → native-rendered-frame 时间线

- 进度条交互式 `PlayerSeekCoordinator` 在同一 `Stopwatch` 下记录 `seek_submit_start`、`seek_command_complete` 与首个帧号变化；原生 Texture 证据写为 `native_rendered_frame`，兼容回退写为 `presented_frame_fallback`，并输出 `seek_to_frame_us`。
- 首帧观测在后台只保留最新目标，不能阻塞下一次 latest-only 派发；该诊断不扩大命中区、不改变音频门禁、播放意图或来源 filtered queue。

## 2026-08-06 · 进度条连续点击响应

- 鼠标进度条点击复用页面级 latest-only `PlayerSeekCoordinator`：首个目标立即提交，后续快速点击替换尚未下发的目标，禁止每个点击进入新帧确认和音频恢复的串行等待。
- 进度条继续保留本地乐观目标以防位置流回写造成滑块回弹；继续观看和其它精确定位仍使用原有精确 seek 与音频门禁。

## 2026-08-04 · 媒体轨道、章节与同步校正

- 审计仅纳入适合本地发现播放器的能力：内嵌音轨选择、字幕选择/关闭、字幕延迟、音频延迟与章节定位；不纳入 mpv 内部播放列表、watch-later、网络录制、脚本/OSD、A-B 或逐帧等专业播放器扩展。
- `PlayerMediaControlsBoundary` 为可选平台扩展。`PlayerService` 只转发强类型意图；MediaKit 在当前 `NativePlayer` 上调用类型化轨道 API，并按需读取 libmpv 章节节点，绝不创建第二个播放器、解码链或队列。
- 新增快捷键不得替换现有绑定：`#`、`v`、`z/Z`、`Ctrl++/Ctrl+-` 与 `g-a/g-s/g-c` 仅在未被配置动作占用时处理；既有 `J/L`、`PageUp/PageDown` 保持原有 seek/来源队列语义。

## 2026-08-04 — 键盘 seek 恢复连续播放

- 同一条本地样本的无内容泄露图形帧差分复现了旧路径在短按后约 0.4 秒的静止窗口；trace 同时证明 MediaKit Texture 使用 `estimated-frame-number` 回退，不能把它宣称为最终屏幕呈现。
- 键盘短按先立即提交关键帧预览且不临时静音，KeyUp 再补一次 absolute 精确 seek；KeyRepeat 进入的长按继续 latest-only、GOP 自适应节流与临时静音，KeyUp 不重复绝对 seek。进度条点击走交互式 latest-only 路径，精确恢复入口仍单独定位。
- Debug 窗口实际回归：新路径 trace 为 `key_up → keyframe_seek_complete`，没有 `exact_seek_start`；短按后的帧差分连续，系统音频保持正常范围。实体键盘长按仍需在后续验收时人工复核，自动化不能伪造 KeyRepeat。

## 所有权

- `PlaybackSession`、PlayerPage 和来源 filtered queue；
- `PlayerService` / `PlayerBackend` 及可选平台扩展；
- 播放切换、seek、全屏、控制显隐、队列和只读诊断；
- Windows native 后端的显式 QA 边界。

## 必须保持

- 右侧队列只来自来源筛选结果，不回退全局媒体库；
- 二级标签切换留在来源语境，返回媒体库保留筛选；
- generation/cancellation 防止旧 open/seek 覆盖新请求；
- 长按前进在首个 `KeyRepeat` 后必须转为临时连续高速播放，松键恢复用户原速度；不得继续反复随机 seek。
  长按快退继续累计逻辑目标并使用 keyframe latest-only 预览；
- 快退连续预览保持 latest-only 合并、受限重复步长和约 64ms 默认刷新预算；当前会话检测到
  关键帧 seek 解码压力时自适应降至 96/125ms，反馈合并到同一节奏，禁止每个 KeyRepeat 都重建完整播放器页面；
- 单次方向键先只建立 5 秒目标，KeyUp 只关键帧跳转一次；进度条点击只提交交互式 latest-only 目标，禁止同一次输入堆积多个 seek；
- seek 延迟以真实 MediaKit Texture 的 1080p/4K、H.264/HEVC/AV1、短/长 GOP 矩阵门禁为准，
  不根据请求参数推测解码路径，也不以单次主观观感取代 p95 结果；
- MediaKit Texture 是正式默认，native mpv/child HWND 只显式 QA；
- 用户播放/暂停意图、current index 和进度不因诊断/反馈重建；
- 控制、隐藏进度、设置和队列入口有页面级挂载与真实可达证据。
- 播放器打开前暂停共享的后台媒体详情新任务，并通知媒体库 Route 级相似视频 controller 进入播放态；
  播放器释放后只恢复进入前未暂停的任务，不能覆盖用户原本的暂停状态。相似扫描 Future 不因页面离开
  被取消，播放器期间只降低/冻结其取帧调度。

## 非目标

- 不把临时连续快进扩展为用户可持久化的倍速、逐帧或专业播放器功能；关键帧预览期间只临时静音，绝不暂停视频时钟；KeyUp 的精确位置确认且新视频帧已交付后才恢复原音量。

不把 NVIDIA/NVOFA 实验宣传或自动晋级为生产能力，不优先专业播放器功能。

历史：`docs/history/chat/CHAT_4_PLAYER_THROUGH_2026-07-30.md`。

## 2026-08-04 · seek 恢复 trace

- `PlayerSeekAudioGate` 在一个临时静音会话内分配 trace id；`PlayerKeyboardSeekController` 在同一 id 下记录 `key_up`、`exact_seek_start` 和 `exact_seek_complete`。
- 精确 seek 返回后才采样最终帧基线；Windows 正式 Texture 路径优先等原生桥完成共享纹理复制的 `native-rendered-frames` 递增，非原生路径才回退 mpv `estimated-frame-number`，并在 trace 标出 `frame_evidence`。新视频帧或超时、以及音频恢复请求/完成继续写入同一 trace。`mono_us` 只用于会话内延迟，`wall_utc_ms` 只作为本地录屏起始时间的对齐锚点；两者不得混用为性能结论。
- 诊断不改变 preview latest-only 合并、音频静音策略、`PlayerBackend` 合约或来源 filtered queue。
