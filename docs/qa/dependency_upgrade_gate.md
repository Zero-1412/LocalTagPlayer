# 依赖升级门禁

最近检查：2026-09-04

## 2026-09-04 · Flutter 3.47 单依赖隔离门禁

新增 `tool/run_flutter_dependency_upgrade_gate.ps1`，每次只允许
`desktop_drop` 或 `package_info_plus` 一个候选，并在短路径副本中只改该依赖。
门禁固定 Flutter `3.47.0` / framework revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05`，禁止 `dependency_overrides`，依次执行
解析、focused/full tests、analyze、Windows Debug build 和隔离 profile 启动。
本机 native 依赖只接受与总门禁相同的七个 SHA-256 全量匹配种子。

| 候选 | 单独结果 | 裁决 |
| --- | --- | --- |
| `desktop_drop` 0.7.1 → 0.8.4 | 解析、focused/full tests、analyze、Debug build、5 秒启动全部通过 | **DONE**：主约束与 lock 只更新该包 |
| `package_info_plus` 9.0.1 → 10.2.1 | `pub get` 阻断，其余步骤按合同不运行 | **BLOCKED**：不修改主约束 |

`package_info_plus` 的阻断仍是稳定依赖图冲突：10.2.1 要求 `win32 ^6.0.1`，当前
`file_picker 11.0.3` 要求 `win32 ^5.9.0`。解析器建议同时迁移
`file_picker 12.2.0`，但这会违反本轮“一次只试升一个直接依赖”的隔离合同；必须先为
`file_picker 12` 建立独立 API/文件选择器门禁，再从新基线复核 package info。

机器证据位于 ignored 目录 `.local/q/d084f/dependency-gate-summary.json` 与
`.local/q/pi1021a/dependency-gate-summary.json`；摘要不含本机路径，详细日志只留本机。

## 本批次裁决

两个目标稳定版不能在同一依赖图中解析，因此本批次按“稳定版优先、禁止
`dependency_overrides`、禁止用预发布版承载生产门禁”拆分裁决：

| 依赖 | 批次前 | 目标稳定版 | 裁决 |
| --- | ---: | ---: | --- |
| `file_picker` | 8.3.7 | 11.0.3 | **DONE**：升级并迁移静态 API |
| `package_info_plus` | 9.0.1 | 10.2.1 | **BLOCKED**：等待稳定依赖约束收敛 |

## 裁决依据

- [`file_picker` changelog](https://pub.dev/packages/file_picker/changelog) 说明 11.0.0
  把 `FilePicker.platform` 实例 API 改为 `FilePicker` 静态 API；11.0.2 还包含
  Android 路径穿越修复和 Linux 初始目录崩溃修复，因此继续停留在 8.x 不合适。
- [`package_info_plus` changelog](https://pub.dev/packages/package_info_plus/changelog)
  显示 10.1+ 需要 `win32 ^6.0.1`；当前 Flutter 3.44.4 / Dart 3.12.2
  满足它的 SDK 下限，但依赖图不满足。
- 最新本地解析器证据：`file_picker >=8.3.3 <12.0.0-beta.1` 需要
  `win32 ^5.9.0`，而 `package_info_plus >=10.1.0` 需要
  `win32 ^6.0.1`，两个区间无交集。稳定版组合
  `file_picker 11.0.3 + package_info_plus 10.2.1` 因而不可解。
- [`file_picker` 12.2.0](https://pub.dev/packages/file_picker/versions) 已有稳定版并迁移到
  `win32 6.x`，但属于新的主版本/API 与跨平台文件选择器迁移，不能与
  `package_info_plus` 10 合并试升或用 override 掩盖风险。

## 已完成变更

1. `file_picker` 升至 11.0.3，锁文件保存 pub.dev 官方 SHA-256。
2. `DesktopFileSystemAdapter` 的目录、多文件、单文件和保存路径调用全部迁移到
   `FilePicker` 静态 API；既有 `FileSystemAdapter` 业务合同不变。
3. 新增架构契约，要求三类静态入口存在并禁止恢复 `FilePicker.platform`。
4. 生成插件注册文件逐一与 Git index 比对内容哈希，确认没有真实内容变化。
5. focused tests 62 项通过、1 项按平台跳过；`flutter analyze --no-pub`
   零问题；`flutter build windows --debug --no-pub` 成功。
6. 从绝对路径启动 Windows Debug 产物，真实点击“新增本地库路径”，确认原生
   “选择视频目录”对话框打开；取消后仍为 1 个资料库、11232 个视频，未写入用户数据。

## 剩余门禁

`package_info_plus` 保持 9.0.1。满足任一条件后再单独复核 10.x：

1. `file_picker 12` 在独立门禁完成 API、三平台与原生文件选择器回归；或
2. 任一上游稳定版放宽约束，使两个当前直接依赖无需 override 即可解析。

复核批次仍须运行 focused tests、`flutter analyze`、Windows Debug build 和
Linux/macOS workflow；若插件注册或包信息行为变化，必须补充真实平台证据。
每次准备发布或 Flutter SDK major 升级时重新运行本门禁。
