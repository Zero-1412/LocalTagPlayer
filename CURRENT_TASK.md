# CURRENT_TASK.md

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-08-01 · 对齐 PotPlayer 的长按快进节奏（本地验证完成）

- 目标：用同一视频对比 PotPlayer 与本项目的方向键长按快进，修复重复按键期间
  反复触发精确 seek 导致的迟滞感。
- 实现：KeyRepeat 只提交关键帧预览并累计逻辑目标，KeyUp 对最终目标精确收敛一次；
  快进/快退反馈同步显示累计目标时间。
- 保护边界：单次 5 秒精确步进、进度条最终提交、播放/暂停意图、filtered queue、
  current index、返回路径、schema、过滤语义、缓存队列和用户数据保持不变。
- 验证模式：Level 3 `independent`；停止编辑后执行独立只读复核。
- 本地证据：focused tests 通过，analyze 零问题，Windows Debug build 成功；
  构建产物打开同一视频后目标反馈为 `前进 5 秒 · 00:29`，来源队列保持
  `2 / 11248`，返回媒体库正常。电脑控制接口不支持原始长按，KeyRepeat/KeyUp
  交互边界由确定性测试覆盖。

## 最近完成

1. 2026-08-01：对齐 PotPlayer 的方向键长按快进节奏，按住期间只做关键帧预览，
   松开时精确收敛最终目标一次，并增加累计目标时间反馈。
2. 2026-07-31：完成 `file_picker` 11.0.2 稳定升级、静态 API 迁移、
   契约测试和 Windows 原生目录选择真实点击；不使用 beta 或依赖覆盖。
3. 2026-07-31：建立 37 项 QA 自动化生命周期清单；合并/退役 3 个包装器，
   归档 3 个历史 runner，并新增脚本、证据路径和绝对盘符门禁。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.125`。
- 数据：schema、标签来源、查询语义、filtered queue 与用户维护数据保持稳定。
- 依赖：`file_picker 11.0.2`、`package_info_plus 9.0.1`；后者 10.x
  受稳定版 `win32` 约束冲突阻塞。
- 最近业务验证：486 项测试通过、3 项 benchmark 按设计跳过；
  `flutter analyze`、Windows Debug build 和交互式 seek 真实后端门禁通过。

## 已确认阻塞

- GitHub Support purge 工单尚未确认服务端缓存清理完成；完成后需验证旧 Commit API 返回 404。
- 可信 Windows/macOS 正式签名仍需仓库所有者配置外部证书和 GitHub Actions secrets；
  任何证书、密码或私钥都不得写入仓库。

## 下一步

1. `file_picker 12` 发布稳定版或上游 `win32` 约束收敛后，单独复核
   `package_info_plus` 9 → 10；不得使用 beta 或 `dependency_overrides` 绕过。
2. 如继续精修播放器，使用实体键盘补一次完整的长按验收；应用切换后播放器需先点击
   才重新接收快捷键的问题应作为独立任务调查，不与 seek 语义混改。
3. 仓库所有者配置签名证书或 GitHub Support purge 完成后，按已记录门禁继续外部验证。
