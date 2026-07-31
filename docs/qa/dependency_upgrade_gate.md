# 依赖升级门禁

最近检查：2026-07-31

## 本批次裁决

两个目标稳定版不能在同一依赖图中解析，因此本批次按“稳定版优先、禁止
`dependency_overrides`、禁止用预发布版承载生产门禁”拆分裁决：

| 依赖 | 批次前 | 目标稳定版 | 裁决 |
| --- | ---: | ---: | --- |
| `file_picker` | 8.3.7 | 11.0.2 | **DONE**：升级并迁移静态 API |
| `package_info_plus` | 9.0.1 | 10.2.1 | **BLOCKED**：等待稳定依赖约束收敛 |

## 裁决依据

- [`file_picker` changelog](https://pub.dev/packages/file_picker/changelog) 说明 11.0.0
  把 `FilePicker.platform` 实例 API 改为 `FilePicker` 静态 API；11.0.2 还包含
  Android 路径穿越修复和 Linux 初始目录崩溃修复，因此继续停留在 8.x 不合适。
- [`package_info_plus` changelog](https://pub.dev/packages/package_info_plus/changelog)
  显示 10.1+ 需要 `win32 ^6.0.1`；当前 Flutter 3.44.4 / Dart 3.12.2
  满足它的 SDK 下限，但依赖图不满足。
- 本地解析器证据：`file_picker >=8.3.3 <12.0.0-beta.1` 需要
  `win32 ^5.9.0`，而 `package_info_plus >=10.1.0` 需要
  `win32 ^6.0.1`，两个区间无交集。稳定版组合
  `file_picker 11.0.2 + package_info_plus 10.2.1` 因而不可解。
- [`file_picker` 12 当前只有预发布版](https://pub.dev/packages/file_picker/versions)。
  门禁不以 beta 包或 `dependency_overrides` 掩盖稳定版冲突；这会把上游兼容风险
  转嫁给文件选择、插件注册和跨平台打包。

## 已完成变更

1. `file_picker` 升至 11.0.2，锁文件保存 pub.dev 官方 SHA-256。
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

1. `file_picker 12` 发布稳定版并与 `win32 6.x`、当前 Flutter 稳定版共同可解；或
2. 任一上游稳定版放宽约束，使两个直接依赖无需 override 即可解析。

复核批次仍须运行 focused tests、`flutter analyze`、Windows Debug build 和
Linux/macOS workflow；若插件注册或包信息行为变化，必须补充真实平台证据。
每次准备发布或 Flutter SDK major 升级时重新运行本门禁。
