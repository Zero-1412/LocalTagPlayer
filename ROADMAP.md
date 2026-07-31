# ROADMAP.md

## 当前阶段

Local Tag Player 已完成标签发现、稳定身份、filtered queue、标签维护、缓存诊断、
响应式 UI 和双平台发布的一阶段闭环。当前属于复杂系统治理和稳定交付阶段，
不是扩展为通用专业播放器的阶段。

本文件只保存未来优先级和明确非目标。旧计划、完成记录和实验路线已归档到
`docs/history/roadmap/ROADMAP_HISTORY_THROUGH_2026-07-30.md`。

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
6. 在隔离兼容批次升级 `file_picker` 8 → 11 和 `package_info_plus` 9 → 10；不得混入治理或 UI 变更，准入条件见 `docs/qa/dependency_upgrade_gate.md`。

## P1：核心闭环深化

1. 大媒体库下持续验证筛选、排序、路径切换和返回状态的交互延迟。
2. 巩固 `videoId + fingerprint + mutable path + missing` 数据恢复闭环。
3. 完善 relink、批量路径替换和依赖备份的失败恢复证据。
4. 继续验证 manual/folder/locked 来源分离和 Tag Manager 批量操作。
5. 把真实事故和高价值 QA 转成 focused/page-level/Agent regression 门禁。
6. 改善缩略图、媒体探测和播放并发时的取消、限流和诊断。
7. 补齐 macOS/Linux adapter 的真实设备验证，不把 Windows 假设上移。

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
