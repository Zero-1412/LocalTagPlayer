# MediaKit / MPV 稳定性矩阵（2026-07-28）

## 目标

用同一组真实匿名片源、同一套 PlayerPage 正式交互链分别验证 MediaKit 与 Windows
原生 MPV，避免把一个后端的结论套用到另一个后端。

本门禁不修改播放器选择、filtered queue、SQLite、标签或用户数据。macOS 与 Linux
继续只允许 MediaKit；将来若要开放 MPV，必须先分别实现、接入和验证各自的原生
`PlayerBackend`，不能复用 Windows child HWND 结论。

## 矩阵定义

| 场景 | MediaKit | Windows MPV | 自动通过条件 | 发布前附加条件 |
| --- | --- | --- | --- | --- |
| 全屏 | 正式窗口全屏状态机 | 正式窗口全屏状态机 + child HWND | 两次往返后视频表面、当前项和已打开项保持一致 | 人工观察无黑窗、穿透或窗口层级异常 |
| 跨 DPI | Flutter Texture metrics 重算 | Flutter metrics + child HWND 物理矩形重算 | 100%/125%/150%/200%/100% 模拟变化期间表面持续有效 | 必须在两块不同缩放显示器间真实移窗；单显示器不得标记通过 |
| 快速切换 | latest-request 串行 open | latest-request 串行 open | 默认 18 次短间隔请求后只打开最后一次选择，来源队列身份与顺序不变 | 无 |
| 长播 | MediaKit/libmpv Texture | Windows 原生 libmpv/D3D11 | 默认每个后端 30 分钟，持续推进、无音视频停滞、掉帧不超过预算、队列不漂移 | 发布候选机型按实际 GPU/显示器复跑 |

## 工具与证据

- 集成门禁：`integration_test/player_backend_stability_matrix_test.dart`
- 双后端汇总：`tool/run_player_backend_stability_matrix.ps1`
- 匿名状态入口：
  `PlayerPageState.buildStabilitySnapshotForTest` 与
  `jumpToQueueIndexForStabilityTest`
- 汇总报告：
  `.local/qa/player-backend-stability/<时间>/player-backend-stability-matrix.json`

默认命令：

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_player_backend_stability_matrix.ps1
```

其它机器没有本机自然片源时，必须通过 `-SamplePaths` 传入至少三段真实视频。默认
每个后端长播 1800 秒、快速切换 18 次、总掉帧预算 5 帧。只有真实跨 DPI 已在
对应硬件上完成后，才可显式传入 `-PhysicalCrossDpiStatus passed`；该参数不是自动
检测的替代品。

## 本机短门禁结果

本次先用真人面部、动画渐变、暗场三段 650 kbps 1080P 自然片源，各后端长播
15 秒并快速切换 12 次，验证矩阵本身可执行：

| 后端 | 全屏 | 模拟 DPI | 快速切换 | 15 秒长播 | 停滞样本 | 最大总掉帧 |
| --- | --- | --- | --- | --- | --- | --- |
| MediaKit | 通过 | 通过 | 12/12，最终项正确 | 5/5 采样推进 | 0 | 0 |
| MPV | 通过 | 通过 | 12/12，最终项正确 | 5/5 采样推进 | 0 | 0 |

汇总自动门禁为 `passed`，但发布门禁保持
`pending-physical-cross-dpi`。测试机只有一块 2560×1440 显示器，真实跨显示器
DPI 没有执行；15 秒也只证明矩阵可运行，不替代默认 30 分钟发布长播。

## 平台门禁

| 平台 | MediaKit | MPV |
| --- | --- | --- |
| Windows | 可用，纳入本矩阵 | 可用，原生 child HWND/D3D11，纳入本矩阵 |
| macOS | 可用 | 阻塞：尚无 macOS 原生 MPV 后端 |
| Linux | 可用 | 阻塞：尚无 Linux 原生 MPV 后端 |

平台门禁由 `resolvePlayerBackendSelection` 的非 Windows 回退、focused test 和矩阵
汇总共同保护。仅增加 UI 选项、链接 libmpv 或复用 Windows 枚举值，均不构成
macOS/Linux 原生后端完成。
