# CURRENT_TASK.md

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-07-31 · 依赖升级门禁兼容批次（本地验证完成）

- 目标：单独执行 `docs/qa/dependency_upgrade_gate.md`，隔离评估并迁移两个
  直接依赖的跨 major 升级，不混入治理、UI 或业务语义变更。
- 裁决：`file_picker` 8.3.7 → 11.0.2 已完成；`package_info_plus` 10.2.1
  与稳定版 `file_picker` 的 `win32` 约束无交集，保持 9.0.1，等待上游稳定版收敛。
- 实现：桌面文件选择适配器迁移到 `FilePicker` 静态 API，并增加禁止恢复
  `FilePicker.platform` 的架构契约。
- 保护边界：不修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、
  PlayerBackend、缓存队列、标签来源语义、用户数据或既有 UI 可达性。
- 验证模式：Level 3 `independent`；每个阶段停止编辑后执行独立只读复核。
- 本地证据：focused tests 62 项通过、1 项按平台跳过；analyze 零问题；
  Windows Debug build 成功；绝对路径启动构建产物后原生目录选择对话框可达，
  取消不改变 1 个资料库与 11232 个视频。

## 最近完成

1. 2026-07-31：完成 `file_picker` 11.0.2 稳定升级、静态 API 迁移、
   契约测试和 Windows 原生目录选择真实点击；不使用 beta 或依赖覆盖。
2. 2026-07-31：建立 37 项 QA 自动化生命周期清单；合并/退役 3 个包装器，
   归档 3 个历史 runner，并新增脚本、证据路径和绝对盘符门禁。
3. 2026-07-31：Chat 1—7、34 份 dated QA 证据、架构完成材料和一次性实验
   已分层归档；当前短契约、索引和门禁路径保留。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.124`。
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
2. 仓库所有者配置签名证书或 GitHub Support purge 完成后，按已记录门禁继续外部验证。
3. 新产品任务从 `NEW_CHAT_BOOTSTRAP.md` 重新路由；不得默认读取本轮历史归档。
