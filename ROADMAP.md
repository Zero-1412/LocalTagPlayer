# ROADMAP.md

## 当前阶段

Local Tag Player 已完成标签发现、稳定身份、filtered queue、标签维护、缓存诊断、
响应式 UI 和双平台发布的一阶段闭环。当前属于复杂系统治理和稳定交付阶段，
不是扩展为通用专业播放器的阶段。

本文件只保存未来优先级和明确非目标。旧计划、完成记录和实验路线已归档到
`docs/history/roadmap/ROADMAP_HISTORY_THROUGH_2026-07-30.md`。

## 架构演进路线

以下路线服务于核心闭环和用户数据保护，按依赖顺序推进；每阶段必须有独立契约和可回滚
边界，不与无关播放器视觉或实验功能捆绑：

1. **Phase 0（已完成）**：架构 ADR、依赖方向门禁、架构指标和旧库 fixture。
2. **Phase 1（已完成）**：`videoId` 主索引、path 辅助索引和 stable-ID 命令 API。
3. **Phase 2（已完成）**：schema migration，将 `videoId` 设为主身份、path 设为可变唯一字段。
4. **Phase 3（已完成）**：`LibraryRepositoryContext` 统一单数据库、stable/path 双索引和事务；真实的查询、标签/收藏命令与 root/扫描/relink 协调逻辑分别迁入 `LibraryStoreQueryService`、`LibraryStoreCommandService`、`LibraryStoreCoordinatorService`。`LibraryStore` 仍保留兼容端口及低层 stable-ID 视频持久化 owner，不复制状态、不打开第二连接。
5. **Phase 4（已完成）**：`ResourceScheduler` 统一扫描、探测、缩略图、视觉和备份资源预算。
6. **Phase 5（契约拆分已完成）**：`PlayerRuntimeBackend` 与 `PlayerSurfaceRenderer` 已独立注入，兼容保留 `PlayerBackend`；具体 runtime/surface adapter 暂不继续拆，待出现真实后端替换需求和独立收益证据再推进。
7. **Phase 6（已完成，FTS5 已通过基准启用）**：候选查询已接入 `LibraryQueryController`/Facade；`dataRevision` 驱动可重建 trigram FTS5 派生索引，失败安全回退完整 Dart 查询。隔离副本上的真实 11,194 条库基准显示完整筛选平均 75.63ms，FTS 候选加最终校验平均 0.484ms，候选路径获胜且结果集合一致；冷索引建立 430.17ms 只作为一次性成本记录。

Phase 3–6 不得改变 `FilterQuery` 语义、来源 filtered queue、用户数据绑定或正式 Windows
播放器默认后端；每次跨 schema/core/platform contract 修改都必须同步更新架构 ADR 和 focused
验证。

## P0：治理和可信交付

1. 完成 Agent 治理整治：
   - 默认上下文预算与 PR 门禁；
   - current/history 文档分层；
   - QA runner manifest 与可移植路径；
   - 已完成实验归档和索引。
2. 保持 Windows 主体验、SQLite 数据和 filtered queue 稳定。
3. 配置 Windows Authenticode 与 macOS Developer ID/公证外部凭据。
4. 在真实已安装旧版本上验证应用内升级、摘要、中文安装和数据保留。
5. GitHub Support purge 完成后验证旧 Commit API 缓存清理。
6. `file_picker` 8 → 11 已在隔离兼容批次完成；`package_info_plus` 9 → 10
   等待稳定版 `win32` 约束收敛，不得使用 beta 或 `dependency_overrides` 绕过。
   准入条件与证据见 `docs/qa/dependency_upgrade_gate.md`。

## P1：核心闭环深化

1. 大媒体库下持续验证筛选、排序、路径切换和返回状态的交互延迟。
2. 巩固 `videoId + fingerprint + mutable path + missing` 数据恢复闭环。
3. 完善 relink、批量路径替换和依赖备份的失败恢复证据。
4. 继续验证 manual/folder/locked 来源分离和 Tag Manager 批量操作。
5. 把真实事故和高价值 QA 转成 focused/page-level/Agent regression 门禁。
6. 改善缩略图、媒体探测和播放并发时的取消、限流和诊断。
7. 补齐 macOS/Linux adapter 的真实设备验证，不把 Windows 假设上移。
8. 根据 `ADR-005` 的外部模块对比，继续用真实数据决定增量 FTS、低层 video persistence 拆分和本地
   operation trace；没有稳定收益证据前不引入 Redis/BullMQ、路由框架或外部 telemetry。

## P2：有证据再推进

1. 自动标签规则与标签导入/导出。
2. 高级搜索语法和可保存筛选。
3. 高级 fingerprint 去重与可选文件整理。
4. Android/iOS 探索；Web 保持低优先级。
5. 只有核心闭环和用户数据保护持续稳定后，才评估高级播放器功能。

## 播放器研究边界

- MediaKit Texture 保持正式默认；
- Windows native mpv/child HWND 保持显式 QA/诊断路径；
- NVIDIA VSR/HDR 只有驱动真实性、许可、发布、回退和性能门禁都通过才可晋级；
- **NVOFA 插帧降级为独立长期研究**，不进入当前产品路线；
- VapourSynth、NVOFA、本机增强插件和专业画质研究统一标记为**非自动后续**；
- 不把显示同步插值宣传为 AI 补帧，不把锐化/缩放宣传为恢复源细节。

## 当前非目标

- 取代 PotPlayer/VLC；
- 字幕、音轨、逐帧、A-B loop 等专业播放器工作流；
- 为尚未出现的问题新增跨平台抽象；
- 未经迁移验证的标签删除/合并或媒体物理移动；
- 自动启用实验性 native/NVIDIA 路径；
- 为追求文档完整而把历史重新放回默认上下文。

## 优先级变更规则

新增或调整优先级时：

1. 说明它保护核心闭环的哪一部分；
2. 给出用户证据、生产事故、性能数据或发布阻塞；
3. 说明非目标和受保护行为；
4. 更新 `CURRENT_TASK.md` 的下一步；
5. 完成项移入 `CHANGELOG.md`/dated QA，不留在本文件形成时间线。
