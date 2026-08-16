# CHANGELOG.md

本文件只保存未发布变更和版本索引。完整历史位于
`docs/history/changelog/`，不要把旧条目复制回根文件。

## Unreleased

### 媒体库首页 Phase 1 视觉重构

- 建立媒体库首页 Before/After 视觉目标，明确页面上下文、搜索、活动筛选、标签发现和视频结果的层级关系。
- 左侧导航选中态改为轻量底色加定位线；搜索焦点和视频卡片 hover 的阴影收敛，减少结构表面对内容的干扰。
- 标签发现面板新增只过滤可见标签的稳定搜索入口；不创建新的筛选条件，不触发媒体库查询，也不改变标签父子语义。
- `FilterQuery`、`TagQueryService`、filtered queue、缩略图/媒体详情队列、PlayerBackend、schema 和用户数据保持不变。

### 缩略图缓存缺失补全

- 缓存诊断页新增“生成缺失缓存”明确入口；媒体库首帧后延迟登记一次自动补全，用户也可以按需手动开始。
- 缩略图后台候选改为惰性分批生产并持续推进，保留 500 项窗口、24 个后台校验请求和既有 FFmpeg/资源调度限制，
  超过窗口的候选不再被截断；启动时已有扫描预取会顺序让位，播放期间仍暂停后台补全并保留可视缩略图优先。
- 多核机器的缩略图后台生成并发从最多 2 个提高到最多 3 个；共享资源总预算仍为 4，前台缩略图和播放门禁不变。
- 媒体详情/时长补全也改为最多 500 项惰性窗口和 8 项 FFprobe 小批次；应用首帧后错峰自动补齐安全的 active 项目，
  已知失败项不在启动时循环重试，继续由诊断页显式重试。
- 重新核对启动后台任务：备份续跑、稳定计数和缓存/媒体详情补全自动执行；新视频扫描、无效记录清理和视觉相似度扫描仍保留
  用户确认或设置门禁，所有任务继续共享总资源预算和播放让渡边界。

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

- `0.2.8+10`：当前版本索引，详细发布说明见 `docs/RELEASE_NOTES_0.2.8.md`。
- 历史版本和逐项变更见 `docs/history/changelog/`。
