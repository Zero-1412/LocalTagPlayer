# CURRENT_TASK.md

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-08-01 · 0.2.5 公共未签名发布（完成）

- 目标：把 v0.2.4 之后已合入 `master` 的播放器和兼容性修复打包并发布到 GitHub。
- 版本：`0.2.5+7`；新增 `docs/RELEASE_NOTES_0.2.5.md` 作为应用更新弹窗和
  后续 GitHub Release 的单一正文来源。
- 发布边界：远程没有 Windows/macOS 签名 secrets；经用户明确授权后，
  发布未签名/未公证的 `v0.2.5` 公开 Release，发布说明与 macOS 文件名均保留风险标识。
- 保护边界：不修改 schema、过滤语义、filtered queue、PlayerBackend、缓存队列或用户数据。
- 验证结果：Level 3 `independent`；Actions [run 30691208487](https://github.com/Zero-1412/LocalTagPlayer/actions/runs/30691208487)
  的分支集成、全量业务门禁、Windows Release 安装器、macOS Release 启动与公开发布均通过。
- 公开产物：[Local Tag Player 0.2.5](https://github.com/Zero-1412/LocalTagPlayer/releases/tag/v0.2.5)
  含 Windows x64 安装器、macOS 未公证 DMG 与两份 SHA256 清单；标签精确指向 `c4e6ca4`。
- 哈希证据：Windows 安装器为 `9792bd608fec529bce688f74934c9f7b1e01468803e9ad44d09e782e7281d425`；
  macOS DMG 为 `210544cd13df298a1a47dd1c1eb0fa8e10f6585e64faa65745f6447d690031d3`。

## 最近完成

1. 2026-08-01：完成 `0.2.5+7` 双平台打包、全量门禁与 `v0.2.5` 公开 GitHub Release；
   缺少签名 secrets 的风险已在发布说明和 macOS 文件名中明确标识。
2. 2026-08-01：对齐 PotPlayer 的方向键长按快进节奏，按住期间只做关键帧预览，
   松开时精确收敛最终目标一次，并增加累计目标时间反馈。
3. 2026-07-31：完成 `file_picker` 11.0.2 稳定升级、静态 API 迁移、
   契约测试和 Windows 原生目录选择真实点击；不使用 beta 或依赖覆盖。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.126`。
- 数据：schema、标签来源、查询语义、filtered queue 与用户维护数据保持稳定。
- 版本：`0.2.5+7`；依赖：`file_picker 11.0.2`、`package_info_plus 9.0.1`；后者 10.x
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
3. 仓库所有者配置签名证书后，为下一版本重跑签名/公证门禁，不静默改写已公开的 `v0.2.5`；
   GitHub Support purge 完成后另行继续旧 Commit API 的外部验证。
