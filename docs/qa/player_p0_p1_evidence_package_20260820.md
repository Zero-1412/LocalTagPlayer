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
dart run tool/generate_player_p0_manifest.dart -Output .local\qa\player_p0_manifest.json -MaxCandidates 6 -MaxProbes 24 -ProbeTimeoutSeconds 20
~~~

生成器若发现默认 Debug 可执行文件，会把其 SHA-256 写入 manifest；找不到时保留空值，
由验证器判为 `unknown`。本机首次有限探测结果为 `partial`，已选 `2/12`、缺少 `10`、实际探测 `6` 个候选；
已确认的两个样本是 1080p H.264 长 GOP `5.27s` 和 4K H.264 短 GOP `1.00s`。
由于本轮设置了全局 probe 上限，这个结果只证明 manifest 生成链可用，不能证明其它
编码/分辨率没有样本；未补齐前 12-case 覆盖继续记 `unknown`。

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

| 指标 | 当前判定 | 依据 |
| --- | --- | --- |
| 正式 Texture 三编码动作探针 | pass（证据管线） | 已有真实 PlayerPage、页面语义、DWM 匿名变化和运行态聚合 |
| 12-case 固定 manifest 完整性 | unknown | 当前工作树没有提交本机媒体路径，尚未有一份统一匿名 manifest |
| 三编码/两分辨率/短长 GOP 的统一 P0 报告 | unknown | 既有矩阵分散在多个日期目录，尚未由同一 manifest 关联 |
| decoder drop | pass 或 fail 按 action 分列 | 运行态有值时非零失败；没有值不补零 |
| VO drop | unknown（已有矩阵多数不可用） | 运行态没有可靠 VO drop 字段时不能判通过 |
| 稳态 total drop | unknown | 既有动作样本缺少独立 10 秒分母 |
| 首个真实 DWM 帧 | pass/fail 按已有 action 分列 | 只采用桌面合成像素报告 |
| P0 总体 | unknown | 统一 12-case、首播和完整稳态证据尚未闭环 |

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
| A-B loop | A/B/清除命令、状态和释放 | A→B 重复播放画面 | 命令可用；可见性为 unknown |
| 外挂字幕 | 加载/轨道/关闭命令和释放 | 字幕在真实 Texture 上可见、同步 | 命令可用；可见性为 unknown |

“命令可用”不升级为“功能完成”。在可见性证据出现前，P1 只能报告命令合同通过和
可见性 unknown。

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
