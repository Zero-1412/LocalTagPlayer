# CHANGELOG.md

本文件只保存未发布变更和版本索引。完整历史位于
`docs/history/changelog/`，不要把旧条目复制回根文件。

## Unreleased

### Agent 治理门禁与动态安全评测

- 压缩根级治理状态、架构契约和变更索引；旧内容保留在 dated history，恢复默认上下文预算门禁。
- 增加隔离动态安全用例、untrusted fixture、benign-control、结果泄露检查和工具动作检查。
- Agent governance workflow 覆盖架构契约与 Agent eval 文档变更，避免治理规则变更绕过门禁。

### 播放器首帧与媒体库悬停预览

- MediaKit 以 `open(play: false)` 完成引擎、媒体可播放性和恢复位置门禁后显式播放；失败/超时继续显示 poster。
- 共享 hover 预览、邻近缩略图预热和 stop/open 释放使用后台任务、串行链和代次保护。

### 架构分层与资源预算

- Library Store 查询、命令和协调职责拆分；FTS5 候选路径最终仍由 `FilterQuery`/`TagQueryService` 校验。
- FTS 候选文本补齐 stable tag ID；缩略图内存快照与后台候选去重改用 stable videoId，磁盘 cache key
  在 videoId 范围内优先复用 mediaFingerprint；ResourceScheduler 增加 pending request cancellation，
  不中断已开始的 I/O。
- schema v2、stable videoId、来源 filtered queue、正式 PlayerBackend、缩略图/媒体队列和用户数据保持不变。

### 播放器命令与异步身份

- open/stop/seek/dispose 共享媒体命令尾链；超时封锁当前代次，旧事件不能写回新媒体。
- 释放、诊断、GPU 探测和属性读取保留有界等待、失败阶段和可复核日志。

### 相似视频与删除安全

- 视觉复核使用可取消、有界、可让渡的后台队列；视觉签名为带 fingerprint 快照的可重建缓存。
- 用户视频删除统一先进入系统回收站，再删除 Repository 记录和可重建缓存；manual 标签和收藏按 stable videoId 保留。

## 已发布版本

- `0.2.7+9`：当前版本索引，详细发布说明见 `docs/RELEASE_NOTES_0.2.7.md`。
- 历史版本和逐项变更见 `docs/history/changelog/`。
