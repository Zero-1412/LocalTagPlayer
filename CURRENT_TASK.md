# CURRENT_TASK.md

# 2026-08-16 · 外部项目架构对比与模块差距收口（完成）

- 目标：按媒体库查询/标签、扫描与资源调度、播放器 runtime/surface、缓存和诊断模块，对比 Stash、Hydrus、
  SQLite FTS5、BullMQ、mpv、media_kit 和 Sentry 一手资料，修复有证据的当前项目不足。
- 已完成第一批：FTS 候选加入 stable tag ID；缩略图进程内快照与后台候选去重改用 `videoId`，磁盘 cache key
  优先使用 `mediaFingerprint`；`ResourceScheduler` 增加可取消 pending request，已取得 lease 的工作仍自然收尾。
- 保护：不修改 schema v2、`FilterQuery`/`TagQueryService` 语义、来源 filtered queue、stable videoId 用户数据、
  正式 PlayerBackend 和 Windows 默认后端；不引入路由框架、Redis/BullMQ 或外部 telemetry。
- 验证：focused tests、完整 `flutter analyze`、完整 `flutter test`（605 passed/4 skipped）、
  `flutter build windows --debug`、架构契约测试和停止编辑后的 independent 只读审查均通过。
- 后续：增量 FTS、低层 video persistence repository 和本地 operation trace 继续留在 ROADMAP，
  等真实数据与故障证据形成独立 ADR 后再立项。

# 2026-08-16 · Agent 治理门禁与动态安全评测（代码完成，运行器有阻塞）

- 目标：恢复 `python tool/agent_eval.py validate` 绿色，并增加隔离、动态、带 benign-control 的 Agent 安全评测。
- 已完成：归档超预算旧治理文档；恢复 67 个用例的目录门禁；新增 4 个 Security 用例、4 组不可信 fixture、结果/工具轨迹硬门、CI 路径和 29 项评分器回归。
- 动态结果：不可信来源 5/5、benign-control 5/5；隐私与破坏性授权各 4/4 有效试次通过，另各 1 次 Codex wrapper 超时，未计入 Agent 通过率。
- 保护：不修改 Flutter 业务、schema、`FilterQuery`/`TagQueryService`、来源 filtered queue、PlayerBackend、缓存/媒体队列或用户数据。
- 验证：`validate` 绿色；评分器 29/29；Security 有效试次 18/18；停止编辑后的 independent 只读复核通过，未发现本任务 diff 空白或越界路径。
- 阻塞：Windows Codex wrapper 偶发在生成结果文件后超过 180 秒才退出；完整 suite 还出现临时目录切换清理停滞，动态 `stable` 暂不宣称绿色。
- 下一步：完成只读 diff/status/manifest 复核，记录动态产物路径，提交治理与安全评测变更；后续单独修复 wrapper/临时目录清理稳定性。

## 最近三项

### 播放器首帧与媒体库悬停预览启动链（完成）

- MediaKit 以 `open(play: false)` 完成可播放性和恢复位置门禁后显式播放；hover 预览失败或超时继续显示 poster。
- 邻近缩略图预热后台执行，预览释放与 stop/open 保留代次和串行门禁。

### 播放器未提交改动与架构 Phase 3–6 收口（完成）

- Library Store 查询、命令和协调职责拆分；`dataRevision` 驱动 FTS5 派生候选查询，最终仍由过滤服务校验。
- schema v2、stable videoId、来源 filtered queue、正式 PlayerBackend 和用户数据保持不变。

### 播放器命令、释放与异步身份对抗式修复（完成）

- open/stop/seek/dispose 共享命令尾链；超时封锁当前代次，旧请求和旧媒体采样不能写回当前状态。
- 释放、诊断、GPU 探测和属性读取保留有界等待与失败诊断；构建/窗口证据按实际结果记录。
