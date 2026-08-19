# CURRENT_TASK.md

# 2026-08-19 · 播放器真实性能基线与 Texture/HWND 对照（P0：真实 PlayerPage 拖动矩阵已闭环，实体键盘待验收）

- 2026-08-20 建立 P0/P1 证据包合同：`tool/qa/player_p0_manifest.template.json` 固定
  `1080p/4K × H.264/HEVC/AV1 × short/long GOP` 的 12 个内容 case，并预留首次播放、
  短按前/后、拖动、长按前/后和全屏七类 action；新增
  `tool/validate_player_p0_evidence.ps1`，只接受实际 DWM 终点并把每项严格分为
  `pass/fail/unknown`，缺少 10 秒稳态分母、VO/逐帧时间戳或实体 QPC 不补成通过。
  当前原始本机 manifest 为 `partial`，装配后的统一门禁为 `fail`（unknown 仍单独保留）；
  阶段 B 已按现有同机报告作出决策：QA-only HWND 精确 seek/首帧不稳定，记录为“HWND QA 路径不可发布”，
  不继续用 HWND 校准正式 Texture。P1 命令/资源 QA 与真实可见性 QA 已在
  `docs/qa/player_p0_p1_evidence_package_20260820.md` 分离；真人长按、发布 GPU/驱动、
  稳定 HWND A/B、跨显示器/DPI 和真实控制可见性保留为外部清单。

- 2026-08-20 继续补齐本机 manifest 链：新增 `tool/generate_player_p0_manifest.dart`，
  只读 library.db，使用 ffprobe 实际关键帧间隔分类 short/long GOP，并对单候选和全局
  probe 数量设硬上限；SQLite FFI 需显式加入 `windows/tools/sqlite` 到 PATH。首次有限
  探测生成 `.local/qa/player_p0_manifest.json` 为 `partial`，已选 `2/12`、缺少 `10`、
  实际探测 `6`；确认 1080p H.264 long GOP `5.27s`、4K H.264 short GOP `1.00s`。
  这不是其它 case 不存在的结论，仍保持 P0 覆盖 `unknown`，不把探测预算内的缺失冒充
  外部硬件阻塞或通过。

- 2026-08-20 将 manifest 探测预算改为六个 resolution×codec bucket 轮询；在
  `maxCandidates=6/maxProbes=24/timeout=20s` 下已选 `5/12`、缺少 `7`、实际探测 `23`，
  新增匿名 `candidateCounts` 便于解释预算覆盖。当前已确证 1080p H.264 short/long、
  1080p HEVC short、4K H.264 short、4K HEVC short；仍未把缺失 case 写成通过。

- 2026-08-20 将 GOP 探测改为首段 30 秒 packet 关键帧窗口，并均匀抽样每个 bucket；
  `maxCandidates=24/maxProbes=144/timeout=20s` 已选 `10/12`、缺少
  `1080p-av1-short-gop` 与 `4k-av1-long-gop`，实际探测 `49`。`probedGopCounts` 确认
  4K AV1 只有 `1 short/0 long`，1080p AV1 为 `0 short/1 long`；匿名
  `probeOutcomeCounts` 进一步确认 1080p AV1 的另一候选是约 `2.00s` 的目标区间外 GOP，
  4K AV1 没有第二个 long 候选。不把这两个 case 补成通过，也不把类别缺失写成探测失败。

- 2026-08-20 对 root 文件树做补充只读审计：177 个未索引媒体中只有 1 个 1080p AV1，
  ffprobe 最大关键帧间隔 `6.25s`（long GOP），没有 4K AV1 未索引候选；因此两个 manifest
  缺口不是 library.db 漏扫造成，仍保持 `unknown`，不把未进入应用资料库的文件强行加入正式报告。

- 2026-08-20 新增 `tool/assemble_player_p0_evidence.ps1`，按目录名和矩阵摘要的显式
  合同把已有真实 PlayerPage/Texture 证据装配到新的本机 manifest；当前装配目标为 `33` 个
  case/action、保留 `51` 个未装配 action，须由重装配结果确认。不能把新拖动证据外推到其它
  GOP、未绑定 startup 或 fullscreen，也不把缺失素材、VO drop 或稳态 total drop 写成通过。
  这完成了报告可复核链，但仍有未绑定拖动、其它 case 的首播/全屏、VO drop 或稳态 total drop；
  这些都不能写成通过。

- 2026-08-20 将 `presentedChanges[].qpcUs` 的后续 DWM 呈现节奏纳入统一 P0 校验器：
  长按输出连续变化间隔 p95/最大值/每轮变化数，长按与拖动输出最长无变化段；复用
  `p95≤50ms`、`max≤100ms`、每轮至少 5 个变化和最长静止 `≤500ms` 的既有标准。
  反向仍按 latest-only 关键帧预览审计，字段不足继续为 `unknown`，不宣称连续反向扫描。

- 2026-08-20 用当前 manifest 的 1080p H.264 short case 试跑正式 PlayerPage forward
  `3` 个独立 Debug Texture 会话：均完成打开、最终 `d3d11va-copy` 和释放，但
  `player_keyboard_event` 缺失、桌面像素 `0/1` 成功且每轮超时，矩阵拒绝生成 p95；
  随后用同一页面、同一素材和同一动作切换 QA-only `virtualKey` 注入，结果仍为
  `player_keyboard_event` 缺失、桌面像素 `0/1` 成功；该负证据只记输入/可见性
  `unknown`，不归因于 H.264 解码性能，也不据此修改播放器业务输入路径。

- 2026-08-20 对上述输入缺口做了相邻真实 PlayerPage Slider 对照：同一 Texture 输出链能写出
  `progress_slider_start/committed`，单样本桌面像素通过；因此 QA 输出文件和页面挂载链可达。
  新增默认关闭的自动化 native-route 诊断后，scan-code 与 virtual-key 均只观察到
  `native_keyboard_message(up)`，没有 `down`，目标原生焦点类别为 `FLUTTERVIEW`，页面仍无
  `player_keyboard_event` 或 DWM 变化。该结果把根因边界收窄到当前桌面 SendInput Down/Flutter
  消息投递链；诊断文件明确不具备真人 WM_KEYDOWN/UP 资格，不进入实体输入或 p50/p95。

- 2026-08-20 将 P1 precision controls 的可见性 QA 与命令/资源 QA 分离：Debug-only
  `run_player_precision_controls_dwm_qa.ps1` 只读正式 PlayerPage 的 DWM 合成匿名网格，
  不发送输入、不保存截图；precision QA 现在实际从 A 播放到 B 再回到 A，并在外挂字幕
  `sub-add` 前后建立独立静止/呈现窗口。H.264/HEVC/AV1 各一轮均观察到
  `ab_loop_cycle_complete=true`、`player_resources_released=true`，但逐帧、A-B 和外挂
  字幕的 DWM 可见性均为 `unknown`；最新三轮采样为 H.264 `26.7 fps`、HEVC `26.9 fps`、
  AV1 `27.4 fps`，仍低于 30fps 最低门禁，不能把命令结果或后端帧号写成真实可见性通过。
  H.264/HEVC 的 A/B DWM 变化为 `pass`，AV1 仍为 `unknown`；最新匿名证据目录为
  `.local/qa/precision-dwm-buffered-{h264,hevc,av1}-20260820_*`。

- 2026-08-20 为 P1 新增 `playback_rate_complete`：正式 PlayerPage Debug 会话真实读回
  `speed=1.5` 并恢复原倍速，未写持久化设置；新增
  `tool/validate_player_p1_precision_evidence.ps1`，按控制分别输出 command/resource、
  visible 和 overall。最新 H.264 rate 会话的四项命令/资源均为 `pass`，但 DWM 采样
  `27.3 fps < 30 fps`，四项 visible/overall 均保持 `unknown`，不把倍速命令可用写成
  真实可见性完成。

- 2026-08-20 重新评估已有正式 PlayerPage/Texture 矩阵：1080p 三编码的 shortForward、
  shortBackward、drag 各为 `3/3` 有效，首个 DWM p95 分别为 H.264 `81/92/343 ms`、
  HEVC `86/94/307 ms`、AV1 `86/93/362 ms`；页面语义、decoder drop、最终硬解为 pass，
  VO/稳态分母/稳态 Texture 重建为 unknown。longForward 的连续呈现门禁在 H.264/HEVC
  失败，AV1 首帧 `1105 ms` 且最长无变化 `950 ms`；longBackward 三编码连续门禁失败，
  仍明确是 forward continuous 与 backward latest-only 的分离证据。4K drag 三编码各 `7/7`
  有效，首个 DWM p95 `351/293/287 ms`，但部分运行态字段缺失，整体保留 unknown。

- 2026-08-20 用 manifest 已选的 1080p H.264/HEVC short GOP 素材各完成一轮正式
  PlayerPage/Texture 精确拖动 `3/3` 独立 Debug 会话；H.264 Down→DWM p50/p95
  `331/355 ms`、Up→画面 `99/100 ms`，HEVC 为 `257/293 ms`、`39/62 ms`，有效捕获均
  约 `115–119 fps`，最终硬解均为 `d3d11va-copy`，decoder/total drop 为 `0`，Texture
  generation 均为 `0/1/2` 且重建 `2` 次，资源释放均有回执。目录已加入显式装配，VO drop、
  稳态分母与其它未覆盖动作继续保持 `unknown`。

- 2026-08-20 用 manifest 已选的 1080p H.264/HEVC/AV1 long GOP 素材各完成一轮正式
  PlayerPage/Texture 精确拖动 `3/3` 独立 Debug 会话；首个 DWM p95 为 `408/517/364 ms`，
  最长无变化段为 `387/500/358 ms`。三组有效捕获约 `111–118 fps`，最终硬解均为
  `d3d11va-copy`，decoder/total drop 为 `0`，Texture generation 均为 `0/1/2` 且重建
  `2` 次，资源释放均有回执；已加入精确装配，VO drop 和稳态分母继续保持 `unknown`。

- 2026-08-20 将正式 PlayerPage `playerFullscreen` 纳入独立 3-session 矩阵，并修正 P0
  validator 的全屏结构指标：fullscreen 的 `p95InputDownToGeometryMs` 只进入独立的
  `fullscreen-window-geometry-settled`，不能读取像素字段的 0 ms，更不能冒充视频首个真实
  DWM 帧。10 个已有素材 case 均 `3/3` 有效；几何 p95 为 H.264 short/long `45/47 ms`、
  HEVC short/long `44/44 ms`、AV1 long `64 ms`，4K H.264 short/long `44/50 ms`、HEVC
  short/long `52/50 ms`、AV1 short `50 ms`。全部保留 `fullscreen_settled`、Texture 代次
  和资源释放证据；视频首帧保持 `unknown`，缺少 manifest 素材的 1080p AV1 short 与 4K AV1
  long 仍为 `unknown`。

- 2026-08-20 为正式 PlayerPage startup 建立 Debug-only 的 `startup-marker.json` 与探针
  附着握手：窗口显示后、`runApp` 前固定 UTC 标记，探针以同机 QPC/UTC 映射作为起点，
  随后以第一个持续中心 DWM 变化为终点，再独立等待 `ready.json` 证明产品页面可达。
  1080p H.264 short startup 已完成 `3/3` 独立会话，显式使用启动动作最低 `40 fps` 采样
  门槛（启动初绘竞争下实测 `66.8–102.3 fps`），并在 Texture id + duration readiness
  之后才接受中心像素变化；首个真实 DWM p95 为 `1257 ms`，三轮为 `1257/795/805 ms`，
  因启动预算 `1000 ms` 判 `fail`，资源释放和最终 `d3d11va-copy` 均有回执。默认 `80 fps`
  的单次试跑因实测约 `55 fps` 严格失败，不能被改写为通过；其余 startup case 仍为 `unknown`，
  后端 `first_frame_ms` 继续不作为 DWM 证据。

- 2026-08-20 建立“流畅性”规范语义与有限工程门禁：依据 W3C Media Capabilities 的
  `smooth=目标帧率下无掉帧`、W3C VideoPlaybackQuality 的总帧/掉帧/展示延迟分层、mpv
  的 VO/显示同步说明、ITU-T P.1203 的首播加载与 stalling 指标，以及 Android CDD
  的每 10 秒掉帧参考上限；项目门禁明确为首个实际 DWM 帧、稳态掉帧、最长无变化和
  长按后续呈现节奏。规范映射与工程阈值见 `docs/qa/player_smoothness_standard_20260820.md`，
  可执行评估器为 `tool/evaluate_player_smoothness_standard.ps1`。对已有证据的首次执行：
  1080p AV1 长按前进首帧 p95 `1055 ms`、最长无变化 `1155 ms`，连续扫描门禁失败；
  4K AV1 反向单轮首帧 `273 ms`、后续 DWM 变化间隔 p95 `141.901 ms`，首帧预算通过但
  连续扫描失败，仍只能称 latest-only 关键帧预览。数值门禁是本项目工程目标，不冒充
  国际规范；缺少 10 秒稳态分母、VO 掉帧或实体 QPC 的项目统一记 `unknown`。

- 2026-08-19 继续按修正后的语义门禁补齐三编码动作矩阵：HEVC 4K/144 DPI 拖动
  `3/3`（fastPreviewThenExact）Down→DWM p50/p95 `391/401 ms`、Up→DWM
  `157/171 ms`、最长静帧 `393 ms`；短按前进/后退 `3/3` 分别为 `93/100`、
  `94/105 ms`；900ms 长按前进/后退 `3/3` 分别为 `832/850`、`274/281 ms`。
  AV1 拖动 `3/3` 为 `368/388`、`138/182 ms`、最长静帧 `381 ms`；短按前进/后退
  `3/3` 为 `75/94`、`94/100 ms`；900ms 长按前进/后退 `3/3` 为 `106/106`、
  `272/285 ms`。所有有效轮次均含 `player_keyboard_event`（键盘动作）、Slider
  回执（拖动）、约 118–121fps 桌面采样、最终 `d3d11va-copy` 与资源释放；这些仍是
  SendInput scan-code/Win32 鼠标自动化，不是实体 WM_KEYDOWN/QPC 证据。HEVC 长按前进
  p95 `850 ms` 与 AV1 拖动 p95 `388 ms` 是当前真实可感知长尾，不能用平均值掩盖。
  原始证据位于 `.local/qa/current-semantic-matrix-hevc-drag-20260819_190209424`、
  `.local/qa/current-semantic-matrix-av1-drag-20260819_190050174` 及同前缀的
  HEVC/AV1 短按、长按目录。
- 2026-08-19 补充桌面探针的持续呈现变化证据：每个动作除首个像素变化外，匿名保留
  后续 DWM 指纹变化的 QPC/UTC、相对/基线差异和尺寸；trace 关联器新增
  `targetMs`、`nextPresentedChangeUtcUs`、`traceToNextPresentedChangeMs` 及动作首/末
  呈现计数。H.264 反向单次复核已观察到 `presentedChangeCount=5` 和约 `15–50 ms`
  的后续变化，说明“首帧之后是否持续变化”已有可审计字段；但自动化动作的输入锚点仍
  是估算 UTC 窗口，尚未成为实体 WM_KEYDOWN/QPC→首个/后续 DWM 帧验收，也没有把像素
  指纹误称为解码帧数。focused 探针契约 14/14、PowerShell 语法检查通过。
- 2026-08-19 自助 Windows 窗口复核：尝试从当前可见媒体库进入播放器并实际发送一次
  `J` 短按时，系统已有安装版单实例接管 Debug 启动；该实例选中的资料库条目弹出
  “视频打开失败 / unplayable media”，因此没有形成有效的 `player_keyboard_event` 或
  首个 DWM 帧样本。该结果记录为安装版/样本可达性阻塞，不归因于快进性能，也不写入任何
  p50/p95；实体 WM_KEYDOWN/QPC 门禁仍需在唯一可播放 Debug 实例中完成。
- 2026-08-19 已用可播放的独立 Debug PlayerPage 自助完成 H.264 4K 原生输入短按矩阵：
  前进、后退各 7/7，Windows 原生观察器均写出 `native_keyboard_message` 的 Down/Up
  QPC，页面均写出 `player_keyboard_event`，桌面采样约 108–118fps；Down→首个 DWM
  变化前进 p50/p95 `111/118 ms`，后退 `104/121 ms`。这是完整的
  `WM_KEYDOWN/UP QPC → PlayerPage → DWM` 管线自证，但按键由 Windows 自助控制发送，
  不代表人体按压间隔；长按仍需可保持按下的实体 Down/Up 证据。原始目录为
  `.local/qa/current-self-manual-{forward,backward}-*`。
- 2026-08-19 补齐 1080p/144 DPI 正式 Texture PlayerPage 自动化合同：H.264 短按前/后
  `81/81`、`81/92 ms`，拖动 `325/343 ms`（松手 `89/91 ms`），长按前/后
  `69/75`、`268/271 ms`；HEVC 短按 `86/86`、`91/94 ms`，拖动 `294/307 ms`
  （松手 `71/81 ms`），长按 `85/99`、`266/281 ms`；AV1 短按 `82/86`、`80/93 ms`，
  拖动 `334/362 ms`（松手 `92/122 ms`），长按前/后 `1094/1105`、`262/263 ms`。
  三编码每项均 3/3、页面语义/Slider 回执、约 110–120fps、最终 `d3d11va-copy`；
  AV1 长按前进首帧 p95 `1105 ms`、最长静帧 `950 ms`，运行态 total drop `6–7`，
  是新的高优先级呈现长尾。1080p 全屏几何切换 H.264/HEVC/AV1 分别为 `47/46/47 ms`，
  各 1 次切换；这些是自动化桌面证据，不是实体人体时序。原始目录按
  `.local/qa/current-semantic-matrix-1080p-*` 与 `.local/qa/current-semantic-gate-1080p-*-fullscreen-*` 保存。
- 2026-08-19 对 AV1 1080p 长按前进的呈现尾延迟继续做分段复核：在不改变播放器业务的
  前提下，桌面探针现在对自动长按首个稳定画面额外保留 250ms 观察窗，并按匿名 DWM
  指纹变化记录后续呈现（仍不冒充解码帧数）。新样本首个 DWM 变化为 Down→`1055 ms`、
  Up→`149 ms`，最长静帧 `1155 ms`；首帧后 245ms 内观察到 8 个匿名呈现变化，说明
  首帧之后确实有小幅连续合成，但并没有消除首帧前约 1.05s 的空窗。对应 trace 仍显示
  `smooth_scan_command_complete` 约 11ms 内完成，运行态 `d3d11va-copy`、Texture
  generation `2`、cache 约 400s，停止阶段 total drop `6`；根因继续落在解码/VO 到
  Texture/DWM 的首帧长尾，不能用“命令已完成”或单个像素变化宣称丝滑。探针契约新增
  观察窗与指纹连续变化门禁；原始目录为 `.local/qa/current-semantic-matrix-1080p-av1-long-forward-postdwell-20260819_200000002`。
- 当前仍未完成的验收项：①实体 `WM_KEYDOWN/UP QPC` 长按前/后各自的 Down→首帧及
  尾部 p50/p95（Windows 自助 `press_key` 只能证明短按，不能保持按下）；②反向落点的
  每次真实 DWM 帧及连续帧节奏，当前仍是 latest-only 关键帧预览；③正式 Texture 与
  QA-only child HWND 的同机同素材对照，现有 HWND 精确 seek/首帧确认失败；④首播首个
  实际呈现帧、短/长 GOP 与 1080p/4K 三编码的统一 12-case manifest；⑤非强制软件回退在
  发布构建、不同 GPU/三编码上的矩阵。逐帧/A-B/外挂字幕已完成命令与资源释放 QA，
  但还没有逐帧 DWM、A-B 重复播放和字幕可见性验收；可调倍速也只有接线，没有真实窗口
  节奏预算。以上任一项未闭环前，不宣称专业播放器级“丝滑”或任务完成。
- 2026-08-20 目标范围审计：当前“全部完成才结束”把本机可执行的 Debug 证据、真人
  key-down/key-up、等价 HWND 后端、发布 GPU 矩阵和五项专业控制绑定成一个无停止点的
  任务；“不改业务功能的基线”与“基线稳定后实现控制”还形成依赖环。已将要求拆为
  P0 证据包、P1 控制包和外部验收清单；固定了“每编码/分辨率/动作至少 3 个有效独立
  会话、失败不入 p50/p95、DWM/运行态证据分级”的本机停止条件。审计全文见
  `docs/qa/player_goal_scope_audit_20260820.md`。这不是降低目标，而是防止继续用
  自动化轮次替代真人/另一后端/发布硬件证据。

- 2026-08-20 对抗式门禁复核发现并修正自动键盘语义回执丢失：PowerShell 探针调用中
  的续行注释曾使 `ExpectedInputEvidencePath` 未传入，旧自动化样本只有 DWM 像素变化，
  不能证明快捷键命中 PlayerPage，已全部降级为不可作语义验收的历史证据。修正后缺少
  `player_keyboard_event` 的样本会拒绝进入 p95；同一真实 4K H.264、144 DPI 的新
  PlayerPage scan-code 矩阵已验证短按前进/后退、900ms 长按前进/后退各 `3/3`，其
  Down→DWM p50/p95 分别为 `100/112`、`100/112`、`81/93`、`293/316 ms`，语义回执
  三轮均为真。该修正只提高证据真实性，不改变用户播放逻辑；HEVC/AV1 及拖动需按同一
  门禁重跑，实体 WM_KEYDOWN/QPC、反向真实首帧和 HWND 对照仍未完成。
- 2026-08-20 修正门禁后 HEVC 4K/144 DPI 先完成短按前进 `3/3`，Down→DWM p50/p95
  `93/100 ms`、Up→DWM `47/50 ms`，三轮均有 `player_keyboard_event`、最终
  `d3d11va-copy` 和资源释放。短按后退两次复跑均出现独立会话启动失败（各有 2/3 有效），
  因 p95 门禁要求 `3/3` 已明确判无效，不把 `93/179 ms` 混入结论；需继续在冷却/启动
  稳定后补齐 HEVC 后退及长按，AV1 也尚未按修正门禁重跑。
- 2026-08-20 长按测量合同校正与三编码复测：自动化桌面像素探针已从按下时刻开始采样，
  在同一循环发送 Repeat/Up，按住期间首帧出现时 `Up→首帧` 保持 null，避免旧版“先松键
  再采样”伪造约 900ms p95。真实 PlayerPage Debug QA 现走 SendInput scan-code；H.264/
  HEVC/AV1 4K、144 DPI、900ms 自动长按后退各 3/3 有效，Down→DWM p50/p95 分别
  `81/98 ms`、`186/201 ms`、`83/99 ms`，最长按住静帧 `95–107/136–205/120–125 ms`，
  有效采样约 `118–120 fps`，最终硬解均 `d3d11va-copy`，decoder/total drop 均为 0，
  Texture generation 仍观察到 2–3 次启动/尺寸重建。这些是自动化“按住期间桌面确实推进”
  基线，不是实体 WM_KEYDOWN/QPC p50/p95，也不是反向 seek 落点已达专业级丝滑的结论；
  单次 H.264 trace 还显示首个 DWM 变化早于第一次 reverse keyframe 命令，必须继续拆分
  QA 恢复播放首帧与反向预览段。原始证据位于
  `.local/qa/current-reverse-hold-scancode-20260820/{h264-matrix,hevc-matrix,av1-matrix}`。
- 2026-08-20 正式反向路径新增按帧让渡/最短 dwell（`reverse_preview_frame_wait_start/complete`），
  focused `player_seek_coordinator_test.dart` 与桌面探针契约均通过；该改进只合并
  latest-only 目标、避免反向命令洪水，尚未证明原生反向连续解码或 DWM 连续帧节奏。旧的
  900ms virtual-key 后采样数字不再作为当前首帧结论，但保留原始目录供审计。
- 2026-08-20 补齐目标中明确的专业控制入口：正式 MediaKit 后端通过同一 NativePlayer
  提供 `frame-step`/`frame-back-step`、`ab-loop-a`/`ab-loop-b` 清除，以及 `sub-add`
  外挂字幕；PlayerService 用可选边界串行转发，播放器上下文菜单和逗号/句号快捷键已挂载。
  A/B 点只存当前页面会话，外挂字幕只经 `FileSystemAdapter` 选择，不写设置、队列或媒体库。
  这完成的是控制能力接线与 focused service contract，不等于逐帧呈现、A-B 反复播放或外挂
  字幕在真实三编码矩阵中的运行验收；P0 实体输入、反向连续呈现和发布级硬解回退矩阵仍未完成。
- 2026-08-20 硬解降级 Debug E2E 已补证：QA 强制软件解码的真实 4K HEVC PlayerPage
  运行态出现 `hwdec_current=no`，健康采样写出 `software_decode_confirmed`，并自动执行
  与降级条相同的安全重新打开回调；匿名日志从 `open_generation=1` 收敛到 `2`，两代均
  保持 `hwdec_current=no`、Texture 首帧证据和资源释放。该自动重开只由 Debug QA 环境变量
  触发，正式用户仍必须点击“重新打开”；尚未完成非强制软件回退在不同 GPU/三编码上的发布矩阵。
- 2026-08-20 补跑 H.264 4K/144 DPI 正式 PlayerPage 桌面像素矩阵：拖动 `3/3`（fastPreviewThenExact）
  Down→DWM p50/p95 `443/456 ms`、短按前进 `3/3` 为 `116/123 ms`、短按后退在提高独立会话
  冷却后 `3/3` 为 `111/122 ms`；900ms 自动长按前进 `3/3` 为 `87/101 ms`、后退 `3/3`
  为 `95/106 ms`。长按首帧均在松键前出现，因此 `Up→首帧=null` 是有效合同，不是零值；运行态
  同时记录到硬解 `d3d11va-copy`、Texture 代次/重建和 decoder/total drop。该矩阵是 SendInput
  scan-code 自动化桌面证据，不是实体 WM_KEYDOWN/QPC；HEVC/AV1 同口径完整复跑以及首次播放/全屏
  汇总仍未形成统一 12-case manifest。
- 2026-08-20 完成三编码真实 PlayerPage precision controls QA：独立脚本在 H.264/HEVC/AV1
  各自的正式 MediaKit Texture 会话中均通过 `frame_step_complete`（估算帧号分别 `900→901`
  或同等单帧推进）、A/B `30.016–30.033s→32.016–32.033s`、清除后 `ab-loop-a/b=no`，以及
  `sub-add` 后 `track-list` 可见；三轮均写出 `precision_controls_qa_complete` 和
  `player_resources_released`。这证明原生命令、页面串行边界和会话资源生命周期已可运行，
  但逐帧首个 DWM 帧仍不是实体 QPC 证据。
- 2026-08-20 扩展 Debug 软件解码安全恢复 E2E 到 H.264/AV1：两种编码均确认
  `software_decode_confirmed requested=d3d11va-copy actual=no`，触发一次安全重新打开，
  `open_generation=1→2`，两代 Texture 首帧和最终 `player_disposed/released` 均落盘；H.264
  长按运行态 total drop 最高 `9`，AV1 最高 `22`，仍明确属于强制软件解码 QA，不代表正式
  用户在不同 GPU 上的回退概率或发布级性能预算。
- 2026-08-20 反向长按 QA 口径修正：自动化后退不再在 Down 后恢复正向播放，改为保持静态基线并
  直接等待 reverse-preview，避免自然播放帧伪装成 seek 呈现。真实 4K H.264、144 DPI、900ms
  长按后退 `3/3` 有效，Down→DWM p50/p95 `296/317 ms`、最长静帧 `277–299 ms`；trace 明确
  写出 `reverse_preview_frame_wait_*`、目标 `23s→5s` 和 `frame_presented=true`，Texture 代次
  未在动作中变化，硬解 `d3d11va-copy`、decoder/total drop 0。证据仍是自动化桌面合成 + 后端
  帧代理，尚未有实体 QPC，也未证明反向连续帧节奏达到专业播放器。

- 2026-08-19 反向基线复核：此前 AV1 反向失败样本的静止基线约在 10 秒，首个 10 秒回退只到 66ms，不能用来判断新帧是否送达。Debug-only QA 页现将长素材静态基线移到 18–30 秒区间；正式 PlayerPage、播放语义和 Texture 上限不变。修正后刚构建 Debug 在同一真实 4K H.264/HEVC/AV1、144 DPI、900ms virtual-key 后退矩阵各 3/3 通过：H.264 Down→DWM p50/p95 `904/905 ms`、HEVC `903/907 ms`、AV1 `909/914 ms`，有效采样 `100.4–118.5 fps`、`captureReadFailures=0`、页面 `player-keyboard-event` 语义成立、硬解最终均 `d3d11va-copy`、decoder/total drop `0`。每轮运行态均见 Texture generation `0/1/2|3` 与 `2–3` 次重建；这些是自动 virtual-key 对照，不是实体 WM_KEYDOWN/QPC p50/p95，且约 0.9 秒首帧已证明仍不专业级丝滑。原始证据位于 `.local/qa/current-reverse-formal-baseline30-20260819/{h264,hevc,av1}/matrix`。
- 2026-08-19 反向逐帧触发实验结论：在同一 AV1 基线下 Debug-only `frame-step -1 seek` 3/3 虽通过，但 Down→DWM p50/p95 `1236/1249 ms`，关闭该实验的同基线对照反而为 `910/915 ms`；因此已撤掉后端实验代码，未把逐帧命令带入正式路径。该结果排除了“暂停 keyframe seek 必须额外 frame-step”这一假设，剩余 P0 根因仍在真实反向预览/Texture/解码呈现长尾，不能继续靠 seek 节流承诺专业体验。
- 2026-08-19 QA 证据合同修正：新增纯函数 `playerQaReverseBaselineTarget` 及 focused contract，避免反向动作落在首帧附近产生假阴性；该函数只存在 Debug QA 页，不写播放进度、不修改用户数据。验证：focused player/seek/desktop-pixel tests 全部通过，`flutter analyze` 通过，`flutter build windows --debug` 成功；完整 `flutter test` 仍受既有非播放器架构迁移预算、设置页行数和 `smoke.sidebar.rescan` 三项失败阻塞，未将其归因于本改动。

- 目标：在不改变用户播放语义、后端默认选择或数据的前提下，用本机真实 H.264/HEVC/AV1、1080p/4K、高码率及长 GOP 素材建立 Debug 基线；区分正式 MediaKit Texture 与 QA-only child HWND，而不是继续凭主观感受调整 seek 节流。
- 当前修改：新增 Debug-only 正式 MediaKit Texture QA 页与 Win32 输入→DWM 合成像素探针。探针只保存匿名像素指纹、差异、QPC 时间和窗口几何；不保存帧、路径、标题或视频 ID。真实 `PlayerPage` 现可通过前台 Win32 `Down → Move → Up` 在可见完整 Slider 上交替拖动，且在控制条 hover 稳定后才开始计时；显式 Debug QA 环境下还要求 `PlayerProgressSlider.onChangeEnd` 的匿名回执，否则不让隐藏点击条的像素变化进入拖动 p95。基线后正式进度条默认采用两阶段：先请求目标附近关键帧、再用普通精确 seek 以 100ms 容差收敛，音频继续等最终新帧门禁；QA 能显式退回单次精确路径作为对照。短按/长按继续用真实 scan-code。实体键盘 Debug 门禁会把前进/后退动作传入隔离页面，提示与 ready 握手分别显示 `L`/`J`，避免人工验收按错方向。门禁成功后还会输出 `desktop-pixel-trace-correlation.json`，按 UTC 侧车关联 `PLAYER_SEEK_TRACE` 与 DWM 首变更，但明确不替代不同源时钟的 QPC→DWM p95。`hwnd` 仍只能显式作为对照，绝不校准正式路径的长 GOP 策略或晋级默认后端。稳定性矩阵现同时消费当前首帧阶段并把匿名 `reverseKeyframeTrace` 挂到 `qaReverseKeyframeTrace`，且写回每个 backend 的独立 `reportPath`，避免日志已有分段证据而报告丢失。
- 探针可靠性补强（QA-only）：Win32 `GetDC`/客户区短暂不可读现在在静态基线和动作采样中使用有界重试，单独累计 `captureReadFailures`，仍严格保留静态基线、连续两帧变化、输入语义和有效帧率门禁。`.local/qa/current-agent-forward-retry-20260819i` 的 3 轮失败均为 `captureReadFailures=0`、页面没有输入语义/像素变化，未混入统计；随后干净重跑 `.local/qa/current-agent-forward-retry-20260819j` 3/3 通过，Down→DWM `100/104 ms`、Up→画面 `57/62 ms`、有效采样 `115.0–117.5 fps`，说明重试没有把输入失败或静态画面伪装成成功。
- 自动化键盘证据门禁补强（QA-only）：正式 `PlayerPage` 的 `forward/backward/playerFullscreen` 探针现在也传入 `player-input-events.jsonl`，要求页面 `player_keyboard_event` 语义回执；专用 Texture QA 未传该文件时仍保持原对照合同。`.local/qa/current-agent-forward-semantic-20260819l` 3/3 通过且每轮 `inputSemanticEvidence=player-keyboard-event`，Down→DWM p50/p95 `106/119 ms`、Up→画面 `61/77 ms`、有效采样 `111.9–116.4 fps`、`captureReadFailures=0`。中途 `.local/qa/current-agent-forward-semantic-20260819k` 的第 3 轮只到 `bootstrap_started`，按独立会话启动失败排除，未生成 p95。
- 已确认的桌面证据：1080p H.264 独立 Debug 会话七次鼠标反向交互均在请求的 120fps 采样下观察到合成像素变化，输入 Down 到新画面 p50/p95 为 `107/118 ms`。资料库只读选出的真实 4K H.264 / HEVC / AV1 样本均在正式 Texture、3840×2160 初始窗口、独立七进程矩阵中全部通过（有效采样约 120–125fps）：H.264 Down→画面 `81/122 ms`、Up→画面 `10/49 ms`、最长静帧 `114 ms`；HEVC 为 `80/85 ms`、`7/12 ms`、`74 ms`；AV1 为 `76/82 ms`、`7/12 ms`、`74 ms`。它们只覆盖专用已暂停 QA 页的单击→实际合成画面，不能替代真实 PlayerPage 的拖动/长按结论。4K/150% DPI、显式 1.0% 像素门槛下的真实 PlayerPage 精确拖动已分别完成 H.264/HEVC/AV1 的 7/7 独立进程：H.264 Down→画面 `335/367 ms`、Up→画面 `140/174 ms`、最长静帧 `360 ms`；HEVC 为 `276/286 ms`、`82/90 ms`、`277 ms`；AV1 为 `444/454 ms`、`249/257 ms`、`445 ms`。三组都含完整 Slider 回执、静态基线、连续两帧变化、120fps 左右采样和产品资源释放。H.264 与 960 窗口 `360/362 ms` 同量级，不能归咎为单纯 4K/DPI 合成压力；但 AV1 的 454ms 明确是用户可感知长尾。4K/150% 全屏门禁的输入到窗口几何变化为 `37 ms`，切换前静态基线和稳定后均为 Texture 第 2 代、3840×2160；初始 4K 窗口已明确观察到 `1920×1080 -> 3840×2160` 的旧 Texture 注销、新 Texture 注册，不能把该次全屏结果外推为“从不重建”。没有提高 Texture 上限。
- 最新 4K 长 GOP integration 分段摘要已结构化写入 `keyboardExperience.smoothScanTrace.summary`：H.264/HEVC/AV1 首帧为 `314/284/292 ms`，seek p95 为 `241/199/259 ms`，长按前进/后退帧代理 p95 为 `175/163`、`161/185`、`136/91 ms`；扫描命令到音频恢复最长为 `133.417/153.990/127.842 ms`，停止 cache 最长为 `13.317/11.483/57.365 s`，累计掉帧最多为 `10/13/9`，Texture 代次均为 `2`、实际硬解均为 `d3d11va-copy`。三组 summary 都明确 `backend-runtime-snapshot-not-desktop-pixels`，因此是 cache/decoder/VO/恢复分段证据，不是实体键盘到首个 DWM 画面的验收；原始日志位于 `.local/qa/turn-4k-{h264,hevc,av1}-scan-summary-20260819.log`。
- 当前 Debug 4K H.264 实窗自动化复核在清理外部 UIA/Accessibility 观察器后稳定通过：正式 PlayerPage、960 窗口、144 DPI、自适应 Texture 开启、Texture generation `3`，有效采样 `117.4–115.8 fps`，Down→DWM 首变更 `100 ms`，stderr 无 `ERROR/Exception`。此前连续三次 `flutter_windows.dll + 0xc0000005` 发生在桌面控制观察器仍持有语义树客户端时，已用 Windows Application Error 与同条件重跑确认是污染环境证据，不纳入播放器性能结论。桌面门禁文档现明确要求真人输入前关闭/重置任何 UIA 客户端。
- 新增正式 PlayerPage 的 Debug-only `playerFullscreen` 门禁并完成一次干净 4K H.264 实窗复核：1280×720 逻辑窗口、144 DPI、有效采样 `115.5 fps`，Enter 到窗口几何变化 `50 ms`，只发生一次几何切换；`renderer-events.jsonl` 显示启动阶段 Texture `1920×1080 → 3840×2160 → 1600×900`、generation `0→1→2→3`，全屏稳定后仍为 generation `3`、`1600×900`，说明本次全屏没有额外 Texture 重建，但启动尺寸协调仍有真实重建成本。该样本的页面键盘枚举为 `other`（Enter 不属于 J/L seek 语义），因此只作全屏/Texture 结构证据，不进入 seek p50/p95；stderr 仅有已知 ffmpeg cover type 提示。
- 同一正式 PlayerPage、1280×720 逻辑窗口、144 DPI 的 HEVC/AV1 `playerFullscreen` 复核也通过了有效桌面采样：HEVC `113.0 fps`、Enter→几何 `44 ms`，AV1 `115.7 fps`、Enter→几何 `50 ms`，均只有一次几何切换，稳定全屏后均保持 Texture generation `3`、`1600×900`。两者启动轨迹均为 `1920×1080 → 1600×900`，没有 H.264 会话中观察到的 `3840×2160` 中间代次；这说明 Texture 启动/尺寸重建路径受编码和解码器时序影响，不能用 H.264 的单次结构证据外推三编码一致性。该动作仍只验证全屏/Texture 结构，不进入实体 seek p50/p95。
- QA-only 关闭自适应尺寸的 HEVC/AV1 对照进一步确认：两者都从 `1920×1080` 重建到原生 `3840×2160`，generation `2`，全屏稳定后不再重建；HEVC 有效采样 `121.5 fps`、Enter→几何 `51 ms`，AV1 `113.9 fps`、`50 ms`。正式自适应路径收敛到 `1600×900`、generation `3`，因此当前证据支持继续保留自适应/稳定档位，不支持直接把正式上限提高到 4K。
- 独立矩阵脚本现在把每轮 `ready.json`、`renderer-events.jsonl` 与 `PLAYER_MEMORY_STAGE`/runtime trace 汇总为匿名 `runtimeEvidence`：保留最终 `hwdecCurrentFinal`、首帧证据、Texture generation/重建次数/尺寸、resize 状态以及 decoder/VO/total 掉帧最大值；`empty/unavailable` 保持 `null`。三轮真实 PlayerPage 4K H.264 自动化前进（仅验证报告管线，不是实体键盘结论）Down→DWM p50/p95 为 `98/105 ms`、Up→画面 `52/60 ms`、最长静止段 `99 ms`、采样 `112.5–115.2 fps`，最终硬解均为 `d3d11va-copy`，Texture 重建事件 `2–3` 次，decoder/VO 本动作没有 runtime snapshot 因而保持 null。矩阵同时修正 PlayerPage 前进/后退动作应标为 `win32-keyboard-virtual-key`，不再误标为 scan-code。
- 干净 Debug 会话补齐真实 PlayerPage 的 7 轮 virtual-key 对照（不是实体键盘证据）：前进 Down→DWM p50/p95 `94/107 ms`、Up→画面 `50/59 ms`，后退 `93/96 ms`、`49/52 ms`，两组均 `7/7`、有效采样约 `112–117 fps`，最终硬解 `d3d11va-copy`。一次早期后退首轮只在 `bootstrap_started` 后退出，已保留为无效生命周期并未混入 p95；该对照证明干净窗口的 Focus/输入链可达，不改变真人 QPC 门禁仍缺的结论。摘要见 `.local/qa/current-4k-h264-realpage-forward-7run-diagnostic-20260820` 和 `.local/qa/current-4k-h264-realpage-backward-7run-diagnostic-20260820b`。
- 2026-08-20 QA-only mpv 反向播放复核已在同一 Debug MediaKit 会话对真实 4K H.264/HEVC/AV1 各采样 20 次位置：三组均未形成持续反向推进（目标→最小位置 `336607→336616`、`291769→291766`、`258601→258601 ms`），运行态临时方向均为 `backward`，最终均恢复 `forward`；硬解均为 `d3d11va-copy`、Texture 代次均为 `2`。该结果只证明当前反向连续播放试验不可作为可靠产品方案，正式长按后退仍是 latest-only keyframe preview；原始日志分别为 `.local/qa/reverse-direction-4k-h264-20260820.log`、`.local/qa/reverse-direction-4k-hevc-20260820.log` 和 `.local/qa/reverse-direction-4k-av1-20260820-rerun.log`。
- 本轮再次启动正式 PlayerPage 的 `manualLongForward` 实体门禁（4K H.264、144 DPI、自适应 Texture、静态基线已就绪），但 30 秒等待窗口内没有收到 `FLUTTERVIEW` 原生 `WM_KEYDOWN/UP`；输出 `.local/qa/manual-physical-long-forward-20260820c` 仅含 `native_keyboard_observer_ready` 与 `manual_keyboard_input_waiting`，没有 `native_keyboard_message`、`player_keyboard_event` 或像素摘要。该结果只记录为“本轮无实体输入”，不进入任何 p50/p95，也不把超时误归因于播放器长按卡顿。
- 最新一次 4K H.264 `manualForward` 单样本（`.local/qa/current-manual-forward-live-20260819d`）完成正式 PlayerPage/Texture 静态基线：`focusReady=true`、Texture generation `3`，原生观察器 `installed=true/childInstalled=true/runnerInstalled=true/topLevelActive=true`；但 30 秒内仍只有 `native_keyboard_observer_ready`，没有 `native_keyboard_message` 或 `player_keyboard_event`，门禁以“未收到实体键盘匿名 FLUTTERVIEW QPC 锚点”退出。该证据排除了观察器未安装和页面 Focus 未就绪，但没有操作者按键，仍不得生成短按 p50/p95。
- 2026-08-20 自主 Computer Use 反向短按复核（`.local/qa/current-computeruse-manual-backward-20260820`）确实向前台 Debug PlayerPage 发送了 `J`，但只产生 `player_keyboard_event(action=other)`，没有 `native_keyboard_message`/FLUTTERVIEW QPC 锚点；实体门禁按证据合同失败，未生成任何物理输入 p50/p95。该结果说明桌面控制 API 的原子 `press_key` 不能冒充实体 WM_KEYDOWN，也没有把本轮超时数字归因于播放器。
- 为拆分自动化连续扫描的呈现段，新增 Debug-only `HoldMilliseconds`：隔离 QA 页在首个 virtual-key 前进 Down 后才恢复播放，实体 `manualLong*` 和正式页面不读取该开关。4K H.264、144 DPI、900ms virtual-key 长按各 7/7：前进 Down→DWM 首画面 p50/p95 `908/912 ms`、最长静帧 `2–9 ms`、有效采样 `110.5–120.4 fps`；后退（latest-only 关键帧预览）为 `907/916 ms`、`1–7 ms`、`114.4–120.9 fps`。前进运行态快照仍为 `d3d11va-copy`、decoder 掉帧 `0`、VO 计数不可用、累计掉帧 `8–9`；两组均不是实体 WM_KEYDOWN/QPC p50/p95，且约 900ms 首帧等待仍不符合专业播放器体感。首次未恢复播放的同合同矩阵 7/7 `pixel_change_timeout` 已保留在 `.local/qa/current-4k-h264-realpage-forward-longhold-7run-20260820`，不与修复后结果混算。
- 同一 900ms virtual-key 长按合同已补齐 HEVC/AV1：HEVC 前进/后退均 7/7，Down→DWM p95 `1029/916 ms`、最长静帧 `108/4 ms`，前进运行态硬解 `d3d11va-copy`、decoder 掉帧 `0`、累计掉帧最高 `15`；AV1 前进 7/7 为 `1040 ms`、最长静帧 `1025 ms`、Up→画面 p95 `131 ms`，硬解 `d3d11va-copy`、decoder 掉帧 `0`、累计掉帧 `14–15`。AV1 后退 7/7 全部 `pixel_change_timeout`，但页面仍收到 Down/10 次 repeat/Up，trace 写出首次关键帧回退后连续 `seek_command_complete`，随后 `new_video_frame_timeout`/`native_rendered_frame_timeout`；这不是输入缺失，而是当前 latest-only 反向预览在该 4K AV1 长 GOP 上没有形成实际 DWM 画面。所有结果均为 virtual-key 自动化，不进入实体 p50/p95。
- 反向 trace 修正：旧键盘/拖动 `2.7 s` 数值包含 seek coordinator 的位置确认，已重新标为“协调器完成后到帧号代理”，不得作为首个呈现帧。现在在非零确认窗口中额外写出 `position_confirmation_start` 与 `position_confirmation_complete|superseded|timeout`，将逻辑位置等待和真实首帧拆开；键盘预览的 `confirmationTimeout=0` 不产生该段。暂停源帧真正送达后，七次反向 keyframe trace 的命令 p95 为 `2 ms`、后端帧号代理 p95 为 `15 ms`、Texture 代次差为零；但 `absolute+keyframes` 会落在目标前 `0.675–8.167 s`，这是长 GOP 关键帧预览跳跃的真实语义问题，不等价于 Texture 合成卡顿。当前 Debug 4K H.264 复测（`current-4k-h264`）进一步得到短按后退 p95 `99 ms`、长按后退帧代理 p95 `238 ms`、反向 trace 命令 p95 `0 ms`、命令到帧代理 p95 `3 ms`，7 次 Texture 代次差均为 `0`，硬解为 `d3d11va-copy`；该样本没有重现 2.7 秒后端长尾，但仍不是实体键盘到 DWM 的最终证据。随后按正式页面合同把 integration 键盘协调器的位置确认设为 `Duration.zero`，同一真实 4K H.264 七次复测得到短按后退 `80 ms`、长按后退 `139 ms`、反向命令 `0 ms`、命令到帧代理 `39 ms`、Texture 代次差 `0`；摘要见 `.local/qa/current-reverse-trace-zero-confirmation-20260819-summary.json`，仍明确标记为后端帧代理而非桌面像素。`reverseKeyframeTrace.segmentTrace` 现在明确分出命令完成、命令后 cache/decoder/VO 快照、后端帧代理、Texture 代次差与 DWM unavailable 边界；不可用属性保留 unavailable/null，不伪造零掉帧。
- 本轮补强反向/拖动的 Debug-only 分段证据：`PlayerSeekCoordinator` 现在在 `seek_command_complete`、`native_rendered_frame|presented_frame_fallback` 和 `native_rendered_frame_timeout` 各自排队写出同一组 cache、decoder、VO、hwdec、Texture 尺寸/代次与呈现证据快照；属性读取经单尾链串行且不阻塞下一次 seek，生产运行没有额外读取。这样旧的 2.7 秒长尾可以直接区分“命令后缓存/解码等待”“后端已交付但 Texture/桌面未呈现”以及“根本没有新帧”，不再只依赖位置或单一帧号代理。Focused `player_seek_coordinator_test.dart` 已覆盖命令完成和实际帧两个快照节点。
- 新接线后的真实 1080p H.264 MediaKit Texture smoke（`.local/qa/current-segmenttrace-followup-20260819c.log`）确认 7/7 keyboard/long-scan trace 同时落盘 `seek_command_complete_runtime` 与 `presented_frame_fallback_runtime`：命令到后端帧 p95 约 `15.3 ms`，Texture generation 全为 `1`，实际硬解 `d3d11va-copy`，decoder 掉帧 `0`，DWM 仍明确不可由 integration 观测。该结果证明分段管线接线正确，不把 estimated-frame-number fallback 冒充桌面像素。
- 最新 Debug 1080p H.264 smoke 已验证 `segmentTrace` 在真实 MediaKit 会话中 7/7 落盘：`d3d11va-copy`、反向命令 p95 `0 ms`、后端帧代理 p95 `15 ms`、Texture 代次差全为 `0`，但 DWM 证据明确为 `unavailable-in-integration-test`；这只验证分段管线，不替代 4K/长 GOP/实体键盘验收。
- 最新 Debug 构建的 4K AV1、144 DPI、正式 PlayerPage、900ms virtual-key 长按快退矩阵（`.local/qa/current-av1-segmenttrace-followup-20260819c`）按门禁真实失败：`7/7 pixel_change_timeout`，`successfulRuns=0`，因此没有生成 p50/p95。中间 5 个会话仍写出 12 条运行态快照：`framePresentationEvidence=texture`、首帧证据 `media-kit-texture+position-update`、`textureGeneration=0/1/3`（重建 2 次）、尺寸 `1600×900/1920×1080`、`adaptiveTextureSizingEnabled=true`、decoder/total drop `0`；`hwdec-current` 出现 `d3d11va-copy → no → d3d11va-copy`，最终恢复硬解。run-02 的反向 trace 明确经过 `native_rendered_frame_timeout_runtime`，等待 `2016 ms` 时仍是 Texture generation `3`、cache `49.962667 s`、decoder/total drop `0`；动作没有实体 QPC 输入窗口，不能冒充 WM_KEYDOWN→DWM p95。该结果强化“AV1 latest-only 反向预览未形成实际屏幕新帧”的 P0 证据，未修改反向策略或抬高 Texture 上限。
- 稳定性矩阵 runner 现在额外记录 `displayInventory`：每块屏的边界、原生分辨率、Windows 当前刷新率与逻辑 DPI；当前单屏实机探测到 `3840×2160 @ 160 Hz / 144 DPI`。报告同时写出 `physicalCrossDpiEvidence.evidenceKind=display-inventory-only` 和 `physicalWindowMoveConfirmed=false`，明确显示器模式观测不能冒充窗口跨屏移动、全屏合成或真实跨 DPI 通过；现有 `.local/qa/current-texture-hwnd-matrix-20260819h` 仍需重跑才会包含该字段。
- 新短时同机矩阵 `.local/qa/current-display-inventory-matrix-20260819` 已落盘：正式 MediaKit Texture 自动场景通过、实际硬解 `d3d11va-copy`，但 QA-only child HWND 仍因精确 seek/首帧代理失败保持总门禁 `failed`；同一报告确认当前是单屏 `3840×2160 @ 160 Hz / 144 DPI`，`physicalCrossDpiStatus=not-run-single-monitor`。该 10 秒/6 次切换运行只用于刷新环境与失败证据，不替代标准 30 分钟/18 次/真实跨屏门禁。
- 既有对照：正式 Texture 六个素材均为 `d3d11va-copy`；后端代理 p95 为 1080p H.264/HEVC/AV1 `480/223/199 ms`、4K `931/574/255 ms`。HWND 在 H.264 seek 代理较快，却在 HEVC/AV1 首帧和持续播放中失败/停滞，现有 HWND QA 路径没有取代正式 Texture 的证据。
- 同一真实 4K H.264 的新只读后端 trace 对照：正式 Texture 主 seek p95 `329 ms`、短按前/后 `47/80 ms`、长按前/后 `147/139 ms`、命令到帧代理 `39 ms`、`textureGenerationDelta=0`、`d3d11va-copy`；QA-only child HWND 主 seek `294 ms`、短按前/后 `131/106 ms`、长按前/后 `101/192 ms`、命令到帧代理 `73 ms`、`d3d11va`，证据为 `child-hwnd-visible+estimated-frame-number-proxy`。两者均非实体键盘/DWM 像素，不能直接宣称 HWND 更丝滑；完整稳定性矩阵因精确位置未收敛而失败，失败样本未混入该摘要，文件为 `.local/qa/current-texture-hwnd-seek-compare-20260819.json`。
- 稳定性矩阵脚本现在即使集成测试在报告写回前失败，也会为每个 backend 写出 `status=failed-no-report`、固定 `failureCategory` 和已从日志解析到的首帧/反向 trace；`current-texture-hwnd-matrix-20260819c` 明确记录 `exact_seek_position_unconfirmed`，不再把空 report 误当成未运行。随后修正测试为立即挂接每个 latest-only seek 的 error handler、等待全部 Future，并让短于场景总时长的 `loop-file=inf` 样本允许位置跨尾部回绕。最终 `current-texture-hwnd-matrix-20260819h` 中正式 MediaKit Texture 三种真实样本全部通过全屏、队列、交互 seek（18/18，`seekFailureCount=0`）、模拟 DPI、快速切换和 10 秒长播，实际硬解为 `d3d11va-copy`，队列帧总耗时 p95 `16.942 ms`、seek 交互 p95 `29.996 ms`、帧代理 p95 `261 ms`、Texture 代次差 `0`；QA-only child HWND 的布局/全屏/模拟 DPI/快速切换/长播通过，但 18 次精确 seek 有 `2` 次未确认、15 次首帧观察超时，实际硬解为 `d3d11va`，且原生计数现在明确标为 `native-rendered-child-hwnd` 而非 Texture；单独 smoke 日志已确认超时阶段同样使用该标签，报告位于 `.local/qa/current-hwnd-evidence-kind-20260819/hwnd-stability.json`；因此双后端总门禁仍为 failed。这是 HWND 测量与呈现闭环的真实失败，不把它抹平成“可发布”。
- P0 当前范围与阻塞：此前一轮矩阵出现过 ready 前退出，已保留为历史无效证据且未用于统计；本次同一正式 QA 合同已完成 H.264/HEVC/AV1 在 4K/150% DPI 的真实 PlayerPage 完整 Slider 拖动 7/7 矩阵，并取得实体短按前/后各 1 条、长按前进 1 条合法单样本。仍缺七个独立会话的实体短按/前后长按 p50/p95，以及这三种输入的同机正式 Texture 与 HWND 对照；长按前进单样本的 `2380 ms` 首帧长尾不能被少量样本平均掩盖。键盘 C# `SendInput` 仍不得作为实体证据。尝试同进程 re-arm 补样时 5/7 次不再是静态基线，方案已撤回且不纳入统计。
- P1 最小闭环：原先连续三次检测到“已请求硬解、实际软件解码”只写日志；现在会显示运行时提示并提供“重新打开”。本轮将确认状态固定为视频表面上的持久降级条，并保留“重新打开”和只读“诊断详情”入口，避免 Snackbar 消失后用户失去上下文。该动作不热切换当前 NativePlayer、不改硬解偏好或用户数据，而是经既有 latest-only open worker 按当前硬解设置重新建立当前媒体会话。真实素材上的降级与重试结果仍待验收。
- 持久降级条现在额外展示请求档位、`hwdec-current` 实际值和连续确认样本数（如 `请求 d3d11va-copy · 实际 no · 确认 3/3`），让“为什么卡/是否已降级”在视频表面可见；“重新打开”与诊断按钮仍不直接热改 NativePlayer。
- P1 诊断补充：诊断快照现在同时记录实际呈现输出路径（Texture/child HWND/unknown）以及软件解码回退确认状态和连续样本数，避免把“请求硬解”误读成“实际硬解”或把 HWND 计数误读成 Texture 呈现。该补充不改变播放命令、后端选择或恢复语义。
- P1 seek 合同：短按继续是单次 keyframe 预览；进度条拖动保持本地滑块/缩略图预览，松手后先提交关键帧快速请求、再由独立 latest-only 精确 seek 以 100ms 位置容差收敛，音频只在最终新帧门禁后恢复；移动事件仍不连续派发解码命令。4K/150% DPI 的正式 PlayerPage 两阶段 7/7 矩阵相对单次精确：H.264 Down p95 `367→351 ms`、最长静帧 `360→343 ms`；HEVC `286→293 ms`、`277→283 ms`；AV1 `454→287 ms`、`445→279 ms`。全部包含快速请求与最终精确确认的匿名回执，不能把 DWM 首帧强行归属为其中一段；结果支持将两阶段作为默认拖动合同，但不代表短按/长按已完成。长按后退仍是 latest-only keyframe preview，尚未达到与前进连续扫描对称的合同。
- 短按/长按反馈现在明确写出“关键帧预览”：短按告诉用户落点是关键帧语义，长按后退标成“连续快退（关键帧预览）”，不会把当前不对称的后退策略误报为连续反向播放；前进进入真正临时高速扫描时仍显示实际倍速。
- 真实 PlayerPage 门禁：新增显式 Debug-only 独立入口，以匿名单项挂载产品 `PlayerPage`、其正式 MediaKit Texture、快捷键和完整 Slider；不加载资料库，不持久化进度/设置/标签，退出先经过产品资源释放链。最初的拖动无效样本保留为前端错误证据：1280 逻辑宽度会挂载右侧常驻队列，按整个客户区 72% 计算的终点落在队列而非 Slider；150% DPI 下把逻辑底部间距错当物理像素还会落到 Slider 下方传输行。门禁现默认 960 无侧栏，并按目标 `GetDpiForWindow` 把 110 逻辑像素转换为物理坐标；新的 7/7 矩阵包含 Slider 回执和实际 DWM 呈现。4K/DPI 仍可显式覆写，不得把已定位的前端失败归因于解码、VO 或 Texture。
- 键盘门禁当前状态：真实 PlayerPage QA 已在 ready 握手中确认自身 `FocusNode` 已请求焦点；早期 C# `SendInput`/Accessibility 复测没有产生匿名 `player_keyboard_event`，不能把它们当实体键盘替身。现已新增 Debug-only 原生 `FLUTTERVIEW` 子窗口观察器，并增加顶层 runner 消息路由旁路：仅在 `LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA=1` 时为 `J/L` 消息写入匿名方向、Down/Up 与共用 QPC；`manualForward/manualBackward` 探针不注入按键，以该 QPC 到 DWM 首帧计时，并要求既有 `player_keyboard_event` 回执。`native_keyboard_observer_ready` 现在同时写出 child/runner 安装状态；最新构建已在 `SetChildContent` 建立父子关系后安装观察器，短门禁确认 `installed=true, childInstalled=true, runnerInstalled=true`；`manualBackward` 运行时握手还确认 `ready.json.manualKeyboardAction=backward`，页面会提示 `J`。本轮桌面控制逐轮置前 Debug 窗口并发送 `L/J` 已验证原生输入链可达，但这是自动化原生消息，不冒充人类实体键盘证据；严格 7/7 短按及前/后长按 p50/p95、Texture/HWND 同输入对照仍未完成。此前安装版的单实例接管、客户区捕获失败和 Texture 冷却期启动失败均保留为无效生命周期，不混入性能统计。QA 样本选择器已改为优先解析 Windows application-support 的 `com.example/local_tag_player/LocalTagPlayer/library.db`，并保持 SQLite 只读，避免环境中递归扫描 AppData 或遗漏真实库。不得把这些输入/采集失败错记为播放器性能，也不得以超时数字替代验收。
- Debug-only 长按门禁已独立为 `manualLongForward/manualLongBackward`：它不注入按键，要求原生匿名 QPC 文件同时出现 Down/Up，默认按住至少 `600 ms`，并在首个稳定像素后继续采样约 `250 ms`；短按与长按不得共用同一 p95。该链路只增强证据合同，不改变正式 PlayerPage 的快捷键或播放语义。
- 实体键盘首个有效样本已补齐：正式 PlayerPage/Texture、144 DPI、真实高码率 H.264 1080p60 下，`manualForward` 为 Down→DWM 首帧 `159 ms`，`manualBackward` 为 `10 ms`；两者都同时具备原生 QPC、`player_keyboard_event` 语义回执和约 110–116fps 有效捕获。`manualLongForward` 在静态基线后由首次真实 L 按下才恢复播放，按住 `2478 ms` 后通过，Down→首个稳定像素 `2380 ms`、最长静止段 `450 ms`；这只是三条单样本，不能冒充 p50/p95，且秒级长尾必须保留为 P0 调查证据。为避免把“暂停状态没有时钟”误判为播放器掉帧，QA 页新增仅 Debug 的 `native-keyboard-qpc-events.jsonl` 轮询恢复；正式页面和 seek 业务不变。样本见 `.local/qa/manual-physical-forward-20260819f`、`.local/qa/manual-physical-backward-20260819a`、`.local/qa/manual-physical-long-forward-20260819b`。
- 本轮改用桌面控制逐轮置前 Debug QA 窗口并发送 `L/J`，确认无需用户代按也能走完整原生输入链：5 个独立有效的前进短按单样本均有 `native-qpc-plus-utc`、`player_keyboard_event` 和 DWM 像素证据，Down→首变更分别为 `206/190/84/188/93 ms`，临时汇总 `n=5 p50=188 ms p95=206 ms`；该汇总不是正式 7/7 释放门禁。反向短按本轮也观测到原生 `J` Down，但三轮均因 GetDC 客户区读取/Texture 启动失败未形成有效像素样本，未把失败数字写入 p50/p95。当前桌面控制 API 只提供原子 `press_key`，不能伪装成持续 `600 ms` 的实体长按；`manualLong*` 仍不作结论。
- `manualLongBackward` 已启动独立会话并通过 ready/焦点握手，但本轮 30 秒没有收到实体 J，按“缺少实体输入”失败处理，未将超时数字写入任何延迟统计；后退长按仍缺真实样本。
- 输入管线修正：观察器已补到 `FlutterWindow::MessageHandler` 的 Debug-only 顶层旁路，并用 `lParam` 窗口去重；合成消息冒烟已同时产生 `native_keyboard_message` 与 `player_keyboard_event`，证明消息路由缺口已修复。该轮桌面捕获只有 `6.6 fps`，因此被探针拒绝且不进入任何性能统计；真实短按/长按仍必须由操作者实体按键完成。
- 关联口径修正：原生实体消息现在同时写入 QPC/UTC；`desktop-pixel-trace-correlation.json` 只把 `PLAYER_SEEK_TRACE` 纳入本次输入 Down 前 `500 ms` 至首像素/松键后 `1 s` 的动作窗口，窗口外 trace 标记为未匹配；多个动作窗口重叠时标记 `ambiguous-overlapping-pixel-action-windows`，不再用最近邻把其它按键误归因。UTC 仍只作窗口筛选，不能替代 QPC→DWM 延迟。
- 关联管线本轮补齐：`PLAYER_SEEK_TRACE` 现在优先使用 `wall_utc_us`，兼容旧 `wall_utc_ms` 并标注精度；每个像素动作只在“唯一动作窗口 + 唯一 trace id”时生成 `actionTraceSummaries`，否则保留 `no-trace-in-input-window` / `ambiguous-multiple-traces-in-input-window`，不强行归因。独立 standalone Debug PlayerPage 拖动 smoke 已实测 `117.6–119.8 fps`、Down→DWM 首变更 `497–528 ms`、Up→首变更 `291–296 ms`；最新会话输出 `available-estimated-utc-window`、`unique-trace`，`seek_command_complete→首像素` 约 `278 ms`，但输入是自动化 Slider 拖动且首帧证据仍为 `estimated-frame-number-fallback`，不得写入实体键盘 p50/p95。此前一次关联文件的 `parse-failed` 已由缺少初始化字段和 OrderedDictionary 展开错误修复，并由 focused/static + 第二次独立 smoke 复核。
- 本轮继续验证时发现原生侧车已同时写 `qpcUs`/`utcUs` 后，桌面探针仍按“qpcUs 是最后字段”截取，导致真实消息存在时误报 `未在时限内收到实体键盘的匿名 FLUTTERVIEW QPC 锚点`；现已改为按逗号或对象结束解析字段，并补充 focused 合同与 `-ValidateOnly` 编译验证。第一次复现目录保留了带 QPC/UTC 的无效失败证据 `.local/qa/current-physical-forward-20260819d`；修复后 `.local/qa/current-physical-forward-20260819e` 无实体输入、只有 observer ready，按缺输入处理，未生成性能摘要。
- correlation 三方字段补齐后，真实 PlayerPage Slider smoke 初次暴露 PowerShell StrictMode 下的可选字段和单事件数组问题；现已修复并由 `.local/qa/current-realpage-correlation-audit-20260819f/desktop-pixel-trace-correlation.json` 验证 `playerInputEventCount=2`、`traceLinkEvidence=player-semantic+unique-trace-estimated-input`、唯一 `traceId=1`。该样本 Down→DWM `490 ms`、Up→首变更 `295 ms`，仍只证明拖动合同和关联管线，不进入实体键盘 p50/p95。
- correlation 现同时识别 `win32-keyboard-*` 与 `manual-keyboard-*`；自动化键盘的页面语义会保留为估算窗口，实体键盘仍必须同时具备 native QPC/UTC 才能进入物理输入结论。
- 实体长按审查边界：已有 `.local/qa/manual-physical-long-forward-20260819b` 是旧 schema、旧原生侧车（无 `utcUs`）样本，日志只含 `audio_restore_start/complete`，没有 `smooth_scan_*` 阶段，不能倒推连续扫描的 cache/decoder/VO/Texture 分段；本轮自动化 `forward` 仍因未产生 PlayerPage 键盘语义回执而超时，未把该失败伪装成卡顿或长尾。必须重新取得真人长按并在同一会话保留微秒 trace，才能继续 P0 分段归因。
- 连续扫描分段采样已接入显式 QA 环境：真实 1080p H.264 MediaKit integration smoke 的 7 次长按前进均写出 `smooth_scan_start/command_start/command_complete/stop_*` 及 `_runtime` 快照；`d3d11va-copy`、Texture `1920×1080`、代次 `1`，`longForwardScan` 帧代理 p95 `108 ms`，后退向后 trace 命令 p95 `0 ms`、帧代理 p95 `12 ms`。扫描结束快照出现 VO 总掉帧 `2–3` 的后端事实，但 DWM 仍明确 unavailable，不能把它称为桌面掉帧或专业级体验通过。产品 PlayerPage 自动化 Slider smoke 在同一采样开关下仍通过 `118.3 fps`、Down→DWM `493 ms`、Up→DWM `287 ms`；它没有触发键盘扫描，不能替代真人长按。
- 保护：schema、`FilterQuery`/`TagQueryService`、来源 filtered queue、缩略图/媒体详情队列、稳定身份、用户播放设置和媒体文件均未改动；默认后端仍是 MediaKit Texture。
- 当前验证：Debug 真实运行、正式 `PlayerPage` 已从资料库进入并确认 4K H.264/Texture/来源过滤队列可达及暂停、桌面像素探针编译验证、单次精确与两阶段 H.264/HEVC/AV1 的 4K 7/7 独立 DWM 矩阵、当前 Debug 4K H.264 integration trace（短按后退帧代理 p95 `99 ms`、长按后退 `238 ms`、反向命令 p95 `0 ms`、命令到帧代理 `3 ms`、Texture 代次差 `0`）、focused 探针与 seek/Slider/硬解恢复合同测试、持久硬解降级条挂载合同、稳定性矩阵 trace 口径合同、输出表面证据边界修正、`current-texture-hwnd-matrix-20260819h` 双后端真实矩阵、完整 `flutter analyze` 与 Windows Debug build 均通过；播放器相关 focused 测试在拆分打开恢复叶文件后通过。全套 `flutter test` 仍明确失败于当前工作树既有的 `library_card_file_menu_test.dart` 菜单 smoke、`result_view_toggle.dart` 迁移预算（223>221）和 `settings_landing_list.dart` 超过 500 行无历史预算；这些不属于本轮播放器证据路径，未擅自改动。矩阵整体因 HWND 精确 seek/首帧确认失败而保持 failed，证据保存在未跟踪 `.local/qa/`，不含媒体内容。
- 下一步：4K/150% DPI 的真实 PlayerPage 单次精确与两阶段拖动都已在显式 `1.0%` 门槛、静态基线、连续两帧变化和匿名语义回执下完成 H.264/HEVC/AV1 的 7/7；该阈值不得与默认 1.5% 的结果混算。新 `manualForward/manualBackward` 可逐轮提示短按，`manualLongForward/manualLongBackward` 可逐轮提示长按并校验 Down→Up QPC、600ms 最小时长和 250ms 尾部采样；仍需操作者完成七个独立短按及前/后长按会话，且只汇总合法的 WM_KEYDOWN→DWM p50/p95。先分段追踪长按前进 `2380 ms` 的缓存/解码/VO/Texture 合成长尾，再做 Texture/HWND 同机实体输入对照；基础播放稳定后再实现倍速、逐帧、A-B loop 与外挂字幕。

# 2026-08-18 · 播放器长按快进连续扫描档位（第二层修复完成，实窗待独占窗口）

- 目标：消除长按快进在长 GOP/高码率视频上因重复随机 seek、显示同步插帧和输出等待叠加造成的卡住与跳顿，保证按住前进键时保持连续解码与稳定呈现节奏。
- 当前修改：物理短按在 KeyUp 只提交一次 keyframe seek；首个前进 `KeyRepeat` 后取消待发预览，进入至少 2× 的临时连续扫描。MediaKit/libmpv 在同一原生锁内保存真实倍速和 `video-sync`、`interpolation`、`framedrop`、`audio-pitch-correction`，扫描期改为 `video-sync=audio`、关闭插帧、`framedrop=vo`，并同锁读回确认；松键/换片后完整恢复并读回验证。临时状态不写入持久化设置；长按快退仍为 latest-only keyframe preview。
- 保护：仅新增可选 `PlayerFastForwardScanBoundary` 并保持 `PlayerService` 命令串行；不改 `PlaybackSession`、来源 filtered playback queue、进度条精确定位、继续观看、缩略图/媒体详情队列、schema、stable identity 或用户数据。无法完整取得原属性的后端只回退临时倍速，不猜测或覆盖用户呈现设置。
- 当前验证：seek controller 新增专用扫描档位优先级回归；服务边界覆盖专用/回退路径；快捷键门禁、位置栅栏、表面交互契约合计 38 项通过；`flutter analyze` 无问题，`flutter build windows --debug` 成功。
- 阻塞：实窗刚构建的 Debug 进程被已运行的安装版单实例接管；安装版路径与本次构建产物不同，未用旧版本冒充验收，也未终止用户进程。
- 下一步：关闭或退出安装版后启动 `build\\windows\\x64\\runner\\Debug\\local_tag_player.exe`，用长 GOP/高码率素材按住配置的前进键，确认高速期画面持续前进、不反复停帧，松键/切换媒体后速度、音量和显示同步设置立即恢复；再进行停止编辑后的独立只读审查与提交。

# 2026-08-17 · 全局 UI 标准盘点与主功能栏状态持久化（代码与 focused 验证完成，实窗待确认）

- 目标：检查媒体库、播放器、标签管理、设置和维护页的 UI 复用边界；统一共享交互表面，主界面功能栏首次默认折叠并记住用户上次展开/折叠状态。
- 当前修改：新增 `AppNavigationItem`，让主功能栏展开/折叠入口共享交互、选中语义和命中标准；品牌折叠入口复用 `AppInteractionSurface`；展示偏好复用既有 `library_sort.json`，旧文件缺字段默认折叠。
- 保护：保留主功能栏入口、tooltip、稳定 key、点击回调、展开/折叠尺寸和侧栏可达性；不修改 `FilterQuery`、`TagQueryService`、来源 filtered playback queue、缩略图/媒体详情队列、schema、stable identity 或用户数据。
- 当前验证：展示偏好、共享 token/导航入口和主界面侧栏 focused tests 通过；全局标准盘点记录在 `docs/design/UI_STANDARD_AUDIT_2026-08-17.md`。
- 阻塞：全局 `flutter analyze`、Windows Debug build 和停止编辑后的真实窗口检查尚待本轮完成；主工作树仍保留并行播放器核心改动，未修改或 stage 其文件。
- 下一步：停止编辑后做 independent 只读检查、analyze/build 和真实窗口复核默认折叠、状态恢复、文本缩放、high contrast、reduced motion 与无溢出。

# 2026-08-17 · 媒体库筛选工具栏高度统一（代码与实窗验收完成）

- 目标：统一截图所示筛选状态、搜索表面和筛选动作的顶栏高度，消除相邻控件上下边界不齐。
- 当前修改：三类控件统一复用 `libraryTopBarControlHeight` 的 48px 高度；保留收藏 chip、移除/清空筛选、搜索输入和结果统计行为。
- 保护：不修改 `FilterQuery`、`TagQueryService`、标签层级、来源 filtered playback queue、缩略图/媒体详情队列、schema、stable identity 或用户数据。
- 当前验证：`library_search_filter_status_test.dart` focused tests 6/6 通过；`flutter analyze` 与 `flutter build windows --debug` 通过；Debug 实窗进入“本地收藏”后检查对齐、结果更新和无溢出，未执行写入动作。
- 阻塞：无。
- 下一步：继续保留当前播放器核心并行改动；如需进一步统一 chip 内部视觉，再单独进行 UI diff 评审。

# 2026-08-17 · 设置首页可见工作区布局（代码与实窗验收完成）

- 目标：选择一个用户能立即感知的页面外壳，先调整设置首页的页面结构、内容密度、主次层级和可见动作，
  不再把 wrapper、key 或 tooltip 作为主要视觉交付。
- 当前修改：宽桌面设置首页显示左侧“设置导航”和“当前策略”摘要，右侧按播放设置、数据与维护、应用排列入口；窄窗口
  继续使用原有单列，并保留分组粒度以维持视口延迟挂载。
- 保护：`CacheSettingsPage` 仍是 section owner；保留 `settings.category.*`、二级页回调、设置持久化、返回路径和入口顺序；
  不修改 schema、`FilterQuery`、`TagQueryService`、filtered playback queue、`PlayerBackend`、缩略图/媒体详情队列、stable identity 或用户数据。
- 当前验证：settings landing 两个 focused widget tests 与 settings route focused test 通过，包含窄窗口入口可达性、宽桌面导航/策略摘要和
  150% 文字缩放无异常；`flutter analyze`、Windows Debug build 通过。使用同一 1340×804 窗口、同一隔离 profile 和同一设置入口形成受控
  Before/After 截图：Before 为单列长列表，After 为左侧导航/策略摘要加右侧分组入口。
- 阻塞：本轮无代码阻塞；全量 `flutter test` 的唯一失败仍是并行播放器核心改动使 `player_state_opening.dart` 达到 541 行、超过架构门禁，
  本轮未修改或 stage 该文件。
- 下一步：提交本轮四个文件并保留用户正在进行的播放器核心改动；核心改动停止后再独立修复 500 行架构门禁。

# 2026-08-17 · 播放器启动首帧与精确恢复解耦（代码完成，实窗待确认）

- 目标：普通新视频已有首帧路径即可播放；继续观看的精确恢复与画质属性收敛保留在必要场景，损坏媒体仍有界检测。
- 当前修改：打开事件重绑后，普通无有效恢复点的媒体先显式 `play()` 并解除打开占位，再执行可播放性检测和画质属性收敛；
  有恢复候选的媒体继续先完成完整门禁。打开请求 controller 只提前切换播放就绪状态，串行 worker 不变。
- 保护：不修改 `PlayerBackend`/`PlayerService` 命令边界、`PlaybackSession`、来源 `filtered playback queue`、缩略图/媒体详情队列、
  schema、stable identity 或用户数据；损坏/无 codec 证据仍进入 `unplayable_media` 失败面板。
- 当前验证：启动请求、打开代次、播放器服务和交互契约 focused 测试通过；analyze/build 与 Debug 实窗启动待本轮完成。
- 阻塞：无代码阻塞；实窗需在停止编辑后复测普通新视频与继续观看。
- 下一步：停止编辑后执行 independent 只读检查、`flutter analyze`、Windows debug build，并从媒体库分别验证新视频首帧与继续观看精确落点。

# 2026-08-17 · 播放器短按快进停顿修复（代码完成，实窗待人工确认）

- 目标：恢复键盘短按快进/快退只提交一次关键帧预览，消除松键时新增的第二次解码停顿；进度条和继续观看继续保留独立精确定位。
- 当前修改：移除键盘控制器的 `exactSubmit` 与 `short_exact_seek_*` 路径；KeyUp 只收敛当前关键帧预览，保留 `seekExactlyWithDiagnostics` 独立入口。
- 保护：不修改 `PlayerBackend`、`PlayerService` 命令边界、`PlaybackSession`、来源 `filtered playback queue`、缩略图/媒体详情队列、schema、stable identity 或用户数据。
- 当前验证：相关 focused 测试与播放器架构契约通过；`flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口已启动并进入媒体库，但点击视频时检测到并发用户输入，未完成实窗快进人工验证。
- 阻塞：真实窗口点击被并发用户输入中断。
- 下一步：用户可在 Debug 播放器中打开任意视频，短按 `L`/配置的快进键确认画面连续；确认后再继续当前上下文菜单 UI 外壳任务。

# 2026-08-17 · 播放器上下文菜单 UI 外壳重构（已完成）

- 目标：继续播放器 Phase 2，在文件动作弹窗之后收口右键上下文菜单，先建立
  `docs/design/PLAYER_CONTEXT_MENU_UI_SHELL_TARGET.md` 的 Before/After 目标，再显式复用播放器局部菜单主题、
  语义标签和稳定挂载 key。
- 当前修改：抽出无状态播放器上下文菜单项构建函数；保留 overlay 边界测量 `GlobalKey`，为视频信息与诊断检查增加
  稳定 `ValueKey`/Semantics，并显式传入播放器局部菜单颜色、elevation、形状以及菜单项正文/图标颜色。
- 保护：不修改菜单 anchor、返回值、信息/诊断分发、`withPlayerOverlaySurfaceOccluded`、`PlaybackSession`、
  `PlayerBackend`、来源 `filtered playback queue`、诊断采样、媒体详情/缓存队列、schema、stable identity 或用户数据。
- 当前验证：上下文菜单、诊断浮层、媒体控制外壳和架构契约 focused tests 通过；完整 `flutter test` 通过（630 passed，4 skipped）；
  `flutter analyze` 无问题。主工作树 Windows build 仍受旧进程占用，但从 `ce667de` 导出的隔离源码已成功构建；
  使用副本 profile 的真实 Debug 窗口从媒体库进入播放器，等待菜单进入动画完成后确认两个菜单项的正文/图标对比度、语义树、
  信息动作和诊断动作均可达，未触发写入。
- 保护：上下文菜单的 anchor、返回值、信息/诊断分发和 `withPlayerOverlaySurfaceOccluded` 保持不变；用户的播放器核心改动及
  相关状态/测试文件仍未被本轮 UI 任务修改或 stage。
- 阻塞：主工作树 debug 产物仍被 PID 37072 占用；该进程归属无法确认，未主动终止。隔离构建和实窗验收已完成。
- 下一步：收集菜单在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的反馈，进入下一个维护页面或共享浮层
  组件族；继续保护播放器入口、来源队列和用户数据边界。

# 2026-08-17 · 目录管理共享 Tooltip 外壳收口（代码完成，实窗通过）

- 目标：进入第三阶段维护页共享组件收口，把目录管理 root 路径提示接入 `MaintenanceTooltip`，先更新
  `docs/design/DIRECTORY_MANAGER_UI_SHELL_TARGET.md` 的 Before/After，再保留页面原有路径内容和动作 owner。
- 当前修改：`directory_manager_sections.dart` 从原生 `Tooltip` 迁移到维护页共享 Tooltip；目录管理 150% 页面测试增加
  具体 root 路径提示的 mounted 断言，避免只验证共享组件孤立存在。
- 保护：不修改目录 root、扫描、解除管理、返回、确认回调、`LibraryApplicationFacade`、schema、FilterQuery、
  TagQueryService、filtered playback queue、PlayerBackend、缓存/媒体详情队列、stable identity 或用户数据。
- 当前验证：目录管理 150% focused test、维护 feedback focused test、相关 `dart analyze` 通过；隔离源码 Windows Debug
  build 成功，真实窗口从媒体库进入目录管理，检查维护工作区标题、添加/重新扫描、root 卡片、路径显示、解除管理入口和返回路径，
  未触发写入动作。
- 阻塞：全量 `flutter test` 当前被工作树既有播放器核心改动触发的 `player_state_opening.dart` 541 行预算契约失败阻断；
  本轮未修改或 stage 该核心文件。
- 下一步：在核心改动停止编辑后重跑全量测试与主工作树 build，再继续 Missing/Relink 或共享 Menu/Tooltip/Snackbar 的实际调用迁移。

# 2026-08-17 · Missing / Relink 共享 Tooltip 外壳收口（代码完成，实窗页面通过）

- 目标：继续第三阶段维护页共享组件收口，把单条缺失路径和批量预览路径映射接入 `MaintenanceTooltip`，先更新
  `docs/design/MISSING_RELINK_UI_SHELL_TARGET.md` 的 Before/After，再保留 stable identity 说明和路径内容。
- 当前修改：`missing_relink_sections.dart` 与 `missing_bulk_relink_preview.dart` 从原生 `Tooltip` 迁移到维护页共享 Tooltip；
  页面级测试增加单条旧路径和批量旧/新路径映射的具体 tooltip 消息断言。
- 保护：不修改 `videoId`、fingerprint、mutable path、单条/批量 relink service、文件选择器、Repository 提交、确认、审计摘要、
  schema、FilterQuery、TagQueryService、filtered playback queue、PlayerBackend、缓存/媒体详情队列或用户数据。
- 当前验证：两个 Missing/Relink focused widget tests、全量 `flutter analyze`、隔离源码 Windows Debug build 通过；真实窗口从媒体库进入
  缺失与重新关联，检查空态、稳定身份保留说明、待处理区域、批量入口和返回路径，未执行文件动作。
- 阻塞：主工作树 build 被已有 `local_tag_player.exe` 文件锁定触发 `LNK1168`；全量 `flutter test` 仅被并行播放器改动使
  `player_state_opening.dart` 达到 541 行、超过架构契约 500 行阻断，本轮未修改或 stage 该核心文件。
- 下一步：在播放器核心改动停止后重跑全量测试与主工作树 build，再继续 Missing/Relink 150%/high contrast/reduced motion 反馈，或转入设置页/共享 Menu、Snackbar 的实际调用迁移。

# 2026-08-17 · 播放器文件动作弹窗 UI 外壳重构（已完成）

- 目标：继续播放器 Phase 2，在启动决策浮层之后收口删除文件与重命名文件两个可达动作弹窗，先建立
  `docs/design/PLAYER_FILE_ACTION_DIALOGS_UI_SHELL_TARGET.md` 的 Before/After 目标，再统一播放器局部主题、
  内容表面和稳定根 key。
- 当前修改：删除确认与重命名弹窗显式复用 `playerDialogThemeSurface`；增加 `player.delete.dialog`、
  `player.renameFile.dialog`，保留原有影响说明、回收站动作、偏好、输入校验和确认/取消 key。
- 保护：不修改 `FileCommandExecutor`、稳定 `videoId`、mutable path、播放状态恢复、`PlaybackSession`、
  `PlayerBackend`、来源 `filtered playback queue`、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据。
- 当前验证：删除确认与重命名 focused/widget tests、重命名播放恢复 smoke test、架构契约 57 项均通过；完整
  `flutter test` 通过（629 passed，4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。
  真实窗口使用精确构建产物从媒体库进入播放器详情并打开重命名弹窗，检查深色播放器浮层、输入焦点、扩展名只读、
  取消入口和底部动作空间；随后取消退出，未执行文件写入。删除弹窗危险路径保持 focused/widget 挂载与回收站语义验证，
  本次实窗未触发删除动作。
- 阻塞：无。
- 下一步：收集文件动作弹窗在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的反馈，决定继续收口播放器
  剩余动作浮层或转入下一页面外壳；本轮不扩展到文件事务、播放状态或队列业务。

# 2026-08-17 · 播放器启动决策与能力警告 UI 外壳重构（已完成）

- 目标：继续播放器 Phase 2，在信息/诊断弹窗之后收口“继续观看”与硬解能力警告两个启动前浮层，先建立
  `docs/design/PLAYER_STARTUP_DIALOGS_UI_SHELL_TARGET.md` 的 Before/After 目标，再统一播放器局部主题、内容表面和稳定根 key。
- 当前修改：继续观看弹窗与硬解警告弹窗显式复用 `playerDialogThemeSurface`；硬解规格正文复用播放器局部文字主题；
  增加 `player.resume.dialog`，保留硬解警告根 key、代理命令和现有动作 key。
- 保护：不修改继续/重播返回值、关闭默认策略、硬解兼容性评估、直接播放门禁、复制代理命令和取消路径；不修改
  `PlaybackSession`、`PlayerBackend`、来源 `filtered playback queue`、播放器启动顺序、ThumbnailService、媒体详情/缓存队列、
  schema、stable identity 或用户数据。
- 当前验证：继续观看与硬解警告 focused tests 通过，均确认新根 key 与原有动作入口；完整 `flutter test` 通过（629 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功。真实窗口从构建产物进入“继续观看”，检查 476 条来源队列、
  播放画面和右侧列表外壳；该样本直接恢复播放，未触发二次确认弹窗，因此弹窗视觉细节以 focused/widget 挂载证据为准，未冒充为
  运行时已打开。
- 阻塞：无。
- 下一步：收集启动弹窗在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，决定继续细化播放器残余浮层
  或转入下一页面外壳；本轮不扩展到播放启动语义、后端能力或队列业务。

# 2026-08-17 · 播放器信息与诊断 UI 外壳重构（已完成）

- 目标：继续播放器 Phase 2，在媒体控制之后收口视频信息与播放诊断弹窗，先建立
  `docs/design/PLAYER_INFO_DIAGNOSTICS_UI_SHELL_TARGET.md` 的 Before/After 目标，再统一弹窗局部主题、
  分组表面、容器语义和稳定 key。
- 当前修改：新增播放器内容弹窗局部主题 helper；视频信息与诊断弹窗显式复用 `playerWorkspaceTheme`，
  `PlayerDialogSectionCard` 改为实色 `Material`、弱描边、统一圆角与裁切，并补齐信息/诊断分组的稳定 key。
- 保护：不修改视频信息字段来源、媒体详情读取、诊断采样/timer/播放流订阅/复制摘要、关闭与滚动路径；不修改
  `PlayerService`、`PlayerBackend`、`PlaybackSession`、来源 `filtered playback queue`、`FilterQuery`、
  `TagQueryService`、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据。
- 当前验证：`test/player_diagnostics_dialog_test.dart` focused 通过，已验证诊断分组挂载、容器语义、采样流和卸载后停止响应；
  完整 `flutter test` 通过（629 passed，4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。
  Debug 窗口真实从媒体库进入播放器，打开上下文菜单中的视频信息与诊断检查，检查信息分组、诊断实时/分析/详细指标表面、
  详细指标滚动、复制/关闭入口和 Esc 返回；正文对比度修正后可读，无明显遮挡或溢出，未触发收藏、标签、设置或文件写入。
- 阻塞：无。
- 下一步：收集本轮播放器信息/诊断弹窗在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化播放器其它残余内容表面，或转入下一个页面外壳重构；继续保护来源队列、播放器会话和用户数据边界。

# 2026-08-17 · 播放器媒体控制 UI 外壳重构（已完成）

- 目标：进入播放器页面下一处 UI 外壳重构，把媒体控制弹窗的音轨、字幕、音画同步、章节四个默认 `Card`
  分组收敛为播放器嵌套工作区表面，先建立 `docs/design/PLAYER_MEDIA_CONTROLS_UI_SHELL_TARGET.md` 的
  Before/After 目标，再补真实挂载证据。
- 当前修改：`PlayerMediaControlSection` 使用播放器实色弱描边 `Material`、圆角和裁切；媒体控制弹窗显式
  使用 `playerWorkspaceTheme`，四个分组和弹窗增加稳定 key/容器语义。
- 保护：不修改 `readMediaControls`、选轨/章节/延迟回调、`PlayerService`、`PlayerBackend`、来源
  `filtered playback queue`、播放会话、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据。
- 当前验证：媒体控制交互、播放器架构挂载、主题 token、high contrast/150% 文字与滚动可达性 focused 测试通过；
  完整 `flutter test` 通过（629 passed，4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug`
  成功。Debug 窗口真实从媒体库进入播放器，打开并滚动媒体控制弹窗检查音轨、字幕、音画同步、章节四组表面、
  空态、关闭与返回；未触发选轨、延迟、章节跳转或其它写入动作。
- 阻塞：无。
- 下一步：收集媒体控制在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，再决定继续细化
  播放器其它残余内容表面，或转入下一个页面的 UI 外壳重构；继续保护来源队列、播放器会话和用户数据边界。

# 2026-08-17 · 标签中心 UI 外壳重构（已完成）

- 目标：进入第三阶段维护页面，把 Tag Manager 从匿名双栏表面收敛为“标签中心工作区”以及左侧“标签导航
  工作区”、右侧“标签 inspector 工作区”，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/TAG_MANAGER_UI_SHELL_TARGET.md`；页面与两个结构表面增加稳定 Semantics/key，
  实色 `Material` 统一圆角、弱描边和裁切；空详情与选中标签详情共用 inspector 边界。
- 保护：不修改 `_filteredTagRows` 展示筛选、搜索 `TextField` 链路、分组选择、详情焦点顺序、别名/隐藏/收藏/
  排序保存、批量 manual 增删、folder 来源门禁、合并/删除影响检查、`LibraryApplicationFacade`、schema、
  filtered playback queue、ThumbnailService、stable identity 或用户数据语义。
- 当前验证：Tag Manager 搜索、分组、页面挂载、150% 文字缩放、详情焦点/下拉锚点和高风险只读反馈 focused
  测试已通过；完整 `flutter test` 通过（628 passed，4 skipped）；架构迁移预算、`flutter analyze` 和
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入标签中心，检查空 inspector、真实 folder
  标签 inspector、属性/批量/高风险区域、滚动和返回媒体库；未触发任何写入动作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：收集标签中心在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，再审查
  共享 Dialog/Menu/Sheet/Tooltip/Snackbar 和播放器残余内容表面；继续保护标签维护、播放队列与用户数据边界。

# 2026-08-17 · 播放器交互 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把播放器交互从通用卡片收敛为“全屏播放列表工作区”和
  “播放器快捷键工作区”，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/PLAYER_INTERACTION_UI_SHELL_TARGET.md`；两个 panel 使用稳定 Semantics/key
  和实色弱描边边界；保留全屏边缘开关、快捷键录制、冲突提示、恢复默认和 Esc 安全出口。
- 保护：不修改 `CacheSettingsPage` 的状态 owner、`PlaybackSettings`、PlayerBackend、PlaybackSession、
  filtered playback queue、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据语义。
- 当前验证：交互意图 focused 测试、150% 文字缩放 focused 测试、设置首页页面级可达性测试和架构迁移预算
  测试已通过；完整 `flutter test` 通过（626 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入播放器交互，检查两个工作区、
  快捷键网格、底部 Esc 安全出口说明、滚动条和返回设置首页；未触发设置动作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：收集播放器交互页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化维护页外壳，或转入播放器页面外壳；不扩展到快捷键语义、播放后端或队列业务边界。

# 2026-08-17 · 视频画质与增强 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把视频画质与增强从通用卡片收敛为“视频画质与增强工作区”，
  先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/PLAYBACK_QUALITY_UI_SHELL_TARGET.md`；设置 panel 使用稳定
  `settings.playbackQuality.workspaceSurface` key 和 Semantics container 的实色弱描边边界；保留比例、
  缩放、色彩、流畅度、增强、HDR 确认和能力状态行。
- 保护：不修改 `PlaybackSettings`、`PlaybackSettingsController`、PlayerBackend 实际应用、HDR/流畅度确认与
  撤销、FFprobe/诊断边界、PlaybackSession、filtered playback queue、ThumbnailService、媒体详情/缓存队列、
  schema、stable identity 或用户数据语义。
- 当前验证：150% 文字缩放 focused 测试、设置首页进入画质页后检查工作区/HDR 开关/返回的页面级测试、HDR
  确认 focused 测试、流畅度确认/撤销测试和架构迁移预算测试已通过；完整 `flutter test` 通过（625 passed，
  4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库
  进入设置，再进入视频画质与增强，检查比例、缩放、色彩、流畅度、压缩增强、两个增强开关和两个能力状态行；
  长内容滚动后工作区底部完整、返回设置首页可达，无明显遮挡、裁切或溢出；未触发任何设置动作。
- 阻塞：无。
- 下一步：收集视频画质与增强页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入播放器交互设置或下一个页面的 UI 外壳重构；不扩展到播放后端、确认语义或队列业务边界。

# 2026-08-17 · 播放与解码 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把播放与解码设置从通用卡片收敛为
  “播放与解码工作区”及“播放会话缓存工作区”，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/PLAYBACK_SETTINGS_UI_SHELL_TARGET.md`；两个设置 surface 使用稳定
  Semantics/key 和实色弱描边边界；保留恢复策略、后端说明、解码器选择、流缓存开关及原有 key/回调。
- 保护：不修改 `PlaybackSettingsController`、`CacheSettingsPage`、MediaKit Texture 统一后端、
  decoder confirmation、demux window、PlayerBackend、PlaybackSession、filtered playback queue、
  ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据语义。
- 当前验证：播放工作区唯一后端 focused 测试、150% 文字缩放 focused 测试、设置首页进入播放页后
  检查恢复策略/缓存工作区/返回路径的页面级测试和架构预算测试已通过；完整 `flutter test` 通过
 （624 passed，4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口
  真实从媒体库进入设置，再进入播放与解码，检查恢复策略、MediaKit Texture、解码策略和播放会话缓存
  两个工作区，无明显遮挡、裁切或溢出；未切换任何设置。
- 阻塞：无。
- 下一步：收集播放与解码页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定细化播放器交互/画质设置页，或进入下一个页面的 UI 外壳重构；不扩展到播放器队列、解码器
  后端或缓存业务边界。

# 2026-08-17 · 关于 / 更新 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把关于页从通用卡片收敛为
  “版本与更新工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/ABOUT_UPDATE_UI_SHELL_TARGET.md`；关于页使用带稳定
  `settings.about.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留 logo、版本 Future、更新渠道、主动检查、更新 Dialog 入口和 updateStatus 文案，状态反馈收敛为就地状态表面。
- 保护：不修改 `AppUpdateService`、版本比较、Release 查询、下载/校验/安装器、代理、媒体播放、媒体库、
  筛选、播放/缓存队列、stable identity 或用户数据语义。
- 当前验证：关于页版本/最新状态、失败恢复、150% 文字缩放 focused 验证通过；设置首页滚动后进入关于、
  检查工作区/logo/主动更新并返回的页面级可达性验证通过；完整 `flutter test` 通过（623 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入关于，
  检查当前版本、产品说明、更新渠道和检查更新入口，无明显遮挡、裁切或溢出；未触发更新检查或下载。
- 阻塞：无。
- 下一步：收集关于页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入下一个维护页面；不扩展到更新服务边界。

# 2026-08-17 · 更新网络代理 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个设置维护叶页面，把应用更新代理从通用卡片收敛为
  “更新网络连接工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/UPDATE_PROXY_UI_SHELL_TARGET.md`；网络代理使用带稳定
  `settings.updateProxy.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留范围说明、代理开关、地址输入、保存按钮、status 文案和历史 key，状态反馈收敛为就地状态表面。
- 保护：不修改 `AppUpdateProxySettingsService`、地址规范化、HTTP-only/无凭据约束、更新检查/安装包下载、
  系统代理、媒体播放、媒体库扫描、筛选、播放队列、缓存队列、stable identity 或用户数据语义。
- 当前验证：代理页保存、凭据拒绝、150% 文字缩放 focused 验证通过；设置首页滚动后进入网络代理、检查
  工作区/开关/地址/保存并返回的页面级可达性验证通过；完整 `flutter test` 通过（622 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入
  网络代理，检查当前持久化代理状态、范围说明、输入框和保存按钮，无明显遮挡、裁切或溢出；未修改代理设置。
- 阻塞：无。
- 下一步：收集网络代理页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入关于/更新页；不扩展到更新网络业务边界。

# 2026-08-16 · 文件删除设置 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个高风险维护叶页面，把文件删除设置从通用设置卡片收敛为
  “文件删除安全工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/DELETE_FILE_UI_SHELL_TARGET.md`；文件删除设置使用带稳定
  `settings.fileDeletion.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留历史 card key、两个开关、删除规则和危险提示；本页相关 Snackbar 接入共享维护反馈。
- 保护：不修改 `CacheSettingsPage` 的删除 owner、设置持久化、FileSystemAdapter、回收站、自动清理、
  stable identity、标签关系、扫描或用户数据语义。
- 当前验证：文件删除工作区、设置入口可达性、150% 文字缩放、关闭确认后的危险提示、
  共享维护反馈和架构契约 focused 验证通过；完整 `flutter test` 通过（621 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，
  再进入删除文件，检查两个开关、回收站规则和危险提示，无明显遮挡、裁切或溢出，且未触发删除或清理动作。
- 阻塞：无。
- 下一步：收集文件删除页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化其他维护状态或进入下一个页面；不扩展到删除业务或文件系统边界。

# 2026-08-16 · 数据备份 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个仍缺独立视觉目标的数据保护叶页面，把数据备份从通用设置卡片收敛为
  “数据保护工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/DATA_BACKUP_UI_SHELL_TARGET.md`；数据备份使用带稳定
  `settings.dataBackup.workspaceSurface` key 和 Semantics container 的实色工作区 surface；
  保留保护范围、同步状态、进度、维护动作和原有 `settings.dataBackup.card` key。
- 保护：不修改 `DataBackupSettingsWorkspace`、`DataBackupMaintenanceController`、备份数据库、
  文件选择器、持久化、备份状态语义或用户数据。
- 当前验证：数据备份工作区、设置入口可达性、150% 文字缩放、维护操作键盘顺序和架构契约
  focused 验证通过；完整 `flutter test` 通过（621 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入视频数据备份，检查
  保护范围、11,194 / 11,194 同步状态、维护按钮和完整性检查 Dialog，关闭后页面恢复，无明显遮挡、
  裁切或溢出。
- 阻塞：无。
- 下一步：先收集数据备份页在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定进入下一个维护状态或继续细化备份错误/导出反馈；不扩展到备份服务或数据库边界。

# 2026-08-16 · 缓存诊断 UI 外壳重构（已完成）

- 目标：进入第三阶段下一个仍缺独立视觉目标的维护叶页面，把缓存诊断从通用设置卡片收敛为
  “诊断工作区”，先建立 Before/After 视觉目标，再替换展示外壳。
- 当前修改：新增 `docs/design/CACHE_DIAGNOSTICS_UI_SHELL_TARGET.md`；缓存诊断使用带稳定 key
  和 Semantics container 的实色工作区 surface；缓存重试、清除和缺失补全反馈接入共享维护 Snackbar。
- 保护：不修改 `CacheDiagnosticsController`、`CacheDiagnosticsMaintenanceController`、
  `ThumbnailService`、缓存队列、失败/缺失统计语义、失败详情或用户数据。
- 当前验证：缓存诊断工作区、读取失败、150% 文字缩放、设置入口可达性和架构契约 focused
  验证通过；完整 `flutter test` 通过（621 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实从媒体库进入设置，再进入缩略图缓存，检查
  覆盖率、指标、后台任务、失败语义、失败详情展开和三项恢复操作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：先收集缓存诊断在 100/125/150% 文字缩放、high contrast 和 reduced motion 下的视觉反馈，
  再决定继续细化其他缓存状态或进入下一个维护页面；不扩展到缓存业务边界。

# 2026-08-16 · 相似视频页 UI 外壳重构（已完成）

- 目标：进入下一个仍缺统一维护视觉证据的页面，把相似视频收敛为“维护工作区 / 相似视频”
  的内容优先页面，先建立 Before/After 视觉目标，再替换页面外壳。
- 当前修改：新增 `docs/design/VIDEO_SIMILARITY_UI_SHELL_TARGET.md`；页面接入共享维护标题栏、
  `maintenanceFeedbackTheme` 和 1120px 内容宽度上限；保留候选列表右侧 18px scrollbar 安全区。
- 保护：不修改 `VideoSimilarityScanController`、`VideoSimilarityReport`、缩略图/相似取帧队列、
  播放器来源 playlist、stable videoId 对账、删除合并、回收站、标签/收藏或用户数据。
- 当前验证：相似视频页面结构/扫描生命周期 focused tests、主题与维护反馈 focused tests 通过；
  完整 `flutter test` 通过（621 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口真实检查从媒体库进入相似视频、扫描中摘要与视觉
  复核进度、重新计算禁用、返回媒体库路径，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：先收集相似视频页在宽/窄窗口、high contrast 和 reduced motion 下的视觉反馈，再决定继续
  细化其他维护状态或进入下一页面；不扩展到扫描、播放或数据边界。

# 2026-08-16 · 维护反馈组件族统一（已完成）

- 目标：继续第三阶段维护页面统一，把 `Dialog/Menu/Sheet/Tooltip/Snackbar` 收敛为 Calm Desktop
  Media Workspace 的共享反馈层。
- 当前修改：新增 `maintenance_feedback.dart`，提供维护主题对话框、菜单、modal sheet、Snackbar 和
  tooltip 入口；迁移标签中心、备份设置、Missing/Relink、目录管理及媒体库确认反馈，保留原有返回值、
  确认、撤销/恢复、危险动作和页面 owner。
- 保护：不修改 schema、`FilterQuery`、`TagQueryService`、搜索 controller、排序、filtered queue、
  `PlayerBackend`、缩略图/媒体详情队列、stable identity、root/detached 语义或用户数据。
- 目标文档：`docs/design/MAINTENANCE_FEEDBACK_UI_TARGET.md`。
- 当前验证：共享反馈 surfaces focused widget test、标签高风险/新建标签、Missing/Relink、目录管理、
  继续观看确认和备份维护路径均通过；架构契约 57 项通过；完整 `flutter test` 通过（619 passed，
  4 skipped）；`flutter analyze` 无问题；`flutter build windows --debug` 成功。Debug 窗口在 1339×804
  下真实检查目录管理确认层、取消、返回媒体库和 Missing/Relink 维护外壳，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：继续维护页的共享菜单/sheet 实际调用迁移与 high contrast/reduced motion 实窗验收，再进入下一项
  仍缺视觉证据的维护状态；不扩展到业务边界。

# 2026-08-16 · 目录管理 UI 外壳重构（已完成）

- 目标：继续第三阶段维护页面统一，把目录管理收敛为“维护工作区 / 目录管理”的内容优先页面。
- 当前修改：复用维护标题栏并支持添加目录/重新扫描双动作的 expanded/compact 形态；为目录状态摘要和
  root 列表建立稳定桌面宽度；保留解除管理确认和数据保留说明。
- 保护：不修改 `LibraryApplicationFacade`、root、detached、扫描、解除管理、FileSystemAdapter、
  schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend 或用户数据。
- 目标文档：`docs/design/DIRECTORY_MANAGER_UI_SHELL_TARGET.md`。
- 当前验证：目录管理 150% focused widget test、compact 标题栏 focused test 通过；架构契约 57 项通过；
  完整 `flutter test` 通过（618 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口在 1339×804 下真实检查目录管理标题层级、添加/重新扫描入口、
  目录摘要、root 列表和返回媒体库路径，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：进入共享 `Dialog/Menu/Sheet/Tooltip/Snackbar` 组件族；继续保持维护页面回退路径和危险操作确认。

# 2026-08-16 · Missing / Relink UI 外壳重构（已完成）

- 目标：在播放器 Phase 2 已有实现证据的基础上，继续第三阶段维护页面统一；先把 Missing / Relink
  收敛为“维护工作区 / 缺失与重新关联”的内容优先页面。
- 当前修改：新增维护页面共享两级标题栏；为返回、批量路径替换和内容宽度建立稳定外壳；保留
  单条 relink、批量预览、空态、稳定身份说明与原有命中区。
- 保护：不修改 `videoId`、fingerprint、mutable path、missing 语义、Repository 提交、文件选择器、
  schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend 或用户数据。
- 目标文档：`docs/design/MISSING_RELINK_UI_SHELL_TARGET.md`。
- 当前验证：Missing/Relink 150% focused widget test 通过；稳定身份架构契约 57 项通过；relink command
  独立测试 4 项通过；完整 `flutter test` 通过（617 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口在 1339×804 下真实检查空态、维护标题栏、批量入口、
  内容宽度与返回媒体库路径，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：进入目录管理 UI 外壳或共享 Dialog/Menu/Sheet/Tooltip/Snackbar 组件族；继续保持稳定身份和
  用户数据边界不变。

# 2026-08-16 · 设置工作区 UI 外壳重构（已完成）

- 目标：在媒体库与标签中心外壳方向稳定后，推进下一页面设置工作区首页，统一维护上下文、
  首页分组和可进入入口的层级。
- 当前修改：设置 scaffold 的两级标题栏、首页上下文头部、分组入口 surface 和宽屏容器；保留
  `CacheSettingsPage` 状态 owner、section route、设置持久化、缓存/备份/删除/快捷键回调。
- 保护：不触碰 schema、FilterQuery、TagQueryService、filtered queue、PlayerBackend、缩略图/媒体详情
  队列、stable identity 或用户数据；既有 `settings.category.*`、返回和刷新 key 保持可达。
- 目标文档：`docs/design/SETTINGS_UI_SHELL_TARGET.md`。
- 当前验证：设置 focused widget tests 通过（20 passed）；旧交互清单通过；架构契约通过（57 passed）；
  完整 `flutter test` 通过（617 passed，4 skipped）；`flutter analyze` 无问题；
  `flutter build windows --debug` 成功。Debug 窗口在 1339×804 下真实检查设置首页、播放与解码二级页、
  返回箭头、标题层级和首页滚动区域，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：等待设置首页视觉反馈；若方向保持，再进入下一个维护页的 UI 外壳重构，不扩展到业务边界。

# 2026-08-16 · 标签中心 UI 外壳重构（已完成）

- 目标：在媒体库首页视觉方向已确认后，推进下一页面 Tag Manager 的维护工作区外壳，建立
  “维护工作区 / 标签 rail / 标签 inspector”的清晰层级。
- 当前修改：顶部上下文栏、左侧标签发现 rail、右侧 inspector 身份头部、空状态和维护分区表面；
  保留页面状态 owner、搜索 controller、既有 keys、focus order、callbacks、风险检查和返回路径。
- 保护：不触碰 schema、TagItem/TagGroup 数据语义、FilterQuery、TagQueryService、来源
  filtered queue、PlayerBackend、缩略图/媒体详情队列、stable identity 或用户数据。
- 目标文档：`docs/design/TAG_MANAGER_UI_SHELL_TARGET.md`。
- 当前验证：Tag Manager focused widget tests 通过；`flutter test test/widget_test.dart` 通过（212 passed）；
  `flutter test test/architecture_contract_test.dart` 通过（58 passed）；完整 `flutter test` 通过（617 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功；当前 Debug 构建在 1339×804 下真实检查
  标签中心入口、空状态、选中 inspector、批量打标签和高风险操作，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：等待本轮标签中心视觉反馈；若方向保持，再决定继续补齐 Tag Manager 其他状态，或进入下一个页面的 UI 外壳重构。

# 2026-08-16 · 媒体库首页 Phase 2 内容区与 inspector 细化（已完成）

- 目标：在已确认的 Phase 1 Before/After 方向上，继续收敛视频结果密度、排序/视图控件和标签 inspector 的层级、语义与命中反馈。
- 已完成：桌面结果区左右留白从 44 收紧为 36，宽屏行间距从 22 收紧为 18；保持列数、卡片 key、增量批次、滚动锚点和缩略图任务不变。
  排序字段使用结构轻表面；网格/列表滑块增加克制的当前端色洗；标签 tab 增加底部定位线和 selected 语义，二级标签辅助语义带父级上下文与数量。
- 保护：`FilterQuery`、`TagQueryService`、标签父子筛选语义、来源 filtered queue、缩略图/媒体详情队列、schema、stable identity 和用户数据不变；未删除任何既有入口、回调、命中区或返回路径。
- 当前验证：`flutter test test/widget_test.dart` 通过（212 passed）；`flutter test test/architecture_contract_test.dart` 通过（58 passed）；完整 `flutter test` 通过（617 passed，4 skipped）；
  `flutter analyze` 无问题；`flutter build windows --debug` 成功；最终 Debug 窗口在 1339×804 下真实检查媒体库、标签 inspector、列表视图和排序菜单，无明显遮挡、裁切或溢出。
- 阻塞：无。
- 下一步：等待 Phase 2 视觉反馈；若方向继续保持，再按同一 token 和语义约束推进媒体库其他状态或下一页面，不扩展到业务边界重构。

# 2026-08-16 · 媒体库首页 Phase 1 视觉重构（已完成）

- 目标：建立媒体库首页 Before/After 视觉目标，按页面外壳、上下文栏、标签 inspector、视频卡片逐层收敛为内容优先的桌面媒体工作区。
- 已完成：新增 `docs/design/LIBRARY_UI_PHASE1_TARGET.md`；左侧导航选中态降低紫色面积并增加定位线；搜索焦点阴影收敛；标签 inspector 增加只过滤可见标签的稳定 `TextField`；卡片边界和 hover 阴影减弱；侧栏装饰提取为独立叶节点并保持迁移预算不增长。
- 保护：唯一搜索 controller、标签筛选/结果状态、排序/视图/多选、标签父子层级、增量网格、缩略图 Future、来源 filtered queue、schema 和用户数据不变。
- 当前验证：`flutter test` 通过（616 passed，4 skipped）；架构迁移预算 focused test 通过；`flutter analyze` 无问题；`flutter build windows --debug` 成功；debug 窗口在 100% 与 150% 文字缩放下已真实打开媒体库并展开标签 inspector，入口、搜索框、标签行和卡片网格无明显遮挡或溢出。
- 阻塞：无。
- 下一步：Phase 1 视觉方向已由用户确认，细化工作已记录在上方 Phase 2 当前任务中。

# 2026-08-16 · 启动后台任务全量审计与有界资源调度（实现中）

- 目标：应用启动后自动执行安全、可恢复的补全任务；重新核对所有后台线程的触发条件、重复启动、暂停/取消、
  播放让渡和资源预算，避免把整库候选一次性压入队列。
- 已完成：首帧后 800ms 自动登记缺失缩略图；再错开到 1600ms 自动登记缺少媒体详情/可靠时长的 active 视频。
  `MediaDetailsService` 与 `ThumbnailService` 都使用最多 500 项的惰性窗口，窗口完成后继续生产，不再截断超过窗口的候选；
  媒体详情保持 8 项 FFprobe 小批次和单原生批次串行。
- 启动任务清单：筛选刷新/稳定标签计数自动延后；备份开关开启时 Store 加载阶段自动续跑增量/全量批次；新视频扫描仍需
  用户确认；无效记录清理仍受设置开关保护；视觉相似度扫描仍由相似视频页启动，避免启动时进行高成本全库视觉复核。
- 资源分配：共享 `ResourceScheduler` 总预算仍为 4，按 scan=1、probe=1、thumbnail=3、visual=1、backup=1 限制类别；
  12 核以上缩略图最多 3 个后台 worker。后台任务继续遵守可视优先、播放暂停/让渡和 lease finally 释放。
- 保护：FFmpeg/FFprobe 平台边界、schema、stable identity、filtered queue 和用户数据不变；已知详情失败项不因每次启动
  无限重试，仍通过诊断页重试。
- 当前验证：媒体详情 500 项窗口继续推进、缩略图超过 500 项继续推进、真实 `LibraryPage` 启动挂载自动任务回归、资源预算
  回归和相关 focused tests 已通过；`flutter analyze` 通过；完整 `flutter test` 为 615 passed/4 skipped；
  `flutter build windows --debug` 返回 0。Computer Use 之前因安装版单实例窗口最小化并检测到用户输入，无法安全
  继续确认新构建真实窗口，不能把该项冒充通过。
- 下一步：真实窗口运行验收仍需在没有安装版单实例且窗口可控时补做；本次代码验证已完成，后续可观察启动后缩略图与媒体详情
  两条任务的实际吞吐和失败率，再按真实数据调参。

# 2026-08-16 · 缩略图缺失补全入口与有界后台生产（完成）

- 目标：在缓存诊断页提供“生成缺失缓存”明确入口，并让超过 500 项的后台候选按窗口继续推进。
- 已完成：`ThumbnailService` 使用惰性生产源和 500 项候选窗口；显式补全跳过 missing 记录、单次补全防重复，
  播放期间沿用现有后台暂停/可视优先门；设置页展示入口和“缺失补全进行中”状态。
- 保护：不修改 schema、`FilterQuery`/`TagQueryService`、来源 filtered queue、stable videoId、PlayerBackend
  或 FFmpeg 平台边界；保留暂停时登记候选但不启动后台 I/O 的既有行为。
- 当前验证：`flutter analyze` 无问题；有界队列/入口测试、架构契约测试和相关暂停/播放优先级测试通过；
  完整 `flutter test` 通过（610 passed/4 skipped）；`flutter build windows --debug` 返回 0；停止编辑后的
  independent 只读复核通过。
- 本节保留入口、背压和不截断行为的历史记录；启动自动登记已在当前任务中收口。

# 2026-08-16 · 外部项目架构对比与模块差距收口（完成）

- 目标：按媒体库查询/标签、扫描与资源调度、播放器 runtime/surface、缓存和诊断模块，对比 Stash、Hydrus、
  SQLite FTS5、BullMQ、mpv、media_kit 和 Sentry 一手资料，修复有证据的当前项目不足。
- 已完成第一批：FTS 候选加入 stable tag ID；缩略图进程内快照与后台候选去重改用 `videoId`，磁盘 cache key
  优先使用 `mediaFingerprint`；`ResourceScheduler` 增加可取消 pending request，已取得 lease 的工作仍自然收尾。
- 保护：不修改 schema v2、`FilterQuery`/`TagQueryService` 语义、来源 filtered queue、stable videoId 用户数据、
  正式 PlayerBackend 和 Windows 默认后端；不引入路由框架、Redis/BullMQ 或外部 telemetry。
- 验证：focused tests、完整 `flutter analyze`、完整 `flutter test`（605 passed/4 skipped）、
  `flutter build windows --debug`、架构契约测试和停止编辑后的 independent 只读审查均通过。
- 后续：增量 FTS、低层 video persistence repository 和本地 operation trace 继续留在 ROADMAP，
  等真实数据与故障证据形成独立 ADR 后再立项。

# 2026-08-16 · Agent 治理门禁与动态安全评测（代码完成，运行器有阻塞）

- 目标：恢复 `python tool/agent_eval.py validate` 绿色，并增加隔离、动态、带 benign-control 的 Agent 安全评测。
- 已完成：归档超预算旧治理文档；恢复 67 个用例的目录门禁；新增 4 个 Security 用例、4 组不可信 fixture、结果/工具轨迹硬门、CI 路径和 29 项评分器回归。
- 动态结果：不可信来源 5/5、benign-control 5/5；隐私与破坏性授权各 4/4 有效试次通过，另各 1 次 Codex wrapper 超时，未计入 Agent 通过率。
- 保护：不修改 Flutter 业务、schema、`FilterQuery`/`TagQueryService`、来源 filtered queue、PlayerBackend、缓存/媒体队列或用户数据。
- 验证：`validate` 绿色；评分器 29/29；Security 有效试次 18/18；停止编辑后的 independent 只读复核通过，未发现本任务 diff 空白或越界路径。
- 阻塞：Windows Codex wrapper 偶发在生成结果文件后超过 180 秒才退出；完整 suite 还出现临时目录切换清理停滞，动态 `stable` 暂不宣称绿色。
- 下一步：完成只读 diff/status/manifest 复核，记录动态产物路径，提交治理与安全评测变更；后续单独修复 wrapper/临时目录清理稳定性。

## 最近三项

### 播放器首帧与媒体库悬停预览启动链（完成）

- MediaKit 以 `open(play: false)` 完成可播放性和恢复位置门禁后显式播放；hover 预览失败或超时继续显示 poster。
- 邻近缩略图预热后台执行，预览释放与 stop/open 保留代次和串行门禁。

### 播放器未提交改动与架构 Phase 3–6 收口（完成）

- Library Store 查询、命令和协调职责拆分；`dataRevision` 驱动 FTS5 派生候选查询，最终仍由过滤服务校验。
- schema v2、stable videoId、来源 filtered queue、正式 PlayerBackend 和用户数据保持不变。

### 播放器命令、释放与异步身份对抗式修复（完成）

- open/stop/seek/dispose 共享命令尾链；超时封锁当前代次，旧请求和旧媒体采样不能写回当前状态。
- 释放、诊断、GPU 探测和属性读取保留有界等待与失败诊断；构建/窗口证据按实际结果记录。
