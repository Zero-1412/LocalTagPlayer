# 播放器桌面像素呈现延迟

## 目的

`tool/invoke_player_desktop_pixel_probe.ps1` 测量的是 Windows 桌面最终合成后的
像素变化，不是 Dart `Future`、mpv `time-pos`、`estimated-frame-number` 或
`native-rendered-frames`。常规探针使用同一 QueryPerformanceCounter 时钟发送 Win32
键盘输入并读取目标窗口客户区的中心视频区域，因此可以输出：

```text
keyDown / keyUp -> firstPersistentPixelChange
```

若 `SendInput` 没有进入 Flutter 的键盘 Focus 链（此类超时绝不能算作播放器卡顿），可用
`manualForward` / `manualBackward` 启动 Debug-only 实体键盘合同。此模式**不注入按键**：
runner 只在已取得焦点的 `FLUTTERVIEW` 子窗口收到真实 `J/L` 后，追加匿名动作、Down 阶段和
与桌面采样共用的 QPC；探针仍要求 PlayerPage 的匿名 `player_keyboard_event` 回执，随后才以
该 QPC 到 DWM 首个稳定画面计算 p50/p95。它不保存键值、媒体路径、视频 ID 或画面。

原生侧车同时写 `qpcUs` 与 `utcUs`；探针按 JSON 字段边界读取 `qpcUs`，不会假设它是最后一个
字段。若探针没有生成 `desktop-pixel-summary.json`，门禁会优先报告
`desktop-pixel-probe-failure.txt` 中的具体分类（例如缺少实体 Down 或采样不足），不会用
“缺少摘要”覆盖根因。没有 `native_keyboard_message` 和页面语义回执的会话一律是无效样本。

采样区默认以中心原生 24×14 的 RGB 指纹读取（可显式切换为分布式或缩放对照模式）；报告只保存指纹、差异百分比、时间戳与窗口
几何信息，**不会保存截图、视频帧、媒体路径、标题或 videoId**。

## 前置条件

1. 只启动刚构建的 `build\\windows\\x64\\runner\\Debug\\local_tag_player.exe`。
   不使用安装版，也不要让单实例接管 Debug 会话。
2. 在 Debug 播放器中打开本机匿名清单中的目标素材，等待硬解状态稳定。
   若运行时连续三次确认“已请求硬解、实际软件解码”，视频表面会保留软件解码降级条；
   该条的“重新打开”只重建当前媒体会话，“诊断详情”只读，不应把提示出现本身计入 seek 呈现延迟。
3. 对短按和快退：先暂停画面。默认的静止门禁会拒绝播放中的自然帧变化，避免将
   正常视频运动误报为 seek 的新画面。
4. 确保窗口完全可见、未被遮挡、位于前台。探针会在发送输入前以 Win32 前台窗口再次
   核验；Flutter `FocusNode` 的布局瞬时状态不作为渲染就绪条件。
5. 使用 `-ProcessId` 二次绑定刚启动的 Debug 进程，避免同名窗口误接收输入。

## 命令

正式 PlayerPage 的全屏实窗动作使用 `-Action playerFullscreen`。它通过产品页面的 Enter
快捷键切换，不走专用 Texture QA 页；门禁同时要求 DWM 窗口几何变化和 `renderer-events.jsonl`
中的 `fullscreen_settled`。2026-08-19 的干净 4K H.264 单样本（1280×720 逻辑窗口、144 DPI）
以 `115.5 fps` 捕获，输入到几何变化 `50 ms`，全屏前后 Texture generation 均为 `3`、尺寸
`1600×900`；同一会话启动阶段仍观察到 `1920×1080 → 3840×2160 → 1600×900` 的尺寸重建。
该动作验证窗口/Texture 结构，不冒充实体键盘 seek 延迟统计。

独立矩阵的每个 `run-*` 还会写匿名 `runtimeEvidence`：最终硬解状态、首帧证据、Texture
generation/重建事件/尺寸、resize 状态，以及 decoder/VO/total 掉帧最大值。`empty` 和
`unavailable` 保持 `null`，不能解释成零掉帧；`evidenceKind` 若为
`backend-runtime-snapshot-not-desktop-pixels`，仍只代表后端运行态，不是桌面像素呈现。

先验证本机 PowerShell 能载入 Win32 采样器；此命令不查找窗口、也不会发送任何输入：

```powershell
.\tool\invoke_player_desktop_pixel_probe.ps1 -ValidateOnly
```

暂停长 GOP H.264/HEVC/AV1 样本后，分别运行短按前进和短按后退：

```powershell
$pid = (Get-Process local_tag_player | Select-Object -Last 1 -ExpandProperty Id)
.\tool\invoke_player_desktop_pixel_probe.ps1 `
  -WindowTitle local_tag_player -ProcessId $pid -Action forward `
  -Samples 7 -FrameRate 120 -MinimumEffectiveCaptureFps 80

.\tool\invoke_player_desktop_pixel_probe.ps1 `
  -WindowTitle local_tag_player -ProcessId $pid -Action backward `
  -Samples 7 -FrameRate 120 -MinimumEffectiveCaptureFps 80
```

对**真实 `PlayerPage`** 的进度条，使用 `progressDrag`。探针会先把真实鼠标悬停到
底部轨道、等待控制条稳定并验证静帧基线；随后经 Win32 `Down → Move → Up` 在 28% 与
72% 之间交替拖动。计时从拖动 Down 开始，因此不把“首次唤起控制条”的淡入计入 seek
呈现延迟。正式 `PlayerProgressSlider` 仍只在 Up 时提交最终精确 seek：

```powershell
.\tool\invoke_player_desktop_pixel_probe.ps1 `
  -WindowTitle local_tag_player -ProcessId $pid -Action progressDrag `
  -Samples 7 -FrameRate 120 -MinimumEffectiveCaptureFps 80
```

该动作以底部约 110 个**逻辑像素**的可见完整 Slider 中线为默认轨道；探针会按目标窗口
DPI 转为物理输入坐标。运行前应确认目标窗口显示的是实际 `PlayerPage`、媒体已经暂停且
窗口未遮挡。不同控制布局仍必须显式调整 `-ProgressDragBottomInsetPixels`。若 UI 布局、
焦点或基线不满足，报告必须失败，不得把失败样本补进 p95。

中心小裁剪在 4K 切换时若只得到小幅但稳定的像素差异，可**显式**以
`-PixelChangeThresholdPercent 1.0` 重跑；报告与矩阵摘要会记录该值，且仍要求静态基线与
连续两帧变化。不得悄悄降低默认 1.5% 门槛或与不同阈值的 p95 混算。

要把“画面变化”进一步收紧为“完整 Slider 真正收到了拖动”，可显式启动正常 Debug
程序的匿名回执（**不要**设置 `LOCAL_TAG_PLAYER_DESKTOP_PIXEL_QA`；后者是专用页）。在
Debug 程序中手动进入真实 `PlayerPage` 并暂停后，再传入同一回执文件：

```powershell
$qaRoot = Join-Path $PWD '.local\qa\playerpage-drag'
New-Item -ItemType Directory -Force $qaRoot | Out-Null
$env:LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA = '1'
$env:LOCAL_TAG_PLAYER_PIXEL_OUTPUT = $qaRoot
Start-Process .\build\windows\x64\runner\Debug\local_tag_player.exe
# 在刚启动的 Debug 程序中打开目标素材、进入 PlayerPage 并暂停。
$pid = (Get-Process local_tag_player | Select-Object -Last 1 -ExpandProperty Id)
.\tool\invoke_player_desktop_pixel_probe.ps1 `
  -WindowTitle local_tag_player -ProcessId $pid -Action progressDrag `
  -ExpectedInputEvidencePath (Join-Path $qaRoot 'player-input-events.jsonl') `
  -Samples 7 -FrameRate 120 -MinimumEffectiveCaptureFps 80
```

启用回执后，任一没有 `PlayerProgressSlider.onChangeEnd` 匿名提交事件的样本都会以
`progress_slider_semantic_evidence_timeout` 失败；它不记录媒体路径、视频 ID、坐标、
拖动目标或画面。

默认快捷键是 `L` 前进、`J` 后退、Space 播放/暂停、Enter 全屏。若用户改过快捷键，
只能显式使用 `-Action custom -VirtualKey <0..255>`，不得悄悄假定旧映射。

实体键盘门禁会在静态基线就绪后停住并等待一次人工按键；当窗口已显示“等待”时，在该
窗口前台短按 `L` 或 `J` 一次。它从 Windows 消息实际到达 `FLUTTERVIEW` 或顶层 runner 路由的 QPC 起算，而不是
从脚本发现文件的时间起算：

```powershell
.\tool\run_player_desktop_pixel_latency_gate.ps1 `
  -Sample <匿名本地样本路径> -Action manualForward `
  -Samples 1 -FrameRate 120 -MinimumEffectiveCaptureFps 80
```

单次门禁只建立一条人工输入样本；p50/p95 仍须由独立会话矩阵汇总。若没有
`native_keyboard_observer_ready` 必须先写出 `installed=true`（同时记录 child/runner 两个观察器状态）；随后如果没有
`native_keyboard_message` 或 `player_keyboard_event`，命令失败并明确标记输入未到达，绝不输出
播放器时延结论。该临时合同固定观察 J/L，不可替代用户自定义快捷键的人工验收。

长按使用独立动作，不得把短按样本重复命名为长按。它要求同一匿名事件文件中出现
`WM_KEYDOWN → WM_KEYUP`，并默认要求按住至少 `600 ms`；报告同时保存实体按键持续时长、
首个稳定像素和松键后约 `250 ms` 的尾部采样。长按合同仍不保存按键值、画面或媒体身份：

若静态基线已就绪但等待窗口内没有实体 `WM_KEYDOWN/UP`，门禁必须以“缺少实体输入”退出，
不能把等待超时写成播放器长按延迟。最近一次 4K H.264 复核目录
`.local/qa/manual-physical-long-forward-20260820c` 只有观察器握手和等待阶段，没有像素摘要，
因此不进入任何 p50/p95；请在窗口显示等待提示后实际按住 `L` 至少 600ms 再重试。

最新一次 4K H.264 `manualForward` 单样本目录
`.local/qa/current-manual-forward-live-20260819d` 已确认正式 PlayerPage 静态基线、`focusReady=true`、
Texture generation `3`，且原生观察器 `installed/childInstalled/runnerInstalled/topLevelActive` 全为 `true`；
等待 30 秒仍没有 `native_keyboard_message`、`player_keyboard_event` 或 QPC 锚点，门禁以“缺少实体输入”退出。
这排除了观察器握手和页面焦点未就绪，但不能替代操作者实际按下 `L`，不进入短按 p50/p95。

2026-08-20 的自主 Computer Use 反向复核目录
`.local/qa/current-computeruse-manual-backward-20260820` 也不构成实体样本：前台窗口确实收到一次
`J` 并写出 `player_keyboard_event(action=other)`，但没有 `native_keyboard_message` 或 FLUTTERVIEW
QPC 锚点，门禁按合同失败。原子 `press_key` 只能证明页面可接收合成输入，不能冒充物理 WM_KEYDOWN；
该次等待超时不计入播放器时延。

```powershell
.\tool\run_player_desktop_pixel_latency_gate.ps1 `
  -Sample <匿名本地样本路径> -Action manualLongForward `
  -ManualLongHoldMinimumMilliseconds 600 -Samples 1 -FrameRate 120

.\tool\run_player_desktop_pixel_latency_gate.ps1 `
  -Sample <匿名本地样本路径> -Action manualLongBackward `
  -ManualLongHoldMinimumMilliseconds 600 -Samples 1 -FrameRate 120
```

长按矩阵仍要求每个进程由操作者真实按住并松开一次；任何没有完整 Down/Up QPC、页面
`player_keyboard_event` 回执、首个稳定像素或最小时长的 run 都是无效样本，不得混入 p50/p95。

要形成短按的 p50/p95，使用下列矩阵。脚本会为每一轮新建、预热、暂停并释放独立 Debug
会话；每次输出 `PLAYER_DESKTOP_PIXEL_MANUAL_INPUT run=N/7` 后，在该前台窗口实体短按一次
对应按键。实体模式只产生 `inputDownToPixel`，故汇总中的 `inputUpToPixel` 必须为 `null`，不能
将不存在的松键提交边界伪造为零毫秒：

```powershell
pwsh -File .\tool\run_player_desktop_pixel_latency_matrix.ps1 `
  -Sample <匿名本地样本路径> -Action manualForward -Runs 7 `
  -FrameRate 120 -MinimumEffectiveCaptureFps 80
```

长按前后必须分别跑独立矩阵；每轮看到 `waiting_for_physical_key=true` 后，操作者在前台
按住对应的 `L`/`J` 再松开。矩阵会读取每轮 `desktop-pixel-report.json` 的
`physicalKeyHoldDurationMs` 和 `manualHoldSatisfied`，缺少完整 Down/Up 或未达到最小时长
就将该轮标为 `manual_hold_contract_invalid`：

```powershell
pwsh -File .\tool\run_player_desktop_pixel_latency_matrix.ps1 `
  -Sample <匿名本地样本路径> -Action manualLongForward -Runs 7 `
  -ManualLongHoldMinimumMilliseconds 600 -FrameRate 120

pwsh -File .\tool\run_player_desktop_pixel_latency_matrix.ps1 `
  -Sample <匿名本地样本路径> -Action manualLongBackward -Runs 7 `
  -ManualLongHoldMinimumMilliseconds 600 -FrameRate 120
```

如果需要先在无人值守环境拆分“连续扫描期间的桌面冻结”而不冒充实体键盘，可对正式
PlayerPage 运行显式 virtual-key 长按。该参数只注入 Win32 `L/J`，结果证据等级固定为
`win32-keyboard-virtual-key-long-hold`；它不能替代上面的实体 QPC 合同：

```powershell
pwsh -File .\tool\run_player_desktop_pixel_latency_matrix.ps1 `
  -Sample <匿名本地样本路径> -Action forward -Runs 7 `
  -HoldMilliseconds 900 -FrameRate 120
```

`HoldMilliseconds` 只接受自动化 `forward/backward`，实体 `manualLong*`、拖动和全屏动作传入
该参数会直接失败。报告中的 `inputDownToPixel` 是首次持续变化，`longestUnchangedRunMs`
是按住期间的桌面静帧代理；两者仍需与同一会话的 cache/decoder/VO/Texture trace 联读。
QA 页会在首个自动化 forward Down 后恢复播放，否则暂停时 `setRate` 不会推进媒体时钟，
这类“整段无像素变化”只能归类为测量前置条件失败。修复后的 4K H.264 900ms 长按矩阵
（`.local/qa/current-4k-h264-realpage-forward-longhold-7run-20260820b`）前进 p50/p95
`908/912 ms`、最长静帧 `2–9 ms`；后退矩阵（`.local/qa/current-4k-h264-realpage-backward-longhold-7run-20260820`）
为 `907/916 ms`、`1–7 ms`。首帧仍在约 900ms，故只能作为自动化呈现基线，不能写成“丝滑”或
替代实体 WM_KEYDOWN/QPC 验收；未恢复播放的首次失败矩阵 `.local/qa/current-4k-h264-realpage-forward-longhold-7run-20260820`
保留用于审计，不得混入统计。

同一 900ms virtual-key 长按合同的 HEVC/AV1 补测：HEVC 前进/后退均 7/7，Down→DWM p95
`1029/916 ms`、最长静帧 `108/4 ms`；AV1 前进 7/7 为 `1040 ms`、最长静帧 `1025 ms`、
Up→画面 p95 `131 ms`。三编码实际硬解均为 `d3d11va-copy`；HEVC/AV1 前进的 decoder 掉帧
均为 `0`，累计掉帧最高分别 `15`、`15`。AV1 后退 7/7 都以 `pixel_change_timeout` 失败，
但页面仍收到 Down/10 次 repeat/Up，随后 trace 出现 `new_video_frame_timeout` 和
`native_rendered_frame_timeout`；这是当前 latest-only 反向预览未形成实际 DWM 画面的证据，
不是输入链缺失。原始目录：`.local/qa/current-4k-hevc-realpage-forward-longhold-7run-20260820`、
`.local/qa/current-4k-hevc-realpage-backward-longhold-7run-20260820`、
`.local/qa/current-4k-av1-realpage-forward-longhold-7run-20260820`、
`.local/qa/current-4k-av1-realpage-backward-longhold-7run-20260820`。以上均为自动化
`win32-keyboard-virtual-key-long-hold`，不进入实体 WM_KEYDOWN/QPC p50/p95。

专用实际 Debug 门禁还提供 `click` 动作。它在独立、已暂停的正式 Texture QA 页向底部 QA
入口发送真实 Win32 鼠标点击，以验证“输入 → Flutter → libmpv → Texture → DWM 像素”
整条链路；它不是用户正式 UI，也不会进入正常产品运行路径：

```powershell
.\tool\run_player_desktop_pixel_latency_gate.ps1 `
  -Sample <匿名本地样本路径> -Action click -FrameRate 120
```

反向动作要获得可靠 p50/p95，使用矩阵脚本启动七个相互独立、均已预热的 Debug QA
会话。每次单独从至少七秒位置暂停再回退五秒，不能在同一暂停会话连续回退至 0 秒：

```powershell
.\tool\run_player_desktop_pixel_latency_matrix.ps1 `
  -Sample <匿名本地样本路径> -Runs 7 -FrameRate 120 -MinimumEffectiveCaptureFps 80
```

全屏切换是“输入到窗口几何变化”的独立合同，不把静止画面没有像素变动误报为失败；QA
同时写出切换稳定后匿名 Texture generation/尺寸事件。显示器支持时可将初始窗口置为
4K，再测静止反向交互；这仍不会提高 1080p Texture 输出上限：

```powershell
.\tool\run_player_desktop_pixel_latency_gate.ps1 `
  -Sample <匿名本地样本路径> -Action fullscreen -FrameRate 120

.\tool\run_player_desktop_pixel_latency_gate.ps1 `
  -Sample <匿名本地样本路径> -Action click -FrameRate 120 `
  -InitialWindowWidth 3840 -InitialWindowHeight 2160

.\tool\run_player_desktop_pixel_latency_matrix.ps1 `
  -Sample <匿名本地样本路径> -Runs 7 -FrameRate 120 `
  -InitialWindowWidth 3840 -InitialWindowHeight 2160
```

矩阵会在独立 Debug 会话之间等待 1.5 秒，让 MediaKit/ANGLE 异步释放旧 D3D 表面；这段
冷却不计入任何一次输入延迟。即使某次子进程在 ready 前退出，脚本仍会跑完其余独立会话，
并在汇总中记录匿名 `qa-lifecycle` 阶段和失败次数；只要有一轮失效，`p95Eligible=false`，
最终命令失败，绝不由其余成功样本补足或静默忽略。

若要从现有资料库挑选素材，`tool/select_player_qa_sample.dart` 只读打开 `library.db`，只把
绝对路径写入调用方指定、未纳入版本控制的 `.local` 文件；stdout 仅输出 codec、分辨率和候选数。
命令行 Dart 运行时须先把项目随 Windows runner 发布的 SQLite DLL 放入 `PATH`：

```powershell
$env:PATH = "$PWD\windows\tools\sqlite;$env:PATH"
dart run tool/select_player_qa_sample.dart `
  --codec h264 `
  --selection-output "$PWD\.local\qa\selected-4k-h264.path"
```

2026-08-18 的正式 Texture 基线：同机 4K H.264、3840×2160 初始窗口、120fps 请求/80fps
最低门槛、七个独立已暂停 QA 会话全部有效；实际采样约 120–125fps，Down→DWM 首个稳定画面
变化 p50/p95 为 `81/122 ms`，Up→画面变化为 `10/49 ms`，最长静帧段 `114 ms`。这是专用单击
链路的受控基线，不是实际 `PlayerPage` 进度条、键盘短按或连续扫描的验收结论。

同一门槛下的真实 4K HEVC 与 AV1 也各完成七个独立正式 Texture QA 会话：HEVC 的
Down→画面 p50/p95 为 `80/85 ms`、Up→画面为 `7/12 ms`、最长静帧 `74 ms`；AV1 为
`76/82 ms`、`7/12 ms`、`74 ms`。三种 codec 的该项结果只说明最小暂停反向单击链路可稳定
呈现，不能与真实 PlayerPage 精确拖动的 `360/362 ms` Down→呈现 p50/p95 混为一项，更不能
据此提高 Texture 尺寸上限或宣称长 GOP 快进已经丝滑。

同机 4K H.264 的真实 `PlayerPage` 精确拖动还在 3840×2160 逻辑窗口、150% DPI
（`windowDpi=144`）、120fps 请求/80fps 最低门槛、显式 1.0% 中心指纹阈值下完成七个独立
会话。所有会话都包含完整 Slider 的匿名 `start/committed` 回执与产品资源释放生命周期；
Down→实际呈现 p50/p95 为 `335/367 ms`、Up→呈现为 `140/174 ms`、最长静帧为 `360 ms`，
实际采样约 119–123fps。它与 960×720 窗口的 `360/362 ms` 同量级：这组样本不能支持
“4K/DPI 合成压力是精确拖动长尾的唯一根因”，但 367ms 本身仍不符合专业播放器体感。
该阈值只对本 4K 矩阵有效，不能和默认 1.5% 门槛下的 p95 混算。

相同合同下，4K HEVC 的真实 `PlayerPage` 拖动为 Down→呈现 `276/286 ms`、Up→呈现
`82/90 ms`、最长静帧 `277 ms`；4K AV1 为 `444/454 ms`、`249/257 ms`、`445 ms`。两者
也都是七个独立进程 7/7 有效、`windowDpi=144`、约 120–123fps，并拥有完整 Slider 回执。
因此实际精确拖动存在强烈 codec 相关性：不能把 AV1 的 454ms 简化为 Flutter 控件命中、
4K/DPI 或单次 Texture 重建，也不能用最小 QA 页中 80ms 级的 keyframe 首帧掩盖它。该差异
符合 mpv 官方对精确 seek 的说明：精确定位需要从前一个关键帧解码至目标位置，耗时取决于
解码性能；`keyframes` 更快但不保证准确落点。[mpv seek 文档](https://mpv.io/manual/stable/#command-interface)

基线确认后，正式拖动合同已改为 `fastPreviewThenExact`：松手先提交一次目标附近的
`absolute+keyframes` 请求，最多等待 600ms 的帧交付证据，再提交原有普通精确 seek，并以
100ms 位置容差确认；音频仍通过原有最终新帧门禁恢复。两阶段的 QA 门禁会分别要求匿名的
`progress_preview_seek_submitted` 与 `progress_exact_seek_confirmed`，所以它证明快速请求与
准确位置确认都执行过；DWM 的首个变化不擅自标注为其中某一阶段的专属帧。

在同机同合同、4K/150% DPI、1.0% 门槛的 7/7 独立矩阵中，两阶段首画面 p95 分别为：H.264
`351 ms`（单次精确为 `367 ms`）、HEVC `293 ms`（`286 ms`）和 AV1 `287 ms`（`454 ms`）；
相应最长静帧为 `343/283/279 ms`。因此该默认策略显著缩短 AV1 的可见等待，H.264 小幅受益，
HEVC 保持同量级；它不是“单次精确 seek 永远更快”的宣称，也不能掩盖后续短按/长按的独立问题。

长按连续扫描从静止画面开始，第一次重复键由系统注入，持续时间由
`-HoldMilliseconds` 决定：

```powershell
.\tool\invoke_player_desktop_pixel_probe.ps1 `
  -WindowTitle local_tag_player -ProcessId $pid -Action forward `
  -HoldMilliseconds 900 -Samples 7 -FrameRate 120
```

这会同时报告首个持久像素变化和 `longestUnchangedRunMs`。后者是桌面画面冻结代理，
必须与 mpv 的 VO/decoder 掉帧、缓存与 Texture trace 联合解释，不能单独定罪。

## 输出与门禁

每次执行生成独立 `.local/qa/desktop-pixel-probe/<timestamp>/` 目录：

- `desktop-pixel-report.json`：逐采样匿名像素指纹、QPC 时间和几何变化；
- `desktop-pixel-summary.json`：p50/p95、超时数、实际采样 fps、最长静止段。
- `desktop-pixel-trace-correlation.json`：仅按 UTC 侧车关联 `PLAYER_SEEK_TRACE` 与 DWM 首变更；不同源时钟不参与 p50/p95。

专用 Debug QA 启动器还会在其输出根记录 `qa-lifecycle.jsonl`，仅包含
`bootstrap_started`、窗口就绪、MediaKit 打开、暂停基线就绪和受控退出等阶段。独立 4K
会话若在 `ready.json` 前退出，必须以该阶段记录和 stdout/stderr 定位；不能用剩余成功样本
补齐 p95，也不能把退出归为像素采样器性能。

`desktop-pixel-summary.json` 还写入目标窗口的 `windowDpi`；专用 Texture QA 的
`renderer-events.jsonl` 会在暂停静态基线就绪时写出 Texture generation 与输出尺寸。两者
必须一起阅读：逻辑 3840×2160 窗口、Windows 150% 缩放和真正的 3840×2160 Texture 输出
是三个不同概念，不能互相替代。

只有同时满足下列条件，结果才可作为“实际呈现帧”证据：

1. `evidence = desktop-composited-pixel-change`；
2. `captureRatePassed = true`，且实际 fps 达到请求实验的最小阈值；
3. 每次输入前 `baselineStatic = true`；
4. `successfulSamples = Samples`，没有 `pixel_change_timeout`；
5. 目标窗口在测试期间没有被遮挡，`geometryChanges` 与实验意图一致。

默认请求 120 fps 且最低接受 80 fps。若 4K 桌面无法稳定达到这一采样速率，探针会失败，
而不是把低采样结果伪装成高刷新率体验结论。全屏/DPI 实验要把几何变化与
`PlayerTextureOutputSizeCoordinator` 的请求/确认和 Texture generation 对齐后另行报告。
本机 4K/150% DPI 的正式 Texture 全屏门禁为 37ms 的输入→窗口几何变化；暂停静态基线和
全屏稳定后都记录为 Texture 第 2 代、3840×2160。它说明这一轮全屏没有额外重建，不代表
所有窗口、DPI 或输出尺寸切换都没有重建成本；初始 4K 建窗已观察到 1920×1080 到
3840×2160 的注销/新注册。

## 三类 seek 体验合同（P1）

三类输入不能共享一个“seek 很快”的 p95：它们的用户意图、正确性与证据均不同。以下是
当前实现和后续实测共同遵守的验收口径；没有真实 DWM 样本的一项保持未验收，而不是默认
绿灯。

| 输入 | 用户可见语义 | 后端合同 | 必须记录的证据 |
| --- | --- | --- | --- |
| 短按 `J/L` | 快速、可预测的关键帧预览；明确允许落在目标前的关键帧 | KeyUp 只提交一次 `absolute+keyframes`；不追加第二个精确 seek | QPC→DWM 新画面、目标与实际关键帧偏移、cache/decoder/VO/Texture trace |
| 进度条拖动 | 拖动中保持本地滑块和缩略图预览；松手后尽快给出画面并收敛到准确时间 | Up 先提交一次 `absolute+keyframes` 快速请求，再提交普通精确 seek；独立 latest-only 协调器以 100ms 容差确认，并在最终新帧门禁后恢复音频 | Win32 drag→DWM 首画面、匿名 `progress_preview_seek_submitted` / `progress_exact_seek_confirmed`、最终 `time-pos` 偏差 |
| 长按前进/后退 | 连续扫描，首次画面快速变化，释放后立即恢复正常播放 | 前进在首个 KeyRepeat 进入临时连续扫描；后退当前仍为 latest-only keyframe preview，必须单列为未对称项 | 首次变化、有效采样 fps、最长静止段、速度/呈现属性恢复、前后方向分开统计 |

2026-08-18 的首份真实 `PlayerPage` 拖动基线使用真实 4K H.264、正式 MediaKit Texture、
960×720 无常驻队列窗口与 120fps 请求/80fps 最低采样门槛。七个独立进程均获得完整
`progress_slider_start` / `progress_slider_committed` 匿名回执和 DWM 合成画面变化：Down→首个
实际画面 p50/p95 为 `360/362 ms`，Up→画面为 `165/170 ms`，最长静帧段 `354 ms`。它证明
拖动落点已走产品 Slider 和精确 seek 合同，也说明当前拖动体验仍明显慢于专业播放器；不能
把这个现实基线用 Dart 命令完成、关键帧预览或专用 Texture 页的较短数值掩盖掉。

短按的关键帧偏移不是失败证据，但必须呈现给用户（快捷键反馈或诊断）并与“精确拖动落点”
严格分开。长按后退尚未达到与前进相同的连续扫描体验，不能在对外说明中称为双向丝滑。
`mpv --play-direction=backward` 虽可尝试反向播放，但 [mpv 官方文档](https://mpv.io/manual/stable/#options-play-direction)
明确说明该模式脆弱、通常更慢且会打断流水线，并且硬解内存统计不可靠；在 H.264/HEVC/AV1
长 GOP、4K 与硬解的真实矩阵证明可恢复前，不能把它作为“专业级反向扫描”的默认修复。

## 证据边界

- `StretchBlt` 读取的是当前桌面上的最终合成内容，所以比 Texture 帧号、位置更新更接近
  用户体验；它仍受 Windows 桌面捕获能力、窗口遮挡、显示器刷新率和采样率限制。
- 像素指纹只能证明中心视频区域出现稳定变化，不能单独证明目标时间点精确无误；准确落点
  仍由播放位置、关键帧语义和 seek trace 共同验证。
- 长按扫描期间视频本来会连续变化，因此其重点是首个变化、有效采样率和最长冻结段；不要把
  它与暂停状态下短按/拖动的“首个新落点画面”统计混成同一 p95。
- 探针不修改正式渲染后端、Texture 尺寸、硬解、滤镜、seek 策略、播放队列或用户设置。

## 与反向长尾 trace 的对应

每个桌面报告应与同一素材、同一 Debug 进程产生的 `PLAYER_SEEK_TRACE` 和诊断快照并列：

```text
键盘输入（QPC）
  -> keyframe seek submit / command complete
  -> mpv 帧号或原生 Texture 代理变化
  -> desktop-composited-pixel-change
```

若后端帧号已变化而桌面像素迟到，优先检查 Flutter Texture / 合成段；若命令完成前已耗尽
时间，优先检查反向 demuxer cache、关键帧距离、解码器和 VO。该分段归因必须以接下来
的反向 seek trace 实验为准，不能根据一个计数器或主观印象下结论。

`integration_test/player_seek_latency_gate_test.dart` 中旧有的 keyboard / drag 数值是
**coordinator 完成后到帧号代理**的回归指标：其 action 会等待位置确认，因此不可与本页
的“物理输入到桌面像素”p50/p95 混算。反向 keyframe trace 会显式输出实际关键帧落点偏移
和 `textureGenerationDelta`；关键帧偏移大说明预览语义跳跃，不等价于 Texture 合成卡顿。

门禁成功后还会生成 `desktop-pixel-trace-correlation.json`。实体键盘观察器会在同一条匿名
事件中同时写入 QPC 与 UTC；文件据此按“输入 Down 前 500ms → 首个像素/松键后 1s”的
动作窗口筛选 `PLAYER_SEEK_TRACE`，帮助判断“后端首帧已变但 DWM 像素仍未变”的时间段，
而不会把窗口外其它按键 trace 最近邻误归因到本次 action；多个动作窗口重叠时只保留
`candidateActionCount` 并标记 `ambiguous-overlapping-pixel-action-windows`，宁可不匹配
也不制造因果。该文件标记
`evidence=utc-input-window-correlation-only`：Dart `mono_us` 与 Windows QPC 仍不是同一时钟，
UTC 只用于事件窗口，不替代 `manualForward/manualBackward` 的 QPC→DWM 延迟，也不会把
UTC 差值混入 p50/p95。新的 `PLAYER_SEEK_TRACE` 同时写出 `wall_utc_us` 与兼容性的
`wall_utc_ms`；关联器优先使用微秒锚点，旧日志回退到毫秒并标记
`traceWallUtcPrecision=millisecond-fallback`。每条关联还标记 `causalOrder`（`between-input-and-first-pixel`、
`after-first-pixel`、`before-input-down` 或 `unmatched`），避免把“trace 在像素之后”误读为
首帧原因。缺少原生 UTC 时才允许标记 `available-estimated-utc-window`，没有
可用 action 时写出 `unavailable-no-shared-events`，不伪造结果。

关联器还会为每个动作输出 `actionTraceSummaries`：只有唯一动作窗口与唯一 trace id
同时成立时才写入阶段表，以及 `commandCompleteToFirstChangedPixelMs`；没有唯一证据时保留
`no-trace-in-input-window`、`ambiguous-multiple-traces-in-input-window` 或
`trace-outside-pixel-window`。该字段曾因 PowerShell 有序字典未预声明/展开而短暂落入
`unavailable-parse-failed`，现已补初始化、改为显式字典索引，并由独立 standalone Debug
PlayerPage 拖动 smoke 复核：`117.6–119.8 fps`，Down→DWM 首变更 `497–528 ms`，
Up→首变更 `291–296 ms`，关联状态为 `available-estimated-utc-window`/`unique-trace`。
这是自动化 Slider 输入且首帧仍为 `estimated-frame-number-fallback`，只能验证关联管线，
不能替代实体键盘或发布级 p50/p95。

当前 correlation 还保留 `playerInputEvents`、动作内的页面输入事件、原生 Down/Up
QPC/UTC 和 `traceLinkEvidence`。所有 `win32-keyboard-*` 与 `manual-keyboard-*` 动作接受
`player_keyboard_event`，拖动动作接受
`progress_slider_*` 与两阶段回执；因此可以复核 native → PlayerPage → 唯一 trace 的事件集合，
而不是只依赖探针内存中的语义布尔值。最新 1080p H.264 PlayerPage Slider smoke 已落盘
`playerInputEventCount=2`、`traceLinkEvidence=player-semantic+unique-trace-estimated-input`；
其 Down→DWM 首变更 `490 ms`、Up→首变更 `295 ms`，仍是自动化拖动，不进入实体键盘统计。

连续扫描的运行态快照只在显式 `LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA=1` 时启用，
并以 `smooth_scan_start/command_start/command_complete/stop_*` 后缀 `_runtime` 的匿名
trace 节点记录 cache 时长/缓冲状态、decoder/VO 掉帧、硬解与同步属性、Texture 尺寸/代次
和输出证据。真实 1080p H.264 integration smoke 的 7 次前进扫描均有完整节点，
`d3d11va-copy`、Texture `1920×1080`、代次 `1`，后端帧代理 p95 为 `108 ms`；扫描结束
快照出现 VO 总掉帧 `2–3`，这是后端计数变化，不是 DWM 像素掉帧结论。integration 仍将
`dwm.evidence` 固定为 `unavailable-in-integration-test`；只有同一会话的真人键盘与桌面
像素侧车才能继续判断这段变化是否对应用户可见冻结。

桌面门禁期间不能让额外的 UIA/Accessibility 客户端抓取目标 Flutter 窗口。一次使用
Windows 桌面控制观察器后，Debug 4K PlayerPage 的 `flutter_windows.dll` 出现
`0xc0000005`，stderr 同时出现 `accessibility_bridge` 的 pending AXTree 错误；重置
桌面控制会话后，同一 4K H.264、同一 960 窗口、同一自适应 Texture 策略可稳定完成握手和
自动化键盘像素门禁（117.4–115.8 fps、Down→首像素 100 ms）。前述污染会话只保留为
无效环境证据，不得归因于播放器解码或 Texture 性能。执行真人键盘矩阵前应先关闭或重置
任何会读取目标窗口语义树的自动化客户端，并以 stderr 无 `ERROR/Exception`、`ready.json`
已写出为实窗前置条件。

同机真实 4K 长 GOP H.264/HEVC/AV1 的 Debug integration 复测还会写出
`keyboardExperience.smoothScanTrace.summary`：H.264 的首帧/seek p50-p95 为
`314 ms / 138/241 ms`，扫描命令到音频恢复最长 `133.417 ms`，停止时 cache 最长
`13.317 s`、累计掉帧最多 `10`；HEVC 为 `284 ms / 157/199 ms`、`153.990 ms`、
`11.483 s`、`13`；AV1 为 `292 ms / 153/259 ms`、`127.842 ms`、`57.365 s`、`9`。
三组实际硬解均为 `d3d11va-copy`，Texture 代次均为 `2`，summary 的证据等级固定为
`backend-runtime-snapshot-not-desktop-pixels`。这些分段有助于定位停止/恢复和缓存长尾，
但不能替代实体 WM_KEYDOWN/UP 到 DWM 首个实际画面的 p50/p95；原始日志见
[`H.264`](/E:/LocalTagPlayer/.local/qa/turn-4k-h264-scan-summary-20260819.log)、
[`HEVC`](/E:/LocalTagPlayer/.local/qa/turn-4k-hevc-scan-summary-20260819.log)、
[`AV1`](/E:/LocalTagPlayer/.local/qa/turn-4k-av1-scan-summary-20260819.log)。

同机还做了 QA-only 的 mpv `play-direction=backward` 试验：H.264/HEVC/AV1 的 20 次
位置采样均未形成持续反向推进（目标到最小位置分别为 `336607→336616`、
`291769→291766`、`258601→258601 ms`），三次最终都恢复 `play-direction=forward`，
硬解保持 `d3d11va-copy`、Texture 代次保持 `2`。该试验没有改变正式长按后退的
latest-only keyframe preview；mpv 官方也明确提示反向播放脆弱且通常更慢，参见
[官方 manual](https://mpv.io/manual/stable/#options-play-direction)。

编码相关的全屏结构证据也已补齐：同一 1280×720 逻辑窗口、144 DPI 的正式 PlayerPage
门禁中，HEVC 为 `113.0 fps`、Enter→几何 `44 ms`，AV1 为 `115.7 fps`、`50 ms`；两者
均一次几何切换，稳定后 Texture 为 `1600×900`、generation `3`，启动只观察到
`1920×1080 → 1600×900`。此前 H.264 同合同为 `115.5 fps`、`50 ms`，但启动出现
`1920×1080 → 3840×2160 → 1600×900`、generation `0→1→2→3`。这不是“全屏零重建”
或“所有编码固定同一尺寸”的证据，而是编码/解码器时序导致的不同 Texture 生命周期；
正式 Texture 上限没有提高。

为避免把“提高 Texture 上限”误当成修复，另对 HEVC/AV1 运行了 Debug-only
`adaptiveTextureSizingEnabled=false` 对照：两者都从 `1920×1080` 重建到 `3840×2160`、
generation `2`，全屏稳定后不再重建；HEVC 有效采样 `121.5 fps`、Enter→几何 `51 ms`，
AV1 `113.9 fps`、`50 ms`。正式自适应路径反而收敛到 `1600×900`、generation `3`。
该对照只说明 4K 原生表面会被创建，并不能证明合成更稳定，因此不把 1080p 上限直接调高。

干净 Debug 会话还完成了真实 PlayerPage 的 7 轮 virtual-key 输入对照（证据等级仍是
`win32-keyboard-virtual-key`，不能冒充实体 WM_KEYDOWN/QPC）：前进 Down→DWM p50/p95
`94/107 ms`、Up→画面 `50/59 ms`；后退 `93/96 ms`、`49/52 ms`，有效采样约
`112–117 fps`，两组均 `7/7`。它证明页面 Focus/快捷键/Texture 路径在干净会话可达，
但不改变实体键盘 p50/p95 仍待真人输入的验收口径。摘要目录为
`.local/qa/current-4k-h264-realpage-forward-7run-diagnostic-20260820` 和
`.local/qa/current-4k-h264-realpage-backward-7run-diagnostic-20260820b`。

### 探针客户区读取失败的分类与重试

窗口重建或 DWM 短暂切换期间，`GetDC`/客户区读取可能瞬时失败。探针现在只在
静态基线和动作采样的原有截止时间内有界重试，并将失败次数写入
`captureReadFailures`；重试不会放宽静态基线、连续两帧像素变化、页面输入语义或有效
捕获帧率门禁。若仍无法取得足够基线帧，样本分类为 `pixel_capture_unavailable`，不生成
延迟统计。

本机复核中，`.local/qa/current-agent-forward-retry-20260819i` 的 3 轮均为
`captureReadFailures=0`，但没有 `player_keyboard_event` 和持久像素变化，按输入未到达
处理并排除；随后干净重跑 `.local/qa/current-agent-forward-retry-20260819j` 取得 3/3
有效样本，Down→DWM 为 `100/104 ms`（p50/p95），Up→画面为 `57/62 ms`，有效捕获
`115.0–117.5 fps`。这证明重试只降低采样器自身的暂态噪声，不会把输入链失败或静态画面
伪装成成功。

正式 `PlayerPage` 的自动化键盘动作（`forward`、`backward`、`playerFullscreen`）现在也传入
`player-input-events.jsonl`，探针要求 `player_keyboard_event` 页面语义回执；专用 Texture QA
不传该文件时仍保持原有像素对照合同。`.local/qa/current-agent-forward-semantic-20260819l`
3/3 通过，每轮均为 `inputSemanticEvidence=player-keyboard-event`，Down→DWM p50/p95
`106/119 ms`、Up→画面 `61/77 ms`，有效捕获 `111.9–116.4 fps`，
`captureReadFailures=0`。`.local/qa/current-agent-forward-semantic-20260819k` 的第 3 轮只到
`bootstrap_started`，按独立会话启动失败排除，未生成 p95；这类失败不能被像素重试或统计脚本
吞掉。

### 反向基线修正与正式三编码复核（2026-08-19）

此前 AV1 反向失败样本的静止基线约在 10 秒，首次 10 秒回退只剩 66ms，桌面像素不变时
无法区分“正确停在首帧”和“新帧未送达”。Debug-only PlayerPage QA 现在对长素材把基线移到
18–30 秒区间；该逻辑不进入正式页面，不改播放起点、播放进度或 Texture 档位。

同一新 Debug 构建、同一真实 4K 长 GOP 素材、144 DPI、900ms virtual-key `backward`，每种编码
独立 3 次均通过桌面合成像素门禁，且页面 `player_keyboard_event` 语义回执成立：

| 编码 | 有效轮次 | Down→DWM p50/p95 | 最长静帧 | 有效采样 | 最终硬解 | Texture 代次/重建 |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| H.264 | 3/3 | 904/905 ms | 0–8 ms | 100.4–118.4 fps | d3d11va-copy | 0/1/2/3，2–3 次 |
| HEVC | 3/3 | 903/907 ms | 0–6 ms | 115.7–117.6 fps | d3d11va-copy | 0/1/3，2 次 |
| AV1 | 3/3 | 909/914 ms | 2–4 ms | 115.8–118.5 fps | d3d11va-copy | 0/1/2/3，2–3 次 |

三组 `captureReadFailures=0`、decoder/total drop 最大值为 `0`；这些是自动 virtual-key 对照，
不是实体 WM_KEYDOWN/QPC p50/p95。约 0.9 秒的首个屏幕变化仍远离专业播放器体验，不能把“门禁通过”
误写成“反向丝滑”。原始匿名矩阵：
`.local/qa/current-reverse-formal-baseline30-20260819/{h264,hevc,av1}/matrix`。

同一 AV1 基线下的 Debug-only `frame-step -1 seek` 触发实验为 3/3、Down→DWM p50/p95
`1236/1249 ms`；关闭实验的同基线对照为 `910/915 ms`。逐帧触发不但没有改善，反而增加长尾，
因此已从 `MediaKitPlayerBackend` 撤掉，正式路径仍只使用既有 `absolute+keyframes` 交互语义。

### 2026-08-20：自动长按首帧测量合同校正

旧版自动化长按先阻塞 `HoldMilliseconds`、发送 KeyUp，再开始桌面采样，因此约
`900 ms` 的结果只能说明“采样启动晚于输入”，不能作为 Down→首帧延迟。本轮已将
探针改为：

- 在 Down 后立即采样，并在同一循环中发送 Repeat 与真实 Up；按住窗口的样本计入有效
  capture fps，动作结束前不提前释放按键。
- 首个持续桌面变化在按住期间出现时，`inputDownToFirstChangedPixelMs` 正常记录，
  `inputUpToFirstChangedPixelMs`/p50/p95 保持 `null`；不得把 nullable 空值强转成 0。
- 真实 PlayerPage QA 读取隔离页 ready 握手的当前快捷键，并用 SendInput scan-code
  进入产品 Focus 链；virtual-key 在该页面可能被 Flutter 解析为 `other`，不能作为
  正式语义门禁的唯一输入路径。

校正后的同机 4K、144 DPI、正式 MediaKit Texture、900ms 自动长按后退矩阵各 3/3
有效（证据是自动化，不是实体 WM_KEYDOWN/QPC）：

| 编码 | Down→DWM p50/p95 | Up→首帧 | 按住期间最长静帧 | 有效采样 | 硬解/Texture |
| --- | ---: | ---: | ---: | ---: | --- |
| H.264 | 81/98 ms | null | 95–107 ms | 118.6–119.8 fps | `d3d11va-copy` / generation 0–3 |
| HEVC | 186/201 ms | null | 136–205 ms | 117.5–119.6 fps | `d3d11va-copy` / generation 0–3 |
| AV1 | 83/99 ms | null | 120–125 ms | 118.2–118.8 fps | `d3d11va-copy` / generation 0–3 |

运行态快照三种编码 decoder drop/total drop 均为 0，Texture 在启动/尺寸协调期间仍
出现 2–3 次重建；这是“按住期间桌面确实在动”的基线，不等价于反向 seek 落点已达
专业播放器水平。H.264 单次 trace 还显示首个 DWM 变化早于第一次 reverse keyframe
seek 命令，说明该数字包含 QA 页按下后恢复播放的首帧；真正的反向预览段必须继续以
`reverse_preview_frame_wait_start/complete`、命令后 cache/decoder/VO/Texture 快照和
DWM 像素变化联合审查。原始匿名证据：

- `.local/qa/current-reverse-hold-scancode-20260820/h264-matrix`
- `.local/qa/current-reverse-hold-scancode-20260820/hevc-matrix`
- `.local/qa/current-reverse-hold-scancode-20260820/av1-matrix`

因此不能把本轮 p95 改写成“反向扫描已经丝滑”；实体短按/长按仍缺少操作者真实
WM_KEYDOWN/QPC 的独立 p50/p95，反向连续解码也仍未形成可交付的双向合同。
