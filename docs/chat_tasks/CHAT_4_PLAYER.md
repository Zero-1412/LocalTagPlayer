# Chat 4：播放器与筛选结果队列

## 2026-08-04 · 媒体轨道、章节与同步校正

- 审计仅纳入适合本地发现播放器的能力：内嵌音轨选择、字幕选择/关闭、字幕延迟、音频延迟与章节定位；不纳入 mpv 内部播放列表、watch-later、网络录制、脚本/OSD、A-B 或逐帧等专业播放器扩展。
- `PlayerMediaControlsBoundary` 为可选平台扩展。`PlayerService` 只转发强类型意图；MediaKit 在当前 `NativePlayer` 上调用类型化轨道 API，并按需读取 libmpv 章节节点，绝不创建第二个播放器、解码链或队列。
- 新增快捷键不得替换现有绑定：`#`、`v`、`z/Z`、`Ctrl++/Ctrl+-` 与 `g-a/g-s/g-c` 仅在未被配置动作占用时处理；既有 `J/L`、`PageUp/PageDown` 保持原有 seek/来源队列语义。

## 2026-08-04 — 键盘 seek 恢复连续播放

- 同一条本地样本的无内容泄露图形帧差分复现了旧路径在短按后约 0.4 秒的静止窗口；trace 同时证明 MediaKit Texture 使用 `estimated-frame-number` 回退，不能把它宣称为最终屏幕呈现。
- 键盘短按改为立即关键帧预览且不临时静音；KeyRepeat 进入的长按继续 latest-only、GOP 自适应节流与临时静音，但 KeyUp 只收敛最后一个关键帧预览，不再追加 absolute 精确 seek。进度条松手仍走独立精确定位。
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
- 长按方向键期间累计逻辑目标并使用 keyframe 预览，KeyUp 只精确收敛最后目标一次；
- 连续预览保持 latest-only 合并、受限重复步长和约 64ms 默认刷新预算；当前会话检测到
  关键帧 seek 解码压力时自适应降至 96/125ms，反馈合并到同一节奏，禁止每个 KeyRepeat 都重建完整播放器页面；
- 单次方向键先只建立 5 秒目标，KeyUp 只精确前进/后退一次；收到 `KeyRepeat` 后才允许
  关键帧预览，进度条释放后同样只提交最终精确目标，禁止预览加精确 seek 的双跳转；
- seek 延迟以真实 MediaKit Texture 的 1080p/4K、H.264/HEVC/AV1、短/长 GOP 矩阵门禁为准，
  不根据请求参数推测解码路径，也不以单次主观观感取代 p95 结果；
- MediaKit Texture 是正式默认，native mpv/child HWND 只显式 QA；
- 用户播放/暂停意图、current index 和进度不因诊断/反馈重建；
- 控制、隐藏进度、设置和队列入口有页面级挂载与真实可达证据。

## 非目标

- 不把长按 seek 扩展为倍速播放、逐帧或专业播放器功能；关键帧预览期间只临时静音，绝不暂停视频时钟；KeyUp 的精确位置确认且新视频帧已交付后才恢复原音量。

不把 NVIDIA/NVOFA 实验宣传或自动晋级为生产能力，不优先专业播放器功能。

历史：`docs/history/chat/CHAT_4_PLAYER_THROUGH_2026-07-30.md`。

## 2026-08-04 · seek 恢复 trace

- `PlayerSeekAudioGate` 在一个临时静音会话内分配 trace id；`PlayerKeyboardSeekController` 在同一 id 下记录 `key_up`、`exact_seek_start` 和 `exact_seek_complete`。
- 精确 seek 返回后才采样最终帧基线；Windows 正式 Texture 路径优先等原生桥完成共享纹理复制的 `native-rendered-frames` 递增，非原生路径才回退 mpv `estimated-frame-number`，并在 trace 标出 `frame_evidence`。新视频帧或超时、以及音频恢复请求/完成继续写入同一 trace。`mono_us` 只用于会话内延迟，`wall_utc_ms` 只作为本地录屏起始时间的对齐锚点；两者不得混用为性能结论。
- 诊断不改变 preview latest-only 合并、音频静音策略、`PlayerBackend` 合约或来源 filtered queue。
