# CHANGELOG.md

本文件只保存当前发布候选和版本索引。完整历史位于
`docs/history/changelog/`，不要把旧条目复制回根文件。

## Unreleased

- 新增 Flutter 3.47 Windows 隔离兼容门禁：在排除用户未跟踪文件的短路径副本中，固定 SDK revision，验证全量测试、analyze、Debug/Release 构建和启动，并以正式 MediaKit Texture 运行真实 seek 矩阵。
- 新增 12 样本 seek 可重放基线：运行前复核 codec、分辨率、GOP 与文件身份，摘要不输出本机媒体路径；矩阵支持 preflight、断点续跑、冷却及有限瞬态重试。
- 本轮只增强 QA/构建证据，不改变播放器默认后端、来源 filtered playback queue、seek 运行时策略、schema 或用户数据。

## 0.2.10

- 播放器媒体控制面板继续保留音轨、字幕、音画同步和章节入口，并按当前后端能力显示逐帧、A-B loop 与外挂字幕操作。
- 播放器精确控制与进度定位继续沿用当前会话边界；操作只作用于当前媒体，不重建来源 filtered playback queue，也不写入媒体库。
- 播放器稳定性诊断补充输入链、Texture 呈现和资源释放的分层证据，失败状态保持可见，不把自动化缺证写成通过。
- 版本治理与发布说明收敛为可审查的当前索引，完整历史保留在 dated history。

详细用户发布说明见 `docs/RELEASE_NOTES_0.2.10.md`。

## 已发布版本

- 0.2.10+12：当前正式版本，详细发布说明见 `docs/RELEASE_NOTES_0.2.10.md`。
- 0.2.9+11：详细发布说明见 `docs/RELEASE_NOTES_0.2.9.md`。
- 0.2.8+10：详细发布说明见 `docs/RELEASE_NOTES_0.2.8.md`。
- 更早版本和逐项变更见 `docs/history/changelog/`。
