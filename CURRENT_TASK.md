# CURRENT_TASK.md

# 2026-08-20 · v0.2.10 正式发布完成

## 当前

- 目标：修复发布前治理与架构门禁并完成 v0.2.10 发布；GitHub Release 已公开，资产状态按实际结果标注为未签名/未公证。
- 已完成：将播放器媒体控制面板从 player_state_dialogs.dart 拆为独立叶文件，保留旧 export 入口、ValueKey、callback、菜单 action 和当前会话边界。
- 已完成：版本更新为 0.2.10+12；补齐纯文本发布说明；根 CHANGELOG 与本任务历史已按预算规则归档。
- 已完成：修复 Windows checkout 的 CRLF/LF 源码契约差异；本地与云端全量门禁、Windows/macOS 打包、Release 资产和 SHA-256 均已核对。

## 最近三项

- 播放器输入链与 Texture/DWM 诊断保持 QA-only，不把自动化缺证写成正式性能通过。
- P0/P1 证据包保留 fail/unknown 原始分类，不因发布需要改写门禁结论。
- 播放器媒体控制、逐帧、A-B loop、外挂字幕和章节操作继续限定在当前播放会话，不改变来源 filtered playback queue。

## 阻塞

- 代码与发布门禁无阻塞；如需签名/公证版，仍需补充 Windows Authenticode 与 macOS 签名/公证 Secrets，并重新运行标签发布。
- 不修改 schema、FilterQuery、TagQueryService、PlayerBackend、缓存/媒体详情队列、stable identity 或用户数据。

## 下一步

- 保持当前 Release 与校验文件可下载；后续如补齐签名 Secrets，再按同一 workflow 重新构建签名/公证资产。
- 根据用户反馈继续维护页面挂载、旧导入入口、Widget、Key、callback 和返回路径，不扩大本次发布范围。
