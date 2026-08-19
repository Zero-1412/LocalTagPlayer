# 播放器真实 seek 延迟矩阵门禁

本门禁衡量本产品已支持的本地发现播放器交互，不把目标扩展为 PotPlayer 或 VLC 的完整专业播放器。它保护精确恢复入口和方向键语义：精确恢复只做一次 absolute seek，方向键短按只在 KeyUp 做一次关键帧预览，只有长按产生 `KeyRepeat` 后才允许连续扫描。普通鼠标点击进度条走独立的关键帧 latest-only 交互路径，由 focused 测试保护其快速点击不堆积。

## 覆盖与口径

矩阵必须完整覆盖 12 例：`1080p/4k × h264/hevc/av1 × short-gop/long-gop`。每例先由 `ffprobe` 验证视频流编码和像素尺寸；短 GOP 最大关键帧间隔不得超过 1.1 秒，长 GOP 不得少于 4 秒。默认脚本运行正式 `MediaKitPlayerBackend` 的 Texture 输出，在两次预热后采集 7 次精确随机 seek，从后端调用到位置实际接近目标（750 ms 容差）并观察帧号变化的端到端耗时计算 p50/p95/max。

解码器路径记录为证据而非先验。硬件不支持时允许软件回退参加门禁，但必须为该机器设置独立、明确的预算；不得根据请求的 `hwdec` 参数推测实际硬解。

## 本机 manifest

媒体路径不得提交。创建一个本机 JSON（建议放在 `.local/qa/`）并为每个 case 填写真实样本和预算：

```json
{
  "cases": [
    {
      "id": "1080p-h264-short-gop",
      "path": "D:\\qa-media\\h264-1080p-gop30.mp4",
      "codec": "h264",
      "width": 1920,
      "height": 1080,
      "gop": "short-gop",
      "p95BudgetMs": 500
    }
  ]
}
```

其余 11 个 ID 必须正好为：

```text
1080p-h264-long-gop   1080p-hevc-short-gop   1080p-hevc-long-gop
1080p-av1-short-gop   1080p-av1-long-gop     4k-h264-short-gop
4k-h264-long-gop      4k-hevc-short-gop      4k-hevc-long-gop
4k-av1-short-gop      4k-av1-long-gop
```

推荐初始 p95 预算为 1080p 短/长 GOP `500/1200 ms`、4K 短/长 GOP `800/1800 ms`；它们是回归门槛，不是跨设备的性能承诺。第一次在目标机器建立基线后，只能在有真实结果和原因记录时调整预算。

## 执行

```powershell
.\tool\run_player_seek_latency_matrix.ps1 -Manifest .\.local\qa\player_seek-latency-matrix.json
```

需要定位正式 Texture 与原生 child HWND 的呈现差异时，才显式运行：

```powershell
.\tool\run_player_seek_latency_matrix.ps1 `
  -Manifest .\.local\qa\player_seek-latency-matrix.json `
  -Backend hwnd
```

输出位于未跟踪的 `artifacts/player_seek_latency_<timestamp>/`：每个 case 的日志和不含路径的 `summary.json`。矩阵通过正式精确恢复入口测量：临时静音但不暂停视频时钟；精确 seek 返回后才采样基线。`native-rendered-frames` 大于零时是原生输出已提交渲染请求的直接代理；正式 MediaKit Texture 标记为 `native-rendered-texture`，child HWND 标记为 `native-rendered-child-hwnd`，不能把 HWND 计数误写成 Texture 复制。当前正式 MediaKit Texture 若未暴露该计数，会回退 `estimated-frame-number`；child HWND 则要求原生子窗口可见且该帧号变化，写为 `child-hwnd-visible+estimated-frame-number-proxy`。这些代理均不是桌面像素捕获，不能当作“首个实际屏幕呈现帧”或与专业播放器的屏幕级数据混算；一旦需要发布级结论，必须补固定帧率录屏或桌面捕获的独立证据。HWND 结果仅用于根因定位，不得作为 Release 排名、默认后端或产品能力声明。任一样本缺失、probe 与 manifest 不符、GOP 分类不符、后端未确认位置/新帧或 p95 超预算都会使门禁失败。

每个 case 还输出 `keyboardExperience` 与 `dragExperience`。前者以页面同配置的
`PlayerKeyboardSeekController` 重放短按、长按前进和长按后退，后者重放一次 latest-only
进度条拖动；两者都从输入模型动作到帧号代理变化采样 p50/p95/max。它们验证正式控制器，
但不替代真实 `PlayerPage` 焦点、实体按键重复率或桌面像素捕获；需要把结果作为用户级体验
结论前，仍要进行实窗录屏对齐。

## 录屏与 `PLAYER_SEEK_TRACE` 对齐

当真实媒体库出现“预览帧先到、连续播放稍后恢复”的间歇性问题时，录屏应以 30fps 或更高的固定帧率保存到未跟踪的 `.local/qa/`，并在启动录制时写入 UTC 毫秒侧车记录。调试日志中的同一 `trace` 必须按以下顺序出现：

```text
key_up
exact_seek_start
exact_seek_complete
native_rendered_frame | presented_frame_fallback | native_rendered_frame_timeout
audio_restore_start
audio_restore_complete
```

进度条交互式 seek 不进入音频门禁时，使用同一 `PLAYER_SEEK_TRACE` 的以下节点测量命令到首帧：

```text
seek_submit_start
seek_command_complete
native_rendered_frame | presented_frame_fallback | native_rendered_frame_timeout
```

当协调器启用了位置确认窗口时，还会明确写出：

```text
position_confirmation_start
position_confirmation_complete | position_confirmation_superseded | position_confirmation_timeout
```

这段等待属于逻辑位置确认，不得直接标成桌面首帧延迟；`confirmationTimeout=0` 的键盘预览
不会产生这段等待。

长按前进连续扫描还必须出现以下独立节点；它们只描述临时扫描档位的下发，不把命令完成冒充桌面呈现：

```text
smooth_scan_start
smooth_scan_command_start
smooth_scan_command_complete | smooth_scan_command_failed
smooth_scan_stop_start
smooth_scan_stop_complete
```

`native_rendered_frame` 的 `mono_us` 由项目内单调 Stopwatch 记录，`seek_to_frame_us` 是从
`seek_submit_start` 到该帧被观察到的间隔；它不包含点击工具、录屏工具或 wall clock 的时间。
后台观测只保留最新目标，不得阻塞下一次 latest-only 派发。

每条事件的 `mono_us` 只用于计算节点间隔；`wall_utc_ms` 只用于和录屏侧车建立时间锚点。若 `seek_command_complete` 已出现而 `native_rendered_frame` 明显延后，说明解码/VO/呈现恢复慢；若 `native_rendered_frame` 已出现但连续画面仍静止，则需要继续检查 Texture 呈现或播放器时钟，不能把单一预览帧当作恢复完成。稳定性矩阵会把 `PLAYER_SEEK_LATENCY` 中的 `reverseKeyframeTrace` 挂到 `qaReverseKeyframeTrace`，保留 `runtimeDeltas.cache`、`decodeAndVoDrops`、`effectivePipeline` 与 Texture 代次差，并新增 `segmentTrace`：明确列出命令完成、命令后运行态、后端帧代理、Texture 和 DWM 证据边界。`segmentTrace.dwm.evidence=unavailable-in-integration-test` 时必须由独立桌面像素侧车补齐，不能把 integration 帧代理升级为实际屏幕呈现；该增强对象同时写回每个 backend 的 `reportPath`，避免只在总矩阵内存对象中暂存而在独立报告审查时丢失。

反向和拖动的 Debug-only `segmentTrace` 还会在三个统一节点写匿名运行态快照：`seek_command_complete_runtime`、`native_rendered_frame_runtime|presented_frame_fallback_runtime`、`native_rendered_frame_timeout_runtime`。快照包含 `demuxer-cache-duration`、decoder/VO/total 掉帧、`hwdec-current`、`current-vo`、`video-sync`、Texture generation/尺寸/resize 状态和呈现证据；读取经单一尾链串行，不等待快照完成再派发 seek。`unavailable` 必须原样保留，不能用 0 代替；这些事件仍不等价于 DWM 像素，只有和实体 WM_KEYDOWN/QPC 及桌面像素侧车同会话关联后，才可用于最终 p50/p95。

当前 Debug 4K H.264 复测的匿名摘要为：短按后退帧代理 p95 `99 ms`、长按后退 p95 `238 ms`、反向命令 p95 `0 ms`、命令到帧代理 p95 `3 ms`，所有反向记录的 `textureGenerationDelta=0`，`hwdec-current=d3d11va-copy`。这只能说明该真实素材的后端分段没有重现旧 `2.7 s`；它仍不替代实体键盘 QPC→DWM 像素合同。将 integration 键盘协调器与正式页面统一为 `confirmationTimeout=0` 后，按同一素材七次复测为短按后退 `80 ms`、长按后退 `139 ms`、命令 p95 `0 ms`、命令到帧代理 `39 ms`，Texture 代次差仍为 `0`；该摘要仍只作后端帧代理证据。

同一真实 4K H.264 另跑了 QA-only child HWND 后端：主 seek p95 `294 ms`、短按前/后 `131/106 ms`、长按前/后 `101/192 ms`、反向命令 p95 `1 ms`、命令到帧代理 `73 ms`，硬解为 `d3d11va`，证据为 `child-hwnd-visible+estimated-frame-number-proxy`。正式 Texture 对照为主 seek `329 ms`、短按前/后 `47/80 ms`、长按前/后 `147/139 ms`、命令到帧代理 `39 ms`、`textureGenerationDelta=0`、`d3d11va-copy`。两者仍都是后端帧代理而非实体键盘/DWM 像素；完整 PlayerPage 稳定性矩阵因样本精确位置未收敛而失败，未将失败样本混入该摘要。匿名对照见 `.local/qa/current-texture-hwnd-seek-compare-20260819.json`。

正式 PlayerPage 的全屏结构复核已覆盖三种 4K 编码（1280×720 逻辑窗口、144 DPI）：
H.264 `115.5 fps`、Enter→几何 `50 ms`，启动 Texture `1920×1080 → 3840×2160 → 1600×900`；
HEVC `113.0 fps`、`44 ms`，启动 `1920×1080 → 1600×900`；AV1 `115.7 fps`、`50 ms`，
启动 `1920×1080 → 1600×900`。三者稳定全屏均仅一次几何切换、Texture generation `3`，
但启动代次不同，故不能将 H.264 的 `3840×2160` 中间重建或单次无额外全屏重建外推到
其它编码。以上是 Texture/窗口生命周期证据，不是 seek p50/p95。

另做了 QA-only 的固定尺寸对照（`adaptiveTextureSizingEnabled=false`）：HEVC/AV1 均从
`1920×1080` 重建到 `3840×2160`、generation `2`，有效采样分别为 `121.5/113.9 fps`，
Enter→几何分别 `51/50 ms`；正式自适应路径分别稳定在 `1600×900`、generation `3`。
这支持“先保留稳定档位、继续测合成压力”的 P0 判断，不支持直接提高正式 Texture 上限。
原始门禁日志分别为 `.local/qa/current-4k-hevc-player-fullscreen-fixed-texture-20260820.log` 和
`.local/qa/current-4k-av1-player-fullscreen-fixed-texture-20260820.log`。

独立真实 PlayerPage virtual-key 对照也完成 7/7：前进 Down→DWM p50/p95 `94/107 ms`、
后退 `93/96 ms`，有效采样约 `112–117 fps`，均为 `win32-keyboard-virtual-key`，不进入
实体键盘 p50/p95。后退第一次 7 轮尝试有一轮只写出 `bootstrap_started`，故整轮门禁保持
`p95Eligible=false`；第二次 7/7 重跑才作为自动化合同对照。该结果证明 Focus/页面输入
链在干净 Debug 会话可达，但不替代真人 QPC 证据。

为验证连续扫描期间是否真的有桌面画面推进，桌面矩阵新增 Debug-only `HoldMilliseconds`。
隔离 QA 页在首个自动化 forward Down 后恢复播放；正式页面、实体 `manualLong*` 和用户
快捷键语义均不读取该环境变量。4K H.264、144 DPI、900ms virtual-key 长按各 7/7：前进
Down→DWM 首画面 p50/p95 `908/912 ms`、最长静帧 `2–9 ms`、有效采样 `110.5–120.4 fps`；
后退 latest-only 关键帧预览为 `907/916 ms`、`1–7 ms`、`114.4–120.9 fps`。前进运行态仍为
`d3d11va-copy`、decoder 掉帧 `0`、VO 计数不可用、累计掉帧 `8–9`。这些数字只证明
virtual-key 长按的桌面探针可运行，首帧约 900ms 仍明显不是专业级丝滑，也不能替代实体
WM_KEYDOWN/QPC p50/p95。未恢复播放的同合同首次 7/7 `pixel_change_timeout` 证据保留在
`.local/qa/current-4k-h264-realpage-forward-longhold-7run-20260820`。

同一 900ms virtual-key 长按合同已补齐 HEVC/AV1：HEVC 前进/后退均 7/7，Down→DWM p95
`1029/916 ms`、最长静帧 `108/4 ms`，前进运行态硬解 `d3d11va-copy`、decoder 掉帧 `0`、
累计掉帧最高 `15`；AV1 前进 7/7 为 `1040 ms`、最长静帧 `1025 ms`、Up→画面 p95 `131 ms`，
硬解 `d3d11va-copy`、decoder 掉帧 `0`、累计掉帧 `14–15`。AV1 后退 7/7 全部
`pixel_change_timeout`，但页面仍收到 Down/10 次 repeat/Up，trace 写出首次关键帧回退后连续
`seek_command_complete`，随后 `new_video_frame_timeout`/`native_rendered_frame_timeout`；这不是
输入缺失，而是当前 latest-only 反向预览在该 4K AV1 长 GOP 上没有形成实际 DWM 画面。以上均为
`win32-keyboard-virtual-key-long-hold` 自动化证据，不进入实体 p50/p95。原始目录分别为
`.local/qa/current-4k-hevc-realpage-forward-longhold-7run-20260820`、
`.local/qa/current-4k-hevc-realpage-backward-longhold-7run-20260820`、
`.local/qa/current-4k-av1-realpage-forward-longhold-7run-20260820` 和
`.local/qa/current-4k-av1-realpage-backward-longhold-7run-20260820`。

最新 Debug 1080p H.264 smoke（`.local/qa/current-segmenttrace-smoke-20260819/integration.log`）已验证新分段对象真实落盘：7/7 反向记录均含 `segmentTrace`，实际硬解 `d3d11va-copy`，反向命令 p95 `0 ms`、命令到后端帧代理 p95 `15 ms`、Texture 代次差均为 `0`；`dwm.evidence` 全部为 `unavailable-in-integration-test`。该 smoke 只证明报告管线和后端代理分段，不替代 4K/长 GOP、实体键盘或桌面像素验收。

新接线的 `.local/qa/current-segmenttrace-followup-20260819c.log` 还验证正式 `PlayerSeekCoordinator` 的 `seek_command_complete_runtime` 与 `presented_frame_fallback_runtime` 均进入 `keyboardExperience.smoothScanTrace.summary.keyframeSegments`（7/7 会话共 21 个命令段）；命令到后端帧代理最大约 `15.3 ms`、Texture generation 全为 `1`、实际硬解 `d3d11va-copy`、decoder 掉帧为 `0`。这里的 `presented_frame_fallback` 仍是 `estimated-frame-number` 代理，不能升级为 DWM 像素呈现。

最新 Debug 构建的 4K AV1、144 DPI、正式 PlayerPage、900ms virtual-key 长按快退矩阵（`.local/qa/current-av1-segmenttrace-followup-20260819c`）按门禁失败：7/7 桌面像素动作均 `pixel_change_timeout`，`successfulRuns=0`，故报告不生成 p50/p95。5 个可完整退出的会话各写出 12 条运行态快照，均保留 `framePresentationEvidence=texture`、`firstFrameEvidence=media-kit-texture+position-update`、Texture generation `0/1/3`（2 次重建）、`1600×900/1920×1080` 尺寸与 `adaptiveTextureSizingEnabled=true`；decoder/total drop 最大值为 `0`，`hwdec-current` 短暂出现 `no` 后最终回到 `d3d11va-copy`。run-02 的 `native_rendered_frame_timeout_runtime` 等待 `2016 ms` 时仍有 Texture generation `3`、cache `49.962667 s`、decoder/total drop `0`。关联器同时标记 `no-trace-in-input-window`，因为该动作是 virtual-key 而非实体 QPC；这是一条反向预览没有形成 DWM 新帧的失败证据，不得改写成实体键盘延迟或用来宣称 Texture/HWND 优劣。

随后在同一 1080p H.264 素材上以 Debug 环境变量 `LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA=1` 重跑
`.local/qa/current-segmenttrace-runtime-smoke-20260819b/integration.log`。7/7 次连续扫描均落盘
`smooth_scan_start/command_start/command_complete/stop_start/stop_complete` 及对应的
`*_runtime` 节点；快进扫描后端帧代理 p95 为 `108 ms`，反向命令 p95 为 `0 ms`、命令到后端帧代理
p95 为 `12 ms`。匿名运行态快照实际读到 `hwdec-current=d3d11va-copy`、`current-vo=libmpv`、
`video-sync=audio`、Texture `1920×1080` / generation `1`；停止节点的 decoder/VO 掉帧计数为后端
累计计数（不同样本为 `2–3`），不是 DWM 或桌面像素掉帧。该开关只在 Windows Debug QA 生效，
生产路径不增加属性轮询；`dwm.evidence` 仍为 `unavailable-in-integration-test`，因此这批数据是
cache/decoder/VO/Texture 的可审计分段线索，不是“首个实际呈现帧”的最终验收。

桌面关联器还修复了 PowerShell StrictMode 下空 trace 事件数组被条件表达式展开为 `$null`
而触发的 `PropertyNotFoundException`；现在自动化 PlayerPage 输入即使没有唯一 trace 也会
保留 `playerInputEvents` 和 `ambiguous-multiple-traces-in-input-window`，不再整份报告
变成 `parse-failed`。这一修复只改善证据完整性，不改变输入、seek 或呈现逻辑。

最新同机真实 4K 长 GOP Debug 三编码复测已把连续扫描阶段聚合为
`keyboardExperience.smoothScanTrace.summary`，避免只看长 trace 行而漏掉停止/恢复长尾：

| 编码 | 首帧 ms | seek p50/p95 ms | 短按前/后 p95 ms | 长按前/后 p95 ms | 扫描命令→音频恢复 max ms | 停止 cache max s | 停止累计掉帧 max | Texture 代次 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| H.264 | 314 | 138/241 | 36/66 | 175/163 | 133.417 | 13.317 | 10 | 2 |
| HEVC | 284 | 157/199 | 57/83 | 161/185 | 153.990 | 11.483 | 13 | 2 |
| AV1 | 292 | 153/259 | 59/66 | 136/91 | 127.842 | 57.365 | 9 | 2 |

三组均为实际 `d3d11va-copy`，聚合证据仍是
`backend-runtime-snapshot-not-desktop-pixels`；扫描 `start→command`、
`command→stop_start`、`stop_start→complete` 也分别独立保留在 summary 的
`maxStartToCommandMs`、`maxCommandToStopStartMs`、`maxStopStartToCompleteMs`。
因此这些数字能定位 cache/解码/恢复阶段，但不能宣称“按键到首个桌面画面”已达到专业播放器水平。
原始匿名日志：
[`H.264`](/E:/LocalTagPlayer/.local/qa/turn-4k-h264-scan-summary-20260819.log)、
[`HEVC`](/E:/LocalTagPlayer/.local/qa/turn-4k-hevc-scan-summary-20260819.log)、
[`AV1`](/E:/LocalTagPlayer/.local/qa/turn-4k-av1-scan-summary-20260819.log)。

### QA-only：mpv `play-direction=backward` 可行性复核（2026-08-20）

为判断“长按后退是否应改成原生反向连续播放”，在同一 Debug MediaKit 会话中临时
设置 `play-direction=backward`，每 100ms 采样位置 20 次，并在 `finally` 恢复方向、
倍速、`video-sync`、`interpolation`、`framedrop` 和音频音高校正。该实验不挂接正式
快捷键，也不改变当前 latest-only keyframe preview 合同。mpv 官方文档将该方向标为
脆弱且通常更慢，故实验结果只能决定是否继续研究，不能直接升级为产品默认行为（见
[mpv 官方 manual](https://mpv.io/manual/stable/#options-play-direction)）。

| 编码 | 位置样本（目标→最小/最大 ms） | backward 距离 ms | 反向期间方向 | 硬解 | Texture 代次 | 恢复方向 |
| --- | ---: | ---: | --- | --- | ---: | --- |
| H.264 | 336607→336616/336616 | -9 | backward（位置不下降） | d3d11va-copy | 2 | forward |
| HEVC | 291769→291766/291766 | 3 | backward（仅 3ms 抖动） | d3d11va-copy | 2 | forward |
| AV1 | 258601→258601/258601 | 0 | backward（位置不变） | d3d11va-copy | 2 | forward |

三种编码均为 `no-sustained-backward-position`；属性读回在实验期间仍可能返回
`forward`，但运行态快照确认临时属性为 `backward`。因此当前证据不支持把 mpv
反向播放作为“丝滑”实现，正式长按后退继续保留 latest-only 关键帧预览；后续若要
实现双向连续扫描，必须另建可观测的实际呈现帧合同，而不是只看 `time-pos`。
稳定性矩阵会把该对象以 `qaReverseDirectionExperiment` 写入每个 backend 报告；
未启用时保留 `enabled=false/status=not-run`，避免把“未运行”误写成反向播放失败。
原始日志：
[`H.264`](/E:/LocalTagPlayer/.local/qa/reverse-direction-4k-h264-20260820.log)、
[`HEVC`](/E:/LocalTagPlayer/.local/qa/reverse-direction-4k-hevc-20260820.log)、
[`AV1`](/E:/LocalTagPlayer/.local/qa/reverse-direction-4k-av1-20260820-rerun.log)。

## 实体键盘到桌面像素的首批样本

真实 PlayerPage 的实体键盘门禁必须同时满足：Windows runner/`FLUTTERVIEW` 原生 QPC `WM_KEYDOWN`、页面 `player_keyboard_event` 语义回执、静态基线、有效桌面采样率和连续两帧像素变化。当前已取得的单样本（正式 MediaKit Texture、144 DPI、高码率 H.264 1080p60）为：

| 动作 | 按住时长 | Down→首个稳定像素 | 最长静止段 | 证据口径 |
| --- | ---: | ---: | ---: | --- |
| 短按前进 | 单次 | 159 ms | 152 ms | 原生 QPC + PlayerPage 语义 + DWM 像素 |
| 短按后退 | 单次 | 10 ms | 5 ms | 原生 QPC + PlayerPage 语义 + DWM 像素 |
| 长按前进 | 2478 ms | 2380 ms | 450 ms | 原生 QPC + PlayerPage 语义 + DWM 像素 |

这些是独立单样本，不得写成 p50/p95。长按前进的 QA 页先暂停建立静态基线，首次真实 L `WM_KEYDOWN` 到达后才恢复播放；该恢复仅存在于 Debug QA，避免把“暂停没有播放时钟”误判为渲染丢帧。`2380 ms` 仍是必须继续拆分的 P0 长尾，后续要用 `PLAYER_SEEK_TRACE` 的 cache/demux、decoder、VO、Texture 代次与桌面 QPC 侧车分段，而不是继续提高 Texture 尺寸上限或用节流参数掩盖。

稳定性矩阵若在报告写回前失败，会为 backend 生成 `status=failed-no-report` 和固定 `failureCategory`；`current-texture-hwnd-matrix-20260819c` 的双后端均为 `exact_seek_position_unconfirmed`。随后测试改为立即吸收每个 latest-only seek 的异步错误、等待全部 Future，并修正 `loop-file=inf` 短片在队列动画期间跨尾部回绕的判定。最终 `current-texture-hwnd-matrix-20260819h` 的正式 MediaKit Texture 三种真实样本全部通过全屏、队列、交互 seek、模拟 DPI、快速切换和 10 秒长播：`seekFailureCount=0`，实际硬解 `d3d11va-copy`，队列帧总耗时 p95 `16.942 ms`、交互 seek 帧耗时 p95 `29.996 ms`、帧代理观察 p95 `261 ms`、Texture 代次差 `0`。QA-only child HWND 的布局/全屏/模拟 DPI/快速切换/长播通过，但精确 seek 有 `2/18` 次未确认、首帧观察 `15` 次超时，实际硬解 `d3d11va`；双后端总门禁仍为 failed，失败被保留为 HWND 呈现/确认闭环证据，不伪装成可发布。完整报告见 `.local/qa/current-texture-hwnd-matrix-20260819h/player-backend-stability-matrix.json`。

随后单独重跑 HWND 证据类型 smoke（`.local/qa/current-hwnd-evidence-kind-20260819/hwnd-stability.json`）：日志中的超时阶段已明确写为 `frame_evidence=native-rendered-child-hwnd`，不再出现 `native-rendered-texture`。该 smoke 仍有精确位置未确认，不能被解释为 HWND 播放已稳定。

## 长 GOP 策略校准

脚本同时写出 `long_gop_policy.json`。它用六个长 GOP case 的最高 p95 推荐页面的运行时档位：

- `<= 750ms`：64ms（约 15fps）预览，750ms 最终新帧阈值；
- `<= 1200ms`：96ms（约 10fps）预览，1200ms 阈值；
- `> 1200ms`：125ms（约 8fps）预览，1800ms 阈值。

运行时不为交互额外扫描媒体 GOP；它保留 latest-only 合并并以同一会话的关键帧 seek 耗时选择上述档位。只有持有完整 12-case manifest 的机器产出结果后，才可以调整这些校准边界。

若超过最终新帧阈值仍无帧号变化，播放器保留临时静音而不播放旧落点音频；下一次 seek 会建立新会话。`frame_evidence=native-rendered-texture` 表示正式 Texture 原生桥已经完成共享纹理复制，`frame_evidence=native-rendered-child-hwnd` 只表示 QA child HWND 的原生渲染计数，`native-rendered-output-unknown` 表示兼容后端没有声明输出类型，`estimated-frame-number-fallback` 表示兼容路径的 mpv 估算；录屏分析不得把这些代理视为同等的屏幕呈现证据。该失败路径写入 `PLAYER_SEEK frame_presentation_timeout`，供诊断而非作为成功收敛。

### 反向桌面像素复核补充（2026-08-19）

反向桌面像素矩阵此前可能在约 10 秒基线执行首个 10 秒回退，导致目标落在 66ms 附近；该静止画面不能证明反向呈现失败。Debug-only QA 现把长素材基线移到 18–30 秒，正式 PlayerPage 和 seek 合同不变。新构建在真实 4K H.264/HEVC/AV1 各 3 次 `backward` virtual-key 矩阵均形成页面语义回执和 DWM 像素变化，Down→DWM p95 分别为 `905/907/914 ms`，最终硬解均为 `d3d11va-copy`，decoder/total drop 为 `0`；Texture generation 仍出现 `0/1/2|3` 和 2–3 次重建。这些不是实体 QPC→DWM 延迟，且首帧约 0.9 秒仍不符合专业级体验。

为验证暂停 keyframe seek 是否需要显式 `frame-step -1 seek`，同一 AV1 基线做了 Debug-only 对照：启用逐帧触发 p95 `1249 ms`，关闭为 `915 ms`。实验已撤掉；当前证据不支持把逐帧触发作为反向呈现修复，下一步应继续沿 cache/decoder/VO/Texture/DWM 分段寻找真正长尾。
