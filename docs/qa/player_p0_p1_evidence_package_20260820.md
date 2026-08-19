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

本机当前装配结果为 `17` 个明确 case/action 映射、`67` 个保留未装配 action；其中包括
1080p 三编码 short/long 的明确 forward/backward 矩阵，以及已有的 4K longhold 矩阵。
没有精确 GOP 绑定的拖动、startup、fullscreen 不会因为目录“看起来相近”而被装配；缺失
素材的 1080p AV1 short 与 4K AV1 long 也继续由原始 manifest 保持缺口。装配输出中的
`evidenceAssembly` 保存选择规则、已映射目录名和省略原因，便于同机复跑和审计。

每个 action 的 evidence 是独立会话目录数组；目录可为包含
desktop-pixel-matrix-summary.json 的矩阵根，或单个 run 目录。报告至少应能追溯：

- DWM 首帧：desktop-composited-pixel-change、首帧延迟和后续匿名变化；
- 运行态：decoder drop、VO drop、total drop、最终硬解属性；
- Texture：generation、尺寸/重建事件和正式 Texture 身份；
- 语义：player_keyboard_event 或 Slider 回执；
- 资源：player_resources_released 或明确的释放失败；
- 稳态：独立至少 10 秒窗口及其分母。动作窗口里的 totalDropFramesMax=0 仍只能记
  unknown，不能代替稳态掉帧率。

因此，当前仓库的本机阶段结论是：

装配后的统一门禁报告为 `overall=fail`：12 个 case 中 `5` 个为 `fail`、`7` 个为
`unknown`、没有 case 为 `pass`。这表示证据链已经能够对已装配动作给出可复核的
`pass/fail/unknown`，但 P0 本机基线尚未完成；VO drop、独立稳态 total drop、未装配
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
| 三编码/两分辨率/短长 GOP 的统一 P0 报告 | fail（5 fail/7 unknown） | 已装配 17 个明确 case/action；仍有未装配动作、稳态字段和 2 个素材缺口 |
| decoder drop | pass 或 fail 按 action 分列 | 运行态有值时非零失败；没有值不补零 |
| VO drop | unknown（已有矩阵多数不可用） | 运行态没有可靠 VO drop 字段时不能判通过 |
| 稳态 total drop | unknown | 既有动作样本缺少独立 10 秒分母 |
| 首个真实 DWM 帧 | pass/fail 按已有 action 分列 | 只采用桌面合成像素报告 |
| P0 总体 | fail（阶段未完成） | 当前门禁没有 case 通过，且仍有 unknown；报告完整性尚未闭环 |

### 已有独立矩阵的补充评估

以下结果来自已有正式 PlayerPage/Texture 的独立矩阵，并通过
[tool/evaluate_player_smoothness_standard.ps1](/E:/LocalTagPlayer/tool/evaluate_player_smoothness_standard.ps1)
重新计算；其中只有目录名能精确绑定素材和 GOP 的结果才由装配器填入统一 manifest，
其它结果仍是支撑证据，不能替代每个 case/action 的三会话关联。

- 1080p 三编码的 shortForward、shortBackward、drag 矩阵各有 `3/3` 有效会话；首个
  DWM p95 分别为：H.264 `81/92/343 ms`、HEVC `86/94/307 ms`、AV1 `86/93/362 ms`。
  页面语义、decoder drop 和最终硬解在这些矩阵中为 `pass`；VO drop、独立稳态分母和
  稳态 Texture 重建仍为 `unknown`，所以矩阵整体不能写成通过。
- 1080p longForward 的首个 DWM p95 为 H.264 `75 ms`、HEVC `99 ms`、AV1 `1105 ms`；
  H.264/HEVC 的连续呈现节奏门禁为 `fail`，AV1 同时首帧与最长无变化间隔失败。
  longBackward 三编码首个 DWM p95 为 `271/281/263 ms`，连续扫描门禁均为 `fail`；
  这些结果继续区分“前进连续扫描”与“后退 latest-only 关键帧预览”，不宣称双向连续。
- 4K drag 的 H.264/HEVC/AV1 矩阵各有 `7/7` 有效会话，首个 DWM p95 为 `351/293/287 ms`，
  页面语义为 `pass`；部分运行态 decoder/hwdec 字段缺失，因此仍按 `unknown` 处理。

阶段 A 在统一 manifest 的每个有效 case/action 达到 3 个独立会话、报告字段齐全、
失败和 unknown 均被保留后结束；不因实体键盘、另一后端或外部 GPU 无限重跑。

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
| 可调倍速 | setRate、状态读回、资源释放 | 真实窗口播放节奏预算 | 命令可用；可见性为 unknown |
| 逐帧 | frame-step/frame-back-step、错误和释放 | 逐帧真实 DWM 画面 | 命令可用；可见性为 unknown |
| A-B loop | A/B/实际 A→B→A 循环、清除命令、状态和释放 | A→B 重复播放画面 | 命令与循环资源 QA 可用；可见性为 unknown |
| 外挂字幕 | 加载/轨道/关闭命令和释放 | 字幕在真实 Texture 上可见、同步 | 命令可用；可见性为 unknown |

“命令可用”不升级为“功能完成”。在可见性证据出现前，P1 只能报告命令合同通过和
可见性 unknown。

### Precision controls 的 DWM 可见性复核

新增 [tool/run_player_precision_controls_dwm_qa.ps1](/E:/LocalTagPlayer/tool/run_player_precision_controls_dwm_qa.ps1)，
它在同一正式 PlayerPage/MediaKit Texture Debug 会话中不发送输入，只读取 DWM 合成后的
中心视频网格和字幕下方网格，分别把命令 JSONL 与匿名桌面指纹 JSONL 落盘。它要求：

- `frame_step_complete` 的命令结果与前后 DWM 时间窗分开；逐帧不接受估算帧号代理；
- A/B 先实际从 A 播放到 B 并观察回到 A，再由 DWM 窗口判断是否有可见变化；
- 外挂字幕先在同一位置建立无字幕静止基线，再把 `sub-add` 后的下方区域作为独立窗口；
- 命令失败为 `fail`，桌面样本不足或指纹变化低于 `1.5%` 只为 `unknown`，不补成通过；
- 资源释放仍必须出现 `player_resources_released`。

最新本机 Debug 三编码各一轮的匿名结果为：H.264 采样 `26.7 fps`、A/B DWM
可见性 `pass`；HEVC 采样 `26.9 fps`、A/B DWM 可见性 `pass`；AV1 采样
`27.4 fps`、A/B DWM 可见性 `unknown`。三轮的逐帧和外挂字幕 DWM 可见性均为
`unknown`，整体均为 `unknown`；采样率仍低于该观察器的 `30 fps` 最低采样门禁，
因此不生成“真实可见性通过”。最新证据目录为
`.local/qa/precision-dwm-buffered-{h264,hevc,av1}-20260820_*`，其中只保留匿名阶段、
尺寸、时间和指纹差异，不保留截图或媒体内容。该结果把 P1 的命令/资源 QA 与真实
可见性 QA 明确拆开，不能写成逐帧、A-B 或外挂字幕功能完成。

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
prompt impact: satisfies first principles; added finite evidence contract without changing playback
protected behaviors: preserved
unauthorized feature removal: none
mount and reachability: not changed; existing PlayerPage evidence retained
validation: see tool/validate_player_p0_evidence.ps1, focused contract test, analyzer/build result
~~~
