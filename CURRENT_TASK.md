# CURRENT_TASK.md

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-08-04 · seek 恢复时间线诊断（完成）

- 对真实 4K 媒体库样本的录屏曾复现连续预览后约 1.37 秒画面静止；新增 `PLAYER_SEEK_TRACE` 把 `KeyUp`、精确 seek 开始/返回、新视频帧证据、音频恢复请求/完成关联到同一 trace id。最终帧基线仅在精确命令返回后读取，Windows 优先以原生 Texture 已渲染计数而非 mpv 估算帧号判定，trace 记录证据来源。
- 每条事件记录 `mono_us` 作为唯一延迟依据，`wall_utc_ms` 仅用于和录屏启动侧车日志建立跨进程锚点；最终基线在 exact seek 返回后采样，Windows 优先观察 `native-rendered-frames`，并用 `frame_evidence` 区分原生 Texture 与估算回退；不改 `PlayerBackend`、音频策略、filtered queue 或用户数据。
- 验证：seek coordinator focused test 覆盖“exact 完成后才取基线”、六个节点顺序、同一 trace id 和 Texture 证据来源；`flutter analyze`、播放器/架构契约与 Windows Debug 构建通过。真实窗口可启动且 stdout 已接通，但捕获持续混入其他前台应用，已停止输入；待无覆盖的播放器窗口可用后，以 30fps 录屏和 trace 日志复核此前间歇性静止段。

### 2026-08-03 · 修复 seek 临时静音与新帧恢复（完成）

- 目标：长按快进/快退只临时静音，关键帧预览保持视频时钟连续；KeyUp 只精确 seek 一次，且必须等新视频帧交付证据后解除静音。
- 作用域：`PlayerKeyboardSeekController`、进度条提交和 `MediaKit Texture` 会话控制；不修改 `PlayerBackend` 接口、数据库、筛选语义、来源 filtered queue、缓存队列或用户媒体。
- 方案：以 `volume=0` 代替 `pause/play`；保持 latest-only 合并，按实际关键帧 seek 耗时自适应为 15/10/8fps 预览，并采用 750/1200/1800ms 新帧确认阈值。12-case 脚本会产出长 GOP p95 对应的建议档位，不伪造本机无 manifest 的结果。
- 验证：seek 会话顺序（含无新帧不解静音）、长 GOP 节流档位、页面与架构契约、完整 widget 测试、`flutter analyze` 与 Windows Debug build 均通过；真实 Debug 应用成功启动并显示媒体库。`.local/qa/player_seek-latency-matrix.json` 不存在，故 12-case Texture 门禁仍需在持有私有 manifest 的机器重跑。

### 2026-08-03 · 修复播放器单次 seek 与真实延迟门禁（完成）

- 目标：消除进度条释放和方向键短按各自可能产生的预览加精确 seek 双跳转，避免长 GOP
  媒体在一次交互中重复解码；保持长按关键帧预览和 KeyUp 精确收敛。
- 作用域：`PlayerProgressSlider`、`PlayerKeyboardSeekController` 与正式 MediaKit Texture
  seek 门禁；不修改 `PlayerBackend` 接口、数据库、筛选语义、来源 filtered queue、缓存队列或用户媒体。
- 验证：新增短按无预览且只精确收敛一次的单元契约；新增 1080p/4K、H.264/HEVC/AV1、
  短/长 GOP 的 ffprobe 规格核验与真实后端 p95 矩阵门禁。本机完整矩阵与 Windows 构建结果见本任务记录。

## 最近完成

1. 2026-08-03：seek 改为临时静音而非暂停视频时钟；方向键 KeyUp 等新视频帧后恢复音量，
   并保持 latest-only 合并和 GOP 成本自适应节流。
2. 2026-08-03：进度条松手改为单次精确 seek；方向键短按不再先做关键帧预览，
   长按仍在 `KeyRepeat` 后预览并在 KeyUp 精确收敛一次；建立真实 codec/GOP 延迟矩阵门禁。
3. 2026-08-01：完成 `0.2.5+7` 双平台打包、全量门禁与 `v0.2.5` 公开 GitHub Release；
   缺少签名 secrets 的风险已在发布说明和 macOS 文件名中明确标识。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.127`。
- 数据：schema、标签来源、查询语义、filtered queue 与用户维护数据保持稳定。
- 版本：`0.2.5+7`；依赖：`file_picker 11.0.2`、`package_info_plus 9.0.1`；后者 10.x
  受稳定版 `win32` 约束冲突阻塞。
- 最近业务验证：短按/长按 seek 会话、进度条 widget 与页面契约已通过；完整的 12-case
  编码/GOP 矩阵仍需在持有私有 manifest 的机器重跑，结果将决定最终门禁校准档位。

## 已确认阻塞

- GitHub Support purge 工单尚未确认服务端缓存清理完成；完成后需验证旧 Commit API 返回 404。
- 可信 Windows/macOS 正式签名仍需仓库所有者配置外部证书和 GitHub Actions secrets；
  任何证书、密码或私钥都不得写入仓库。

## 下一步

1. `file_picker 12` 发布稳定版或上游 `win32` 约束收敛后，单独复核
   `package_info_plus` 9 → 10；不得使用 beta 或 `dependency_overrides` 绕过。
2. 如继续精修播放器，使用实体键盘补一次完整的长按验收；应用切换后播放器需先点击
   才重新接收快捷键的问题应作为独立任务调查，不与 seek 语义混改。对真实用户视频建立新预算时，
   使用 `docs/qa/player_seek_latency_matrix.md` 的 12-case manifest，不将路径提交仓库。
3. 代理功能完成后，使用本机代理完成一次 GitHub 检查和安装包下载真实验收；
   仓库签名凭据与 GitHub Support purge 仍按既有独立任务跟进。
