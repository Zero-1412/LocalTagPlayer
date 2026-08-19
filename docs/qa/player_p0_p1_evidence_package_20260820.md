# 播放器 P0/P1 证据包与外部验收清单

本文件把“播放器体验”拆成可停止、可复现的证据合同。它不改变播放器默认后端、
PlaybackSession、来源 filtered queue、标签筛选、缩略图/媒体详情队列或用户数据。

## 阶段 A：P0 本机真实性能证据包

### 固定条件

- 构建：Windows Debug；报告必须记录可执行文件 SHA-256。
- 正式输出：mediaKit-texture，即正式 MediaKit PlayerPage 的 Texture 路径。
- 素材：本机匿名 manifest，路径只保留在未跟踪 .local/qa/，不得提交仓库。
- 内容覆盖：1080p/4K × H.264/HEVC/AV1 × short-gop/long-gop，正好 12 个 case。
- 交互覆盖：每个 case 预留 startup、shortForward、shortBackward、drag、
  longForward、longBackward、fullscreen 七个 action。
- 独立性：每个有效 action 至少 3 个独立会话；失败会话保留但不得进入 p50/p95。
- 延迟终点：第一个真实 DWM/桌面合成变化。time-pos、命令完成、后端帧号、
  estimated-frame-number 或 Texture 复制回执都只能作为分段诊断，不能替代该终点。
- 稳态分母：每个已有素材 case 另跑至少 3 个独立 Debug PlayerPage/Texture 会话，
  每次正式播放窗口至少 10 秒；稳态 decoder/VO/total drop、硬解、Texture 代次/重建和
  释放证据不能挂到某个动作窗口，也不能替代首个真实 DWM 帧。

本机 manifest 可从 [tool/qa/player_p0_manifest.template.json](/E:/LocalTagPlayer/tool/qa/player_p0_manifest.template.json)
复制到 .local/qa/ 后填写。每个 case 的 path、编码、尺寸、GOP 分类和预算必须与
ffprobe 实际结果一致；12-case seek 运行器仍由
[tool/run_player_seek_latency_matrix.ps1](/E:/LocalTagPlayer/tool/run_player_seek_latency_matrix.ps1)
执行素材和 GOP 校验。

也可以用只读资料库生成器建立候选 manifest。Windows CLI 需要把仓库内的 SQLite
运行库放入当前进程 PATH；生成器对每个候选和整个探测批次都有上限，超时/缺失只记
partial/unknown，不会等待无限长的媒体扫描：

~~~powershell
$env:Path = (Join-Path (Get-Location) 'windows\tools\sqlite') + ';' + $env:Path
dart run tool/generate_player_p0_manifest.dart -Output .local\qa\player_p0_manifest.json -MaxCandidates 24 -MaxProbes 144 -ProbeTimeoutSeconds 20
~~~

探测预算按六个 `resolution-codec` bucket 轮询，并在每个 bucket 内均匀抽取首尾/中间候选，
避免热门编码或资料库时间排序先耗尽全局预算；ffprobe
在单个有界的首段 30 秒窗口内读取 packet 关键帧标志，不为素材枚举完整解码帧，manifest
中的 `selection.candidateCounts` 只记录每个 bucket 的数量，不写路径或媒体标识。
`selection.probedGopCounts` 进一步记录 packet 校验成功的 short/long 数量，区分“候选存在但
GOP 不符合”与“没有机会探测”。
`selection.probeOutcomeCounts` 再区分 `probe-failed`、`gop-outside-target` 和已分类的
short/long；因此 GOP 落在 `1.1s` 与 `4.0s` 之间时保持 case 缺失，不会被误写成短 GOP。
因此 `maxProbes=144` 至少会给每个有候选的 bucket 24 个均匀抽样机会，同时仍然是有限门禁。

生成器若发现默认 Debug 可执行文件，会把其 SHA-256 写入 manifest；找不到时保留空值，
由验证器判为 `unknown`。本机首次有限探测结果为 `partial`，已选 `2/12`、缺少 `10`、实际探测 `6` 个候选；
已确认的两个样本是 1080p H.264 长 GOP `5.27s` 和 4K H.264 短 GOP `1.00s`。
由于本轮设置了全局 probe 上限，这个结果只证明 manifest 生成链可用，不能证明其它
编码/分辨率没有样本；未补齐前 12-case 覆盖继续记 `unknown`。

最新 `24/144` 有界扫描已选 `10/12`；缺口为 `1080p-av1-short-gop` 和
`4k-av1-long-gop`。`probedGopCounts` 显示 4K AV1 资料库只有一个 short 候选；
1080p AV1 的另一个候选 packet 可读但关键帧间隔约 `2.00s`，落在目标 GOP 区间之外，
因此两个缺口仍保持 unknown。

补充的只读 root 文件树审计又检查了 `177` 个未索引媒体：其中只有 `1` 个 1080p AV1，
ffprobe 关键帧最大间隔为 `6.25s`，仍属于 long GOP；没有发现 4K AV1 未索引候选。
该审计不把未进入应用资料库的文件强行加入正式 manifest，但它排除了“本轮缺口只是
library.db 漏扫”的解释；两个缺口继续保持 `unknown`，不因额外扫描而伪造完整覆盖。

### 2026-08-21 · 受控 AV1 fixture 与素材范围隔离

为补齐本机报告的两个素材缺口，新增
[tool/prepare_player_p0_av1_fixture_manifest.ps1](/E:/LocalTagPlayer/tool/prepare_player_p0_av1_fixture_manifest.ps1)。
它只在新的隔离 `.local/qa/` 目录生成 30 秒 AV1 QA fixture，不修改源媒体；生成后重新用
ffprobe 校验 codec、分辨率、码率、时长和 packet 关键帧间隔。当前固定 Debug/Texture manifest
为 `player-p0-av1-fixtures-20260821f`：1080p AV1 short GOP 的关键帧间隔为 `1.001s`、
码率约 `6326.2kbps`；4K AV1 long GOP 的关键帧间隔为 `5.0s`、码率约 `23483.5kbps`。
两个 case 的 `selectionStatus` 为 `qa-generated-fixture-and-ffprobe-verified`，
`selectionEvidence.sourceKind=controlled-local-qa-fixture`；fixture 路径不进入报告摘要。
这两个受控 fixture 只作为本机可复现的素材合同，不能外推为用户任意 AV1 文件的发布结论。

装配器现在对这两个 case 只接受目录名含 `-fixture-` 的完整三会话矩阵，拒绝把同 codec/
分辨率/GOP 的旧素材 action 证据冒充 fixture 证据。v2 装配结果为 `43` 个明确映射、
`41` 个 action omitted，12 个 case 的稳态目录均已绑定。两个 fixture 的正式 Texture 稳态均
为 `3/3` 有效、每轮约 `10s`、decoder/total drop 为 `pass`、最终硬解为 `d3d11va-copy`、
Texture 代次 delta 为 `0`、资源释放 `3/3`；VO drop 均为 `unknown`。

新增 fixture 的 startup 各为 `3/3` 有效，但 1080p short 的 DWM 首帧 p95 为约 `1265ms`、
4K long 为约 `2025ms`，按 `1000ms` 预算均为 `fail`。fullscreen 各为 `3/3` 有效，
几何完成 p95 为约 `46/45ms`；这只是窗口几何结构证据，视频首个真实 DWM 帧仍为 `unknown`。
1080p short drag 为 `3/3` 有效，Down→DWM p95 `307ms`、页面 Slider 语义和资源释放通过，
VO 缺失仍使 action overall 保持 `unknown`。当前 Debug 自动化 forward 的新复测（fixture 与
原始 1080p AV1 各 `3/3`）均没有 `player_keyboard_event` 或 DWM 变化，严格不生成 p95；
该输入链负证据只记 `unknown`，不修改业务快捷键路径，也不替代阶段 D 的实体 WM_KEYDOWN/UP。

统一 v2 门禁报告为
`.local/qa/player-p0-av1-fixtures-20260821f/p0-evidence-gate-v2.json`，validator exit `2`，
`overall=fail`（`11` 个 case fail、`1` 个 case unknown、`0` 个 case pass）。报告完整记录了
受控素材、三会话分母、真实 DWM 终点、Texture/资源释放和 unknown 边界；本机阶段不再因外部
GPU/驱动、实体键盘或另一渲染架构无限等待。

### 统一判定

[tool/validate_player_p0_evidence.ps1](/E:/LocalTagPlayer/tool/validate_player_p0_evidence.ps1)
只读取 manifest/匿名 QA 产物，并对每个 case/action 输出 pass、fail 或 unknown。
它不会把缺少字段、缺少 VO/逐帧时间戳、缺少 10 秒稳态分母、缺少真实 DWM 帧或缺少
实体 QPC 写成通过。

~~~powershell
# 只验证 manifest 结构，不读取媒体或 QA 产物
.\tool\validate_player_p0_evidence.ps1 -Manifest .\.local\qa\player_p0_manifest.json -ValidateOnly -Output .\.local\qa\p0-manifest-validation.json

# 读取 manifest 里 evidence 字段指向的匿名 QA 目录并生成门禁报告
.\tool\validate_player_p0_evidence.ps1 -Manifest .\.local\qa\player_p0_manifest.json -Output .\.local\qa\p0-evidence-gate.json
~~~

已有矩阵需要先通过
[tool/assemble_player_p0_evidence.ps1](/E:/LocalTagPlayer/tool/assemble_player_p0_evidence.ps1)
显式装配到一个新的本机 manifest；装配器不修改原始 manifest，也不按相邻目录或媒体路径猜测
case。它只接受目录名同时声明分辨率、编码、GOP 和动作，且摘要满足
`product-player-page`、`desktop-composited-pixel-change`、`p95Eligible=true`、至少三个
`valid` run 并且每个 report 文件存在的矩阵：

~~~powershell
pwsh -NoProfile -File .\tool\assemble_player_p0_evidence.ps1 `
  -SourceManifest .\.local\qa\player_p0_manifest.json `
  -OutputManifest .\.local\qa\player_p0_manifest-with-evidence.json `
  -EvidenceRoot .\.local\qa

pwsh -NoProfile -File .\tool\validate_player_p0_evidence.ps1 `
  -Manifest .\.local\qa\player_p0_manifest-with-evidence.json `
  -Output .\.local\qa\p0-evidence-gate-assembled.json
~~~

此前的装配结果为 `41` 个明确 case/action 映射、`43` 个保留未装配 action；其中包括
1080p H.264/HEVC short GOP 和三编码 long GOP 的正式 PlayerPage 精确拖动矩阵、三编码
short/long 的明确 forward/backward 矩阵、10 个有素材 case 的正式 PlayerPage fullscreen
矩阵、9 个有完整会话的正式 PlayerPage startup 矩阵，以及已有的 4K longhold 矩阵。没有精确 GOP
绑定的其它拖动、startup、fullscreen 不会因为目录“看起来相近”而被装配；4K AV1 short
的 startup 只有 `2/3` 有效会话，因此没有装配；缺失素材的 1080p AV1 short 与 4K AV1 long
也继续由原始 manifest 保持缺口。装配输出中的
`evidenceAssembly` 保存选择规则、已映射目录名和省略原因，便于同机复跑和审计。2026-08-21
受控 AV1 fixture v2 装配为 `43/41`；对于标记为 `qa-generated-fixture-and-ffprobe-verified`
的 case，只有目录名含 `-fixture-` 的证据才可进入该 case。

每个 action 的 evidence 是独立会话目录数组；目录可为包含
desktop-pixel-matrix-summary.json 的矩阵根，或单个 run 目录。报告至少应能追溯：

- DWM 首帧：desktop-composited-pixel-change、首帧延迟和后续匿名变化；
- 运行态：decoder drop、VO drop、total drop、最终硬解属性；
- Texture：generation、尺寸/重建事件和正式 Texture 身份；
- 语义：player_keyboard_event 或 Slider 回执；
- 资源：player_resources_released 或明确的释放失败；
- 稳态：独立至少 10 秒窗口及其分母。动作窗口里的 totalDropFramesMax=0 仍只能记
  unknown，不能代替稳态掉帧率。

统一校验器现在同时从每个 report 的 `presentedChanges[].qpcUs` 计算 DWM 后续呈现变化：
对 `longForward`/`longBackward` 输出连续变化间隔 p95、最大间隔和每轮变化数，并沿用
平滑度标准的 `p95≤50 ms`、`max≤100 ms`、每轮至少 `5` 个变化；对长按/拖动另输出
最长无变化段（`≤500 ms`）。字段不足只记 `unknown`，反向 latest-only 关键帧预览不因
存在若干变化而被写成连续反向扫描。

本轮新增 [tool/run_player_steady_runtime_matrix.ps1](/E:/LocalTagPlayer/tool/run_player_steady_runtime_matrix.ps1)
和正式 PlayerPage 的 `LOCAL_TAG_PLAYER_STEADY_RUNTIME_QA=1` Debug 入口。它只采样已有的
运行态快照，不启动 DWM 像素探针；矩阵摘要以 `backend-runtime-steady-window` 标记，
并将 `pass/fail/unknown` 保留在 decoder、VO、total 三个独立指标中。装配器把它放在
case 级 `evidence.steadyRuntime`，不复制到 startup、短按、拖动或长按 action。

当前 10 个已有素材 case 均完成 `3/3` 有效会话：实际窗口 `10001–10007 ms`，每轮
`21/21` 采样处于播放态、buffering `0`；decoder drop 与 total drop 均为 `pass`（每轮
`0→0`），VO drop 属性在本机为 `empty`，因此 10/10 case 均严格记为 `unknown`；最终
硬解均为 `d3d11va-copy`，Texture 代次 delta 均为 `0`，每轮均有资源释放回执。两个
manifest 缺口 `1080p-av1-short-gop` 与 `4k-av1-long-gop` 的 case 级稳态指标继续为
`unknown`。这组稳态证据只说明运行态分母在当前 Debug 机器上可复现，不把后端 total drop
提升为 DWM 无掉帧，也不改变启动首帧的 fail/unknown 结论。

因此，当前仓库的本机阶段结论是：

装配后的统一门禁报告为 `overall=fail`：12 个 case 中 `11` 个为 `fail`、`1` 个为
`unknown`、没有 case 为 `pass`。这表示证据链已经能够对已装配动作和 case 级稳态窗口
给出可复核的 `pass/fail/unknown`，但 P0 本机首帧/动作基线仍未通过；VO drop、未装配
动作和两个 manifest 缺口不能被这次装配覆盖。

本轮对统一 manifest 的正式 PlayerPage 1080p H.264 short forward 做了 3 个独立
Debug Texture 会话；打开、最终硬解和释放均有运行态证据，但没有页面键盘语义事件，
scan-code 与诊断用 virtual-key 两种输入注入都没有产生真实 DWM 像素变化。因此该轮
只保留为输入/可见性 `unknown`，不产生 p95，也不把后端打开成功误报为首个 DWM 呈现帧。

相邻 Slider 对照在同一正式 PlayerPage/Texture/QA 输出链上成功写出
`progress_slider_start/committed` 并形成单样本 DWM 变化。进一步开启默认关闭的自动化
native-route 诊断后，scan-code 与 virtual-key 都只得到 native `up`、没有 `down`；原生
焦点类别为 `FLUTTERVIEW`，但页面仍没有 `player_keyboard_event`。这说明当前失败位于
桌面 SendInput Down 或 Flutter Windows 消息投递链，不能归因于解码/Texture；诊断结果不具备
真人 WM_KEYDOWN/UP 资格，不进入实体输入或性能统计。

| 指标 | 当前判定 | 依据 |
| --- | --- | --- |
| 正式 Texture 三编码动作探针 | pass（证据管线） | 已有真实 PlayerPage、页面语义、DWM 匿名变化和运行态聚合 |
| 12-case 固定 manifest 完整性 | fail（10/12） | 当前本机有统一 ignored manifest，但两个 AV1 case 没有可验证样本 |
| 三编码/两分辨率/短长 GOP 的统一 P0 报告 | fail（11 fail/1 unknown） | 已装配 41 个明确 case/action；startup 目标全部失败或缺证据，连续呈现、未装配动作、稳态字段和 2 个素材缺口仍未闭环 |
| decoder drop | pass 或 fail 按 action 分列 | 运行态有值时非零失败；没有值不补零 |
| VO drop | unknown（已有矩阵多数不可用） | 运行态没有可靠 VO drop 字段时不能判通过 |
| case 级稳态 decoder drop | pass（10/12） | 10 个已有素材 case 各 3/3、独立至少 10 秒窗口；两个缺口 unknown |
| case 级稳态 VO drop | unknown（12/12） | 本机 `vo-drop-frame-count=empty`，不能按零处理 |
| case 级稳态 total drop | pass（10/12） | 10 个已有素材 case 的独立分母为 0→0；两个缺口 unknown |
| action 窗口 steady-total-drop | unknown | 动作窗口仍不具备 10 秒稳态分母，不能由 case 结果外推 |
| DWM 后续呈现节奏 | pass/fail/unknown 按长按 action 分列 | 由 `presentedChanges[].qpcUs` 计算；缺少连续变化序列不补成通过 |
| 首个真实 DWM 帧 | pass/fail 按已有 action 分列 | 只采用桌面合成像素报告 |
| P0 总体 | fail（阶段未完成） | 当前门禁没有 case 通过，且仍有 unknown；报告完整性尚未闭环 |

### 已有独立矩阵的补充评估

以下结果来自已有正式 PlayerPage/Texture 的独立矩阵，并通过
[tool/evaluate_player_smoothness_standard.ps1](/E:/LocalTagPlayer/tool/evaluate_player_smoothness_standard.ps1)
重新计算；其中只有目录名能精确绑定素材和 GOP 的结果才由装配器填入统一 manifest，
其它结果仍是支撑证据，不能替代每个 case/action 的三会话关联。

- 1080p 三编码的 shortForward、shortBackward、drag 矩阵各有 `3/3` 有效会话；其中
  H.264/HEVC short GOP drag 已用新目录精确绑定到对应素材；首个 DWM p95 分别为：
  H.264 `81/92/343 ms`、HEVC `86/94/307 ms`、AV1 `86/93/362 ms`。
  页面语义、decoder drop 和最终硬解在这些矩阵中为 `pass`；VO drop、独立稳态分母和
  稳态 Texture 重建仍为 `unknown`，所以矩阵整体不能写成通过。
- 1080p longForward 的首个 DWM p95 为 H.264 `75 ms`、HEVC `99 ms`、AV1 `1105 ms`；
  H.264/HEVC 的连续呈现节奏门禁为 `fail`，AV1 同时首帧与最长无变化间隔失败。
  longBackward 三编码首个 DWM p95 为 `271/281/263 ms`，连续扫描门禁均为 `fail`；
  这些结果继续区分“前进连续扫描”与“后退 latest-only 关键帧预览”，不宣称双向连续。
- 4K drag 的 H.264/HEVC/AV1 矩阵各有 `7/7` 有效会话，首个 DWM p95 为 `351/293/287 ms`，
  页面语义为 `pass`；部分运行态 decoder/hwdec 字段缺失，因此仍按 `unknown` 处理。
- 1080p 三编码的 long-GOP drag 也已用 manifest 素材精确完成 `3/3` 独立会话；首个
  DWM p95 为 H.264 `408 ms`、HEVC `517 ms`、AV1 `364 ms`，最长无变化段分别为
  `387/500/358 ms`。这些结果进入统一装配，但 HEVC 的 `500 ms` 仍处于最长静止阈值边界，
  VO drop 与稳态分母缺失时不改变 unknown 约束。
- 10 个 manifest 已有素材的正式 PlayerPage fullscreen 矩阵均完成 `3/3` 独立会话；
  fullscreen 的窗口几何完成只作为结构辅助证据，不能替代视频首个真实 DWM 帧。1080p H.264 short/long 为
  `45/47 ms`、HEVC short/long 为 `44/44 ms`、AV1 long 为 `64 ms`，4K H.264 short/long
  为 `44/50 ms`、HEVC short/long 为 `52/50 ms`、AV1 short 为 `50 ms`。validator 明确
  读取 `p95InputDownToGeometryMs` 作为独立的 `fullscreen-window-geometry-settled` 指标，
  不把像素字段的 0 ms 当成通过；fullscreen 的页面语义不是 seek 语义，视频首帧、Texture、
  资源和可见性字段仍单独保留 unknown。
- 正式 PlayerPage startup 现在已覆盖 9 个有可验证素材的 case，各完成 `3/3` 独立 Debug
  Texture 会话；窗口显示后、`runApp` 前写入 `startup-marker.json`，探针附着后才允许挂载页面，
  首个持续中心 DWM 变化使用同机 UTC→QPC 映射计时，随后再用 `ready.json` 验证产品页面可达。
  所有矩阵显式采用最低 `40 fps` 采样门槛，实测有效采样约 `66.8–118.3 fps`；在 Texture
  id + duration readiness 之后才接受中心像素变化。1080p H.264 short/long 的 startup p95
  为 `1257/2448 ms`，HEVC short/long 为 `1074/1035 ms`，AV1 long 为 `1106 ms`；4K
  H.264 short/long、HEVC short/long 为 `1134/1150/1136/1102 ms`；9 个均因 startup
  `1000 ms` 预算判 `fail`，资源释放和最终
  `d3d11va-copy` 均有回执。4K AV1 short 仅 `2/3` 会话有效而保持 unknown，缺失素材的
  1080p AV1 short 与 4K AV1 long 也保持 unknown；后端 `first_frame_ms` 不进入该指标。

阶段 A 在统一 manifest 的每个可运行 case/action 保留 3-session 结果、case 级稳态分母、
失败和 unknown 均可复核后达到本机停止条件；12-case 缺料、动作失败、VO unknown 和
首个 DWM 预算失败仍如实留在报告中，不因实体键盘、另一后端或外部 GPU 无限重跑。

## 阶段 B：P0 根因决策

### Texture 与 QA-only HWND

当前同机稳定性报告
.local/qa/current-texture-hwnd-matrix-20260819h/player-backend-stability-matrix.json
给出的可审计事实是：

- MediaKit Texture：全屏、队列、交互、模拟 DPI、快速切换和 10 秒长播通过；
  实际硬解为 d3d11va-copy，seekFailureCount=0，Texture generation delta 为 0。
- QA-only child HWND：布局/全屏/模拟 DPI/快速切换/长播可运行，但精确 seek 有
  2/18 未确认，首帧观察有 15 次超时；总门禁为 failed。

决策：HWND QA path publishability = fail，记录为“HWND QA 路径不可发布”。这不是
“HWND 黑屏所以 Texture 必然有根因”的推断；因为 HWND 自身没有满足同一首帧/精确 seek
验收，不能继续用它校准 Texture，也不能用它做 Release 排名或默认后端决策。只有后续
出现稳定、同素材、同动作、同 DWM 终点的 HWND 路径，才允许重新做公平 A/B。

### 反向 seek 语义

- 当前正式语义是 latest-only keyframe preview：目标合并、按帧让渡和最短 dwell
  只控制预览节奏，避免命令洪水。
- 它不是连续反向扫描，也不证明每个中间目标都在屏幕上呈现。
- QA-only play-direction=backward 实验三编码均为 no-sustained-backward-position，
  因此“连续反向解码”当前为 unknown，不能写成通过。
- 正向长按的临时连续播放与反向 latest-only 关键帧预览必须在报告中分开列名和指标。

## 阶段 C：P1 播放控制包

命令/资源 QA 和真实可见性 QA 分开记账：

| 能力 | 命令/资源 QA | 真实可见性 QA | 当前结论 |
| --- | --- | --- | --- |
| 短按 | 页面语义与 DWM 动作合同 | 首个真实 DWM 帧 | 已有 Texture action 证据，实体长按仍未闭环 |
| 拖动 | Slider onChangeEnd、latest-only 合并、释放 | 预览连续变化与松手准确收敛 | 命令合同已有；统一 P0 manifest 后再汇总 |
| 长按 | 前进临时扫描、后退 latest-only、KeyDown/Up 生命周期 | 按住期间 DWM 首帧和后续节奏 | 自动化已有；实体 WM_KEYDOWN/UP QPC 为 unknown |
| 可调倍速 | setRate、播放中状态/速度读回、恢复读回、资源释放 | 真实窗口播放节奏预算 | H.264/HEVC/AV1 各 3/3 pass（同一修复后 Debug 构建） |
| 逐帧 | frame-step/frame-back-step、错误和释放 | 前进、后退各自的真实 DWM 画面 | H.264 前进/后退各 3/3 pass；HEVC 两方向各 3/3 unknown；AV1 双向严格聚合 unknown；三组 command/resource 均 3/3 pass |
| A-B loop | A/B/实际 A→B→A 循环、清除命令、状态和释放 | A→B 重复播放画面 | H.264/HEVC/AV1 各 3/3 pass（同一修复后 Debug 构建） |
| 外挂字幕 | 加载/轨道/关闭命令和释放 | 字幕在真实 Texture 上可见并落入测试时间窗 | H.264/HEVC/AV1 各 3/3 pass（同一修复后 Debug 构建） |

“命令可用”不升级为“功能完成”。在可见性证据出现前，P1 只能报告命令合同通过和
可见性 unknown。

### Precision controls 的 DWM 可见性复核

新增 [tool/run_player_precision_controls_dwm_qa.ps1](/E:/LocalTagPlayer/tool/run_player_precision_controls_dwm_qa.ps1)
和 [tool/validate_player_p1_precision_evidence.ps1](/E:/LocalTagPlayer/tool/validate_player_p1_precision_evidence.ps1)，
它在同一正式 PlayerPage/MediaKit Texture Debug 会话中不发送输入，只读取 DWM 合成后的
中心视频网格和字幕下方网格，分别把命令 JSONL 与匿名桌面指纹 JSONL 落盘。它要求：

- `frame_step_complete` 与 `frame_step_backward_complete` 分别记录命令结果和前后 DWM 时间窗；
  前进、后退两个方向均必须有真实桌面变化，逐帧不接受估算帧号代理；
- `playback_rate_complete` 必须在真实播放状态读回 `speed=1.5`，并恢复原倍速且再次读回；
  该阶段只触碰当前 PlayerService，不写持久化播放设置；
- command/resource 门禁同时要求 `playback_rate_restored.success=true`，设置成功但未恢复
  原倍速不得记为通过；匿名摘要保留 requested/readback rate 供复核；
- A/B 先实际从 A 播放到 B 并观察回到 A，再由 DWM 窗口判断是否有可见变化；
- 外挂字幕先在同一位置建立无字幕静止基线，再把 `sub-add` 后的下方区域作为独立窗口；
- 命令失败为 `fail`，桌面样本不足或指纹变化低于 `1.5%` 只为 `unknown`，不补成通过；
- DWM 观测器使用桌面 DC 的不缩放 `BitBlt` 和匿名分布式网格；采样率必须达到 `30 fps`，
  可见性以命令后至少一个不低于 `1.5%` 的真实桌面合成变化为 `pass`，不以命令或帧号代理；
- 资源释放仍必须出现 `player_resources_released`。

P1 校验器对每个控制分别输出 `commandResource`、`visible` 和合并 `overall`，因此命令
可用但 DWM 采样不足时不会被合并为完成：

~~~powershell
pwsh -NoProfile -File .\tool\validate_player_p1_precision_evidence.ps1 `
  -EvidenceRoot .\.local\qa\precision-dwm-rate-h264-20260820 `
  -Output .\.local\qa\p1-precision-evidence.json
~~~

三轮独立会话可用下面的矩阵入口顺序运行；它会排除 ready 前失败，并把 validator 的
`unknown` 以 exit code `3` 保留：

~~~powershell
pwsh -NoProfile -File .\tool\run_player_precision_controls_dwm_matrix.ps1 `
  -Sample 'D:\video\<anonymous-local-sample>.mp4' -Runs 3 `
  -Output .\.local\qa\precision-dwm-matrix-current
~~~

最新本机 Debug 三编码各一轮的匿名结果为：H.264 采样 `26.7 fps`、A/B DWM
可见性 `pass`；HEVC 采样 `26.9 fps`、A/B DWM 可见性 `pass`；AV1 采样
`27.4 fps`、A/B DWM 可见性 `unknown`。三轮的逐帧和外挂字幕 DWM 可见性均为
`unknown`，整体均为 `unknown`；采样率仍低于该观察器的 `30 fps` 最低采样门禁，
因此不生成“真实可见性通过”。最新证据目录为
`.local/qa/precision-dwm-buffered-{h264,hevc,av1}-20260820_*`，其中只保留匿名阶段、
尺寸、时间和指纹差异，不保留截图或媒体内容。该结果把 P1 的命令/资源 QA 与真实
可见性 QA 明确拆开，不能写成逐帧、A-B 或外挂字幕功能完成。

最新 H.264 precision 会话新增的倍速命令阶段已真实读回并恢复原值，P1 校验器将四个
控制的 `commandResource` 记为 `pass`；同一会话 DWM 采样为 `27.3 fps`，低于 `30 fps`
门禁，因此四个控制的 `visible` 和合并 `overall` 仍为 `unknown`。这只证明倍速命令
合同可用，不证明倍速在真实 Texture 上的呈现节奏已经通过。

本轮重新执行正式 Texture command/resource QA，匿名目录为
`.local/qa/precision-command-current-20260820l`：`frame_step_complete`、
`playback_rate_complete`（`1.5→1.500000`）、`playback_rate_restored`、A/B 四阶段和
`external_subtitle_complete(trackListObserved=true)` 均为 `success=true`，并有
`player_resources_released`。独立 P1 校验器将四项 `commandResource` 判为 `pass`；由于
该 command-only 目录没有 DWM 摘要，四项 `visible` 和合并 `overall` 均为 `unknown`，
没有把命令/资源结果升级为真实 Texture 可见性完成。

随后修正 DWM 观测器的缩放瓶颈，并让倍速 QA 在播放中设置 `1.5x`、观察 1 秒、恢复到
`1.0x` 后读回，再暂停进入下一项。新增矩阵入口并真实运行
`.local/qa/precision-dwm-matrix-grid16-rate1s-20260820b`：3/3 独立会话有效，采样为
`32.0–32.2 fps`，资源释放和四项 command/resource 均 `3/3 pass`，A/B loop 的 DWM
可见性 `3/3 pass`；逐帧、倍速和外挂字幕均 `3/3 unknown`，所以聚合校验为 A/B
`overall=pass`，其它三个控制和矩阵总体 `overall=unknown`，validator exit `3`。这是
`libass=false` 旧 Debug 构建的基线，前一轮
ready 前退出的会话和本矩阵之外的探索轮次均未混入该聚合结果。

随后根据真实属性读回定位到 `media_kit` 默认 `PlayerConfiguration.libass=false` 会把
`sub-visibility` 初始化为 `no`；外挂字幕轨道虽已选中，但不可能进入正式 Texture。正式
`MediaKitPlayerBackend` 现在以 `libass: true` 初始化同一 NativePlayer，并保留独立
command/resource 与 DWM 观察边界。修复后的三编码代表性矩阵均为 3/3 有效、采样约
`31.8–32.3 fps`、资源释放 `3/3 pass`，外挂字幕均 `subtitleSelected=true`、
`subtitleVisibilityEnabled=true`，字幕下方 DWM 网格均 `3/3 pass`：

- H.264：`.local/qa/precision-dwm-matrix-long-h264-libass-20260820a`，逐帧、倍速、
  A-B、外挂字幕的 command/resource 与 visible 均 `3/3 pass`，矩阵 exit `0`；
- HEVC：`.local/qa/precision-dwm-matrix-long-hevc-libass-20260820a`，倍速、A-B、外挂
  字幕均 `3/3 pass`；逐帧 command/resource `3/3 pass` 但 DWM visible `3/3 unknown`，
  因而该矩阵总体 `unknown`；
- AV1：`.local/qa/precision-dwm-matrix-long-av1-libass-20260820a`，四项 command/resource
  与 visible 均 `3/3 pass`，矩阵 exit `0`。

因此外挂字幕在这组三编码代表性素材上已拥有真实可见证据；HEVC 逐帧仍单独保持
`unknown`，不能被其它控制或编码的通过结果覆盖。

为降低局部逐帧变化落在采样点之间的漏检，最终 DWM 观察器将中心匿名网格加密为
`32×20`，同时把字幕保留为独立的 `16×4` 网格并固定在采集 ROI 的 `70%–100%` 底部
归一化区域；阈值仍为 `1.5%`，不保存原始桌面像素。最终观察器矩阵为：

- H.264：`.local/qa/precision-dwm-matrix-long-h264-grid32-region-sub-libass-20260820a`，
  `3/3` 有效，采样 `31.4–31.5 fps`，四项 command/resource 与 DWM visible 均 `3/3 pass`，
  exit `0`；
- HEVC：`.local/qa/precision-dwm-matrix-long-hevc-grid32-region-sub-libass-20260820a`，
  `3/3` 有效，采样 `31.0–31.7 fps`，逐帧 command/resource `3/3 pass` 但 DWM visible
  `3/3 unknown`（最大中心差异 `0.12%`），倍速、A-B、外挂字幕均 `3/3 pass`，exit `3`；
- AV1：`.local/qa/precision-dwm-matrix-long-av1-grid32-region-sub-libass-20260820a`，
  `3/3` 有效，采样 `31.2–31.5 fps`，倍速、A-B、外挂字幕均 `3/3 pass`；逐帧两轮
  pass、一轮没有足够 DWM 变化，聚合为 unknown，exit `3`。

以上 `grid32-region-sub` 是单向逐帧阶段的历史基线；旧的 `grid16` 结果也保留。当前
双向逐帧合同以后以 `grid32-bidirectional` 观察器结果为最新可复核口径，不把任一方向
或任一会话的 unknown 删除、合并或重写为通过：

- H.264：`.local/qa/precision-dwm-matrix-long-h264-grid32-bidirectional-20260820a`，
  `3/3` 有效，采样 `31.4–31.7 fps`，前进/后退逐帧、倍速、A-B、外挂字幕的
  command/resource 与 visible 均 `3/3 pass`，exit `0`；
- HEVC：`.local/qa/precision-dwm-matrix-long-hevc-grid32-bidirectional-20260820a`，
  `3/3` 有效，采样 `31.1–31.5 fps`，两方向逐帧 visible 均 `3/3 unknown`（最大中心差异
  `0.12%`），倍速、A-B、外挂字幕均 `3/3 pass`，exit `3`；
- AV1：`.local/qa/precision-dwm-matrix-long-av1-grid32-bidirectional-20260820a`，
  `3/3` 有效，采样 `31.2–31.6 fps`，逐帧严格按双向/三会话聚合为 `unknown`，倍速、
  A-B、外挂字幕均 `3/3 pass`，exit `3`。

## 阶段 D：外部验收清单

下列项目不阻塞本机阶段报告，但不能由自动化 SendInput 伪造：

- 真人实体 WM_KEYDOWN/UP 长按前进/后退矩阵，保留原生 QPC、按住时长、首个/后续
  DWM 帧；不能用 press_key 代替保持按下。
- 发布构建、目标 GPU/驱动和非强制硬解三编码矩阵；软件回退必须记录实际路径和用户
  可见降级，而不是只记录请求参数。
- 稳定 HWND 与正式 Texture 的同机同素材同动作 A/B；若 HWND 再次不满足合同，结论
  仍是 QA-only 不可发布。
- 跨显示器、DPI、真实窗口移动和全屏切换；当前显示器 inventory 或模拟 Flutter
  metrics 只能记环境/模拟证据。
- 逐帧、A-B、外挂字幕和倍速的真实窗口可见性回归。

## 交付审查

~~~text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved
prompt impact: satisfies first principles; minimal subtitle-rendering fix plus finite evidence contract, no queue/data semantic change
protected behaviors: preserved
unauthorized feature removal: none
mount and reachability: not changed; existing PlayerPage evidence retained
validation: focused contract tests 21/21 passed; subtitle/backend architecture contract passed; PowerShell parsers passed; flutter analyze no issues; flutter build windows --debug passed; steady runtime 10 cases × 3 sessions passed the bounded matrix; bidirectional grid32 H.264 P1 matrix 3/3 valid with validator exit 0 and overall=pass; bidirectional grid32 HEVC and AV1 matrices 3/3 valid with validator exit 3 and overall=unknown because at least one frame-step direction/session lacked DWM change; P0 validator exit 2 with overall=fail as required by remaining DWM/action/VO/manifest unknowns
~~~
