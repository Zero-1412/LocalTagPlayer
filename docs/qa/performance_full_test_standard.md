# Local Tag Player 压测与性能全测标准

## 1. 目的与适用范围

本文是 Windows 主基线的可重复性能、压力和稳定性门禁。目标是验证大型本地媒体库在
“扫描 → 标签筛选 → 当前过滤队列 → 播放 → 缓存/诊断”闭环中保持可用、可响应、可回收，
并为后续优化提供同机可比较的基线。

典型工作负载按约 11,000 个视频、8 TB 媒体库设计；实际运行时必须记录真实视频数、根目录数、
媒体所在磁盘类型、GPU、显示器缩放和播放后端。本文不把 Local Tag Player 当作 PotPlayer、VLC
或专业视频工作站进行功能/性能比较。

本标准默认不修改用户媒体文件和正在使用的 profile。涉及增删目录、播放记录或数据库写入的
测试必须使用可丢弃 profile；真实媒体根只读使用。

## 2. 资料依据与统一原则

外部资料只作为测量方法依据，项目门槛以本文和已有专项门禁为准：

- [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance)：性能判断使用
  profile 或接近发布的构建；debug 模式不能作为最终性能结论。
- [Flutter integration performance test](https://docs.flutter.dev/cookbook/testing/integration/profiling)：
  集成测试可保存 timeline/summary，便于跨版本比较。
- [Flutter Performance view](https://docs.flutter.dev/tools/devtools/performance) 与
  [CPU profiler](https://docs.flutter.dev/tools/devtools/cpu-profiler)：分别用于帧、UI/GPU、Dart CPU
  热点分析；分析时保留 profile 快照或 trace。
- [Windows Performance Recorder 基础诊断](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/recording-for-basic-system-diagnosis)：
  记录 CPU、磁盘 I/O、内存、进程/线程、硬故障等系统信号。
- [Windows 应用内存与磁盘性能分析](https://learn.microsoft.com/en-us/windows/apps/develop/performance/disk-memory)：
  短 trace 适合启动，数分钟长 trace 适合识别内存持续增长；用 WPA 打开 ETL。
- [FFprobe 文档](https://ffmpeg.org/ffprobe.html) 与 [FFmpeg benchmark 选项](https://ffmpeg.org/ffmpeg.html)：
  先确认媒体规格和实际工具输出，再解释解码、取帧或录屏结果。
- [Google SRE SLO](https://sre.google/sre-book/service-level-objectives/)：性能指标保留
  P50/P95/P99 和长尾，不以平均值单独判定；并明确测量窗口、样本和错误。

统一原则：

1. 先测用户可感知的“首个可用结果/首帧/返回可操作”，再测命令返回和后台吞吐。
2. 所有延迟至少报告 P50、P95、P99、最大值和样本数；平均值只能作为辅助信息。
3. 冷启动、热启动、首次缓存、热缓存分开；不能把不同构建模式、后端、媒体库或显示器混算。
4. 性能回归比较同一台机器、同一 profile、同一媒体样本和同一 renderer/backend；跨机器只比较
   结构性结论，不宣称绝对性能承诺。
5. 每个结果必须能回到阶段、seed、构建 commit、环境、原始日志和汇总 JSON/CSV；失败保留原始现场。

## 3. 测试环境与样本契约

每次全测开始前写入报告：

| 类别 | 必填字段 |
| --- | --- |
| 构建 | commit、版本、Flutter/Dart 版本、构建模式、是否 profile/release、是否带本地改动 |
| Windows | Windows 版本、分辨率、DPI、显示器数量、缩放比例、电源模式 |
| 硬件 | CPU 型号/核心数、内存、GPU/驱动、系统盘和媒体盘类型/剩余空间 |
| 应用 | 播放后端、实际硬解路径、renderer、数据库视频数/标签数/root 数、缓存冷/热状态 |
| 样本 | 12-case seek 矩阵 manifest、随机 seed、真实媒体根是否只读、异常媒体数量 |
| 干扰 | 录屏、WPR、杀毒扫描、同步盘、浏览器/编译器等后台活动；有则必须注明 |

媒体样本至少覆盖：

- 真实大库：约 11,000 视频，验证加载、排序、标签计数和筛选队列；
- 播放矩阵：`1080p/4K × H.264/HEVC/AV1 × short-GOP/long-GOP` 共 12 例；短 GOP 最大关键帧
  间隔不超过 1.1 秒，长 GOP 不少于 4 秒；
- 播放稳定性样本：至少 3 段真实片源，覆盖不同码率/运动量；
- 异常样本：不可读、0-byte、不完整缩略图或缺失路径，仅用于验证失败可见、可重试和不阻塞。

涉及用户数据库的测试：先复制到独立目录并设置 `LOCAL_TAG_PLAYER_DATA_DIR`；不得让 benchmark
或压力测试直接打开用户当前 profile。测试结束后核对 profile 中的 stable `videoId`、标签来源、
收藏、播放记录和路径状态没有非预期变化。

## 4. 门禁分层

| 层级 | 何时运行 | 最小内容 | 结论 |
| --- | --- | --- | --- |
| L0 静态门禁 | 每次相关修改 | `flutter test`、`flutter analyze`、`flutter build windows --debug` | 失败即停止，不进入性能比较 |
| L1 交互 smoke | 媒体库、标签、排序、搜索、播放器 UI 修改后 | 主窗口语义压测 + 标签切换 10 轮 + 关键入口真实点击 | 入口/状态/返回路径不能坏 |
| L2 基准门禁 | 性能优化、扫描/缓存/播放链路修改后 | 加载、全量/索引扫描、帧、seek 12-case、后端稳定性 | 同机基线回归不超过预算 |
| L3 全测 | 发布前、连续多轮优化后或用户要求的“一次全测” | L0–L2 + 隔离目录增删压力 + 30 分钟播放器长跑 + 内存/资源尾部 | 生成完整报告，硬失败不得发布 |

debug 构建可用于功能和崩溃检查；L2/L3 的时间、帧、资源结论必须优先来自 profile 或 release-like
构建。若现有 runner 只支持 debug，应把该结果标为“探索性/不可作为发布性能结论”，不得伪装成 profile 门禁。

## 5. 指标与初始门槛

以下是同一硬件、同一媒体库的初始预算。第一次全测用于建立正式基线；后续可在有结果和根因记录时
校准，但不能通过放宽阈值掩盖回归。

### 5.1 硬失败条件

- 应用崩溃、窗口丢失、测试进程异常退出、持续无响应超过 5 秒，或任一阶段超时。
- 标签来源、层级、筛选语义、结果数、filtered queue、当前序号或返回筛选状态发生错误。
- 播放器回退到全局媒体库队列；播放记录、收藏、manual 标签或 stable identity 非预期改变。
- 真实媒体根被写入、移动、删除，或测试未使用隔离 profile。
- 有效媒体反复无法首帧/无法播放；诊断 timer、异步 callback 或 FFmpeg/FFprobe 子进程在页面释放后泄漏。
- 长跑中出现持续增长且无法解释的工作集/私有内存、句柄或线程；或测试结束后资源未回到可接受尾部。

### 5.2 用户可感知延迟与帧

| 场景 | 初始目标 | 硬门槛/说明 |
| --- | ---: | --- |
| 冷启动到主窗口可操作 | P95 ≤ 10 s | 同一机后续版本相对基线不得增加 >15% 且不得增加 >1 s |
| 热启动到主窗口可操作 | P95 ≤ 5 s | 数据库加载、首屏列表和标签计数分阶段记录 |
| 标签/搜索/排序首次可见结果 | P95 ≤ 500 ms，P99 ≤ 1 s | 先判定视频结果更新；计数和缩略图延后不算失败 |
| 本地 root 进入/返回 | P95 ≤ 1 s | 不允许全局媒体库回退或筛选状态丢失 |
| 正常滚动/展开/队列操作帧总时长 | P95 ≤ 16.7 ms | 以 60Hz 为默认基准；同时报告 build/raster |
| 正常交互慢帧 | `>33.3 ms` ≤ 1% | 单次 `>100 ms` 需解释；连续卡顿为失败 |
| 扫描期间事件循环间隙 | 目标 P95 ≤ 50 ms | P95 >100 ms 或界面持续不可操作为失败；报告 max |

帧门槛只对有足够样本的交互阶段计算；启动单次长任务不得与稳定滚动帧混算。120Hz 显示器可
附加记录 8.3ms 预算，但不替换默认 60Hz 结论。

### 5.3 库加载、扫描、缓存和资源

| 领域 | 必须记录 | 初始门槛 |
| --- | --- | --- |
| SQLite/首屏 | `totalMs`、各 stage、视频/标签/关系数量 | 同机 P95 相对基线 ≤ +15%；数量断言必须通过 |
| 全量扫描 | 目录遍历、stat、指纹、commit、entries/s | 不阻塞 UI；结果数量和 missing/added/modified 正确 |
| 稳态差量扫描 | indexed scan、commit、无变化数量 | 不重复重建所有标签/缩略图；同机 P95 ≤ 基线 +15% |
| 缩略图/媒体详情 | queued/active/completed/failed、首屏可见成功率 | 有效样本不无限重试；失败可见；0-byte/不完整 JPEG 不算命中 |
| 进程资源 | CPU、working/private set、线程、句柄、I/O、GPU 显存 | 分阶段记录 median/P95/max；browse idle 不应持续 CPU 饱和 |
| 30 分钟尾部 | 最后 5 分钟 median 对 warm-up 后 5 分钟 median | 工作集/私有内存增长目标 ≤10%，硬门槛 ≤20% 且不得出现单调无界增长 |

CPU/GPU 绝对数值随解码器和媒体规格变化，除“空闲/浏览持续饱和”外，统一以同机同后端基线
比较。4K 软件解码与硬解必须分开报告。

### 5.4 播放与压力

- seek 使用现有 [player seek latency matrix](./player_seek_latency_matrix.md) 的 12 例和 manifest
  规则；每例 2 次预热后采 7 次，按 case 的 p95 budget 判定，不跨 codec/GOP 合并。
- 双后端稳定性矩阵默认每后端至少 18 次快速切换、30 分钟长播、6 次全屏往返；最大掉帧预算
  由 runner 参数和当次报告声明，不能只看“测试退出码为 0”。跨 DPI 分为两种证据：
  `simulated-single-monitor` 运行 100%/125%/150%/200%/100% 的 Flutter metrics、Surface
  重算和状态机验证，发布状态标记为 `passed-simulated-cross-dpi`；只有实际不同缩放屏幕移窗
  才能标记 `passed`，不能把模拟证据写成物理跨屏通过。默认对照为 MediaKit Texture 与
  原生 MPV Texture；需要定位呈现链路时，才显式传入 `-Backends mediaKit,hwnd` 比较
  正式 Texture 与 QA-only child HWND。后者不得作为 Release 排名、默认后端或产品能力声明。
- runner 同时写入 `displayInventory`：每块屏的边界、原生分辨率、Windows 当前刷新率和逻辑
  DPI。该字段的 `physicalCrossDpiEvidence.evidenceKind` 固定为
  `display-inventory-only`，只用于确认测试环境确实是 4K/高刷新率和记录 DPI；
  `physicalWindowMoveConfirmed` 在自动矩阵中保持 `false`，不能由显示器 inventory 推导出
  “窗口已经跨屏”或“全屏合成压力已通过”。
- 真实媒体库播放器随机压力默认 1,800 秒、固定 seed；覆盖随机打开、队列滚动、两次 seek、全屏
  往返、诊断和返回媒体库。至少有 1 个 cycle，且无崩溃、无卡死、无错误播放器页面残留。
- 隔离 profile 的增删目录压力默认 10 cycles，覆盖 add/scan/scroll/play/seek/diagnostics/release/remove；
  结束后视频数、root 数和关键数据库计数回到基线，release tail 默认 60 秒。
- 播放诊断必须记录真实首帧、停滞、AV offset、掉帧和后端；不能按请求的 `hwdec` 或设置值推断实际硬解。
  双后端报告还必须写出 `qaSeekFrameObservation`：它汇总页面开始观察新帧后的 p50/p95 与超时数，
  但不是按键/拖动到桌面像素变化的完整时延；正式 Texture 回退帧号和 HWND 的 visible+帧号代理必须
  显式保留 evidence，不能冒充屏幕级首帧。

## 6. 一次 L3 全测的固定执行顺序

顺序固定是为了把确定性失败和长时间资源问题分开：

1. **冻结环境**：关闭无关高负载任务，记录第 3 节环境字段、commit、seed、profile/backend、DPI；
   确认真实媒体根只读、隔离 profile 可丢弃、输出目录不存在且不会覆盖旧证据。
2. **L0**：运行 `flutter test`、`flutter analyze`、`flutter build windows --debug`；失败只记录，不进入
   性能优化结论。
3. **库加载/扫描**：在复制的数据库 profile 上运行 `library_load_benchmark_test.dart` 和
   `library_scan_benchmark_test.dart`，分别保存首屏、标签计数、全量扫描、indexed scan、commit 和
   event-loop gap JSON。
4. **主窗口 L1**：执行 `main_window_latency_smoke.md` 的 10 轮标签/搜索/排序/路径采样和
   `main_window_semantic_stress_gate.md`；真实点击确认入口可达、结果更新、返回和截图状态。
5. **播放器专项**：运行 12-case seek matrix，再运行双后端稳定性矩阵；硬解/软件回退、掉帧、停滞、
   首帧和 queue/source 证据分开保存。
6. **隔离目录压力**：运行 `tool/run_library_add_remove_player_stress.ps1`，显式传入只读 `-RootPath`、
   真实 profile 副本、`-Cycles 10`、`-ReleaseTailSeconds 60`，保留失败现场。
7. **真实库长跑**：运行 `tool/run_player_real_library_stress.ps1 -Profile -DurationSeconds 1800`；
   记录阶段帧 summary、process-metrics、latency-summary 和关键阶段截图。成功也至少保留汇总文件。
8. **资源尾部与系统 trace**：比较 warm-up 与最后 5 分钟资源；只有出现回归、长尾异常或内存增长时，
   追加 5–10 分钟 WPR/WPA trace，避免把诊断采样开销混入所有基线。
9. **收口核对**：检查应用进程退出、FFmpeg/FFprobe 无孤儿进程、输出 artifact 完整、隔离 profile 可删除、
   用户 profile 和真实媒体根未被访问写入；再汇总 Pass/Warning/Fail。

建议命令骨架（路径和 manifest 必须由执行者显式替换，不能把下面的占位符直接执行）：

```powershell
# 性能测试必须使用隔离 profile；真实库只读。
$env:LOCAL_TAG_PLAYER_DATA_DIR = '<可丢弃 profile 的绝对路径>'
$env:LOCAL_TAG_PLAYER_LOAD_BENCHMARK = '1'
$env:LOCAL_TAG_PLAYER_LOAD_BENCHMARK_OUTPUT = '<artifact>\library-load.json'
flutter test test/library_load_benchmark_test.dart

$env:LOCAL_TAG_PLAYER_SCAN_BENCHMARK = '1'
$env:LOCAL_TAG_PLAYER_SCAN_BENCHMARK_OUTPUT = '<artifact>\library-scan.json'
flutter test test/library_scan_benchmark_test.dart

Remove-Item Env:LOCAL_TAG_PLAYER_LOAD_BENCHMARK -ErrorAction SilentlyContinue
Remove-Item Env:LOCAL_TAG_PLAYER_SCAN_BENCHMARK -ErrorAction SilentlyContinue
Remove-Item Env:LOCAL_TAG_PLAYER_DATA_DIR -ErrorAction SilentlyContinue

.\tool\run_player_seek_latency_matrix.ps1 `
  -Manifest '.\.local\qa\player_seek-latency-matrix.json'
.\tool\run_player_backend_stability_matrix.ps1 `
  -PhysicalCrossDpiStatus simulated -LongPlaySeconds 1800 -RapidSwitchCount 18
.\tool\run_library_add_remove_player_stress.ps1 `
  -SourceProfile '<真实 profile 的只读复制源>' `
  -RootPath '<只读真实媒体根>' -Cycles 10 -ReleaseTailSeconds 60
.\tool\run_player_real_library_stress.ps1 `
  -Profile -DurationSeconds 1800 -Seed 20260815
```

## 7. 报告格式与裁决

每次全测产出一个不含用户文件名、完整路径或标签内容的 `summary.json`，并附原始日志路径。报告至少包含：

```text
run_id / generated_at / commit / build_mode / seed
machine / windows / display_inventory / display_dpi / refresh_rate / gpu / renderer / backend
library_counts / cache_state / sample_manifest
scenario / samples / p50_ms / p95_ms / p99_ms / max_ms
frame_build_p95 / frame_raster_p95 / frame_total_p95 / over16 / over33
cpu / working_set / private_bytes / threads / handles / io / gpu_memory
errors / hangs / dropped_frames / stalls / orphan_processes
baseline_id / delta_percent / status / evidence_paths / notes
```

裁决分三类：

- **Pass**：硬失败为 0，专项门禁通过，关键预算满足，证据完整。
- **Warning**：功能和稳定性通过，但某项只有探索性/debug 数据、真实跨 DPI 未执行、WPR 未采集或
  第一次全测尚未建立可比较基线；必须写明后续补测，不得标成完整发布通过。
- **Fail**：任一硬失败、用户数据/媒体根风险、queue/filter 语义错误、持续资源泄漏、关键 p95 超预算
  且无批准的基线变更说明。

优化判定至少满足以下两项：同机同样本关键 P95 改善 ≥10%；重复批次方向一致；CPU/内存/I/O 没有把成本
转移到另一条用户路径；所有硬失败和既有行为清单仍为 0。否则只记录为“未证实优化”，不进入正式基线。

## 8. 现有仓库入口映射

| 标准项目 | 现有入口 |
| --- | --- |
| 标签/路径 L1 | `docs/qa/main_window_latency_smoke.md`、`docs/qa/main_window_semantic_stress_gate.md` |
| 大库加载 | `test/library_load_benchmark_test.dart` |
| 全量/差量扫描 | `test/library_scan_benchmark_test.dart` |
| 播放 seek | `tool/run_player_seek_latency_matrix.ps1`、`docs/qa/player_seek_latency_matrix.md` |
| 双后端稳定性 | `tool/run_player_backend_stability_matrix.ps1` |
| 增删目录压力 | `tool/run_library_add_remove_player_stress.ps1` |
| 真实库播放器长跑 | `tool/run_player_real_library_stress.ps1` |
| 进程资源汇总 | `tool/summarize_player_stress_metrics.ps1` |
| 脚本登记 | `tool/qa/manifest.json` |

本标准不新增脚本，因此不修改 `tool/qa/manifest.json`。以后新增 runner、移动 runner 或改变 artifact
契约时，必须同时更新 manifest、本文件和对应 dated QA 证据。
