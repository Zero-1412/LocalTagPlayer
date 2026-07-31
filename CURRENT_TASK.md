# CURRENT_TASK.md

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-07-31 · Agent 治理整治

- 目标：执行 `docs/audits/LOCAL_TAG_PLAYER_AGENT_ECOSYSTEM_AUDIT_2026_07_31.md`
  中有证据支持的治理任务，按 P0、P1、P2 完成自动门禁、文档分层、脚本合并和历史归档。
- 当前阶段：P2，默认规则和 current/history 文档已分层；下一步建立 QA manifest、
  合并重复 runner 并归档已完成实验资产。
- 保护边界：不修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、
  PlayerBackend、缓存队列、标签来源语义、用户数据或既有 UI 可达性。
- 验证模式：Level 3 `independent`；每个阶段停止编辑后执行独立只读复核。
- 已证伪风险：`docs/AGENT_SKILL_INSTALL.md` 与 Apple UI `agents/openai.yaml`
  均可被严格 UTF-8 正确解码；此前乱码是 PowerShell 默认解码造成的显示问题。

## 最近完成

1. 2026-07-31：`AGENTS`、Project、Claude、Harness 建立单一事实源；
   Architecture、Roadmap、Changelog 的 current contract 与历史无损分离。
2. 2026-07-31：建立治理预算、严格 UTF-8/Skill 元数据验证和 PR workflow；
   `CURRENT_TASK` 历史无损归档，63 个 Agent 用例与 21 个工具单测通过。
3. 2026-07-31：完成 180 项 Agent 治理资产对抗式审计，报告提交
   `75a4e57` 已推送到 `origin/master`。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.124`。
- 数据：schema、标签来源、查询语义、filtered queue 与用户维护数据保持稳定。
- 最近业务验证：486 项测试通过、3 项 benchmark 按设计跳过；
  `flutter analyze`、Windows Debug build 和交互式 seek 真实后端门禁通过。

## 已确认阻塞

- GitHub Support purge 工单尚未确认服务端缓存清理完成；完成后需验证旧 Commit API 返回 404。
- 可信 Windows/macOS 正式签名仍需仓库所有者配置外部证书和 GitHub Actions secrets；
  任何证书、密码或私钥都不得写入仓库。

## 下一步

1. 建立 QA manifest，合并重复 runner 并移除本机绝对路径。
2. 归档已完成 Chat/QA/实验资产，生成可检索索引。
3. 固定 GitHub Actions 依赖，完成全量独立复核。
