# 当前 QA Gate

本目录只保存仍会影响当前发布或开发判断的短 gate。带日期的实验、压力测试和研究证据已经迁入 `docs/history/qa/`，避免默认上下文把历史结果误当成当前能力。

| 当前文件 | 作用 |
| --- | --- |
| `NVIDIA_VSR_HDR_GATE.md` | NVIDIA VSR / HDR 启用与降级门槛 |
| `dependency_upgrade_gate.md` | 跨 major 依赖升级的隔离与验证门槛 |
| `main_window_latency_smoke.md` | 主窗口延迟 smoke 契约 |
| `main_window_semantic_stress_gate.md` | 主窗口语义压力门禁 |
| `performance_full_test_standard.md` | 压测、性能优化与 L3 全测标准 |
| `player_p0_p1_evidence_package_20260820.md` | 播放器 P0 本机真实性能证据包、P1 可见性边界与外部验收清单 |
| `windows_hardware_decode_matrix.md` | Windows 硬解兼容矩阵 |

自动化脚本的状态、最近验证日期、证据和替代命令统一登记在 `tool/qa/manifest.json`。新增、移动或退役 QA 脚本时必须同步更新清单；治理 CI 会拒绝漏登记脚本和失效证据路径。
