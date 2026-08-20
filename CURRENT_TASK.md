# CURRENT_TASK.md

# 2026-08-20 · v0.2.10 正式发布修复与验证

## 当前

- 目标：修复发布前治理与架构门禁，按现有 GitHub release workflow 发布 v0.2.10。
- 已完成：将播放器媒体控制面板从 player_state_dialogs.dart 拆为独立叶文件，保留旧 export 入口、ValueKey、callback、菜单 action 和当前会话边界。
- 已完成：版本更新为 0.2.10+12；补齐纯文本发布说明；根 CHANGELOG 与本任务历史已按预算规则归档。

## 最近三项

- 播放器输入链与 Texture/DWM 诊断保持 QA-only，不把自动化缺证写成正式性能通过。
- P0/P1 证据包保留 fail/unknown 原始分类，不因发布需要改写门禁结论。
- 播放器媒体控制、逐帧、A-B loop、外挂字幕和章节操作继续限定在当前播放会话，不改变来源 filtered playback queue。

## 阻塞

- focused architecture/player media controls tests 已通过；完整 flutter test、flutter analyze、Debug/Release build 和 Agent governance 仍需最终复跑。
- tag 正式发布还需要 Windows Authenticode 与 macOS 签名/公证 Secrets；缺少时只能按工作流明确标记为未签名/未公证，不得冒充签名包。
- 不修改 schema、FilterQuery、TagQueryService、PlayerBackend、缓存/媒体详情队列、stable identity 或用户数据。

## 下一步

- 停止编辑后独立运行 agent-eval validate、agent-eval 单元测试、完整 Flutter 测试、analyze、Debug/Release build 和发布说明门禁。
- 复核页面挂载与旧导入入口，确认无悬空 Widget、Key、callback 或返回路径。
- 仅在所有门禁真实通过后创建中文提交、推送当前发布分支、触发 v0.2.10 工作流并核对 GitHub Release 资产与 SHA-256。
