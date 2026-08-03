# CURRENT_TASK.md

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-08-03 · 修复播放器单次 seek 与真实延迟门禁（完成）

- 目标：消除进度条释放和方向键短按各自可能产生的预览加精确 seek 双跳转，避免长 GOP
  媒体在一次交互中重复解码；保持长按关键帧预览和 KeyUp 精确收敛。
- 作用域：`PlayerProgressSlider`、`PlayerKeyboardSeekController` 与正式 MediaKit Texture
  seek 门禁；不修改 `PlayerBackend` 接口、数据库、筛选语义、来源 filtered queue、缓存队列或用户媒体。
- 验证：新增短按无预览且只精确收敛一次的单元契约；新增 1080p/4K、H.264/HEVC/AV1、
  短/长 GOP 的 ffprobe 规格核验与真实后端 p95 矩阵门禁。本机完整矩阵与 Windows 构建结果见本任务记录。

## 最近完成

1. 2026-08-03：进度条松手改为单次精确 seek；方向键短按不再先做关键帧预览，
   长按仍在 `KeyRepeat` 后预览并在 KeyUp 精确收敛一次；建立真实 codec/GOP 延迟矩阵门禁。
2. 2026-08-01：完成 `0.2.5+7` 双平台打包、全量门禁与 `v0.2.5` 公开 GitHub Release；
   缺少签名 secrets 的风险已在发布说明和 macOS 文件名中明确标识。
3. 2026-08-01：对齐 PotPlayer 的方向键长按快进节奏，按住期间只做关键帧预览，
   松开时精确收敛最终目标一次，并增加累计目标时间反馈。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.127`。
- 数据：schema、标签来源、查询语义、filtered queue 与用户维护数据保持稳定。
- 版本：`0.2.5+7`；依赖：`file_picker 11.0.2`、`package_info_plus 9.0.1`；后者 10.x
  受稳定版 `win32` 约束冲突阻塞。
- 最近业务验证：短按/长按 seek 契约、进度条 widget、真实 MediaKit Texture seek 门禁、
  `flutter analyze` 与 Windows Debug build 均通过；完整的 12-case 编码/GOP 矩阵摘要位于未跟踪 artifacts。

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
