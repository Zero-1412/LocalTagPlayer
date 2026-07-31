# 依赖升级门禁

最近检查：2026-07-31

## 当前结论

`flutter pub outdated --no-dev-dependencies` 返回成功，但发现两个直接依赖需要跨 major 升级：

| 依赖 | 当前 | 可解析稳定版 | 裁决 |
| --- | ---: | ---: | --- |
| `file_picker` | 8.3.7 | 11.0.2 | DEFER：单独兼容批次 |
| `package_info_plus` | 9.0.1 | 10.2.1 | DEFER：单独兼容批次 |

本轮是 Agent 治理、文档分层和 QA 自动化生命周期整治，不改变应用依赖。直接把 major 升级混入治理提交会扩大平台插件、生成注册文件和打包验证范围；当前工作树还存在用户自己的生成注册文件改动，因此本轮升级会产生不可可靠归因的冲突。保持当前锁文件不是宣称“无需升级”，而是拒绝未经隔离验证的跨 major 变更。

## 解除门禁条件

依赖升级必须作为独立任务完成：

1. 先核对两个包从当前版本到目标版本的 changelog 和最低 Flutter/Dart/平台要求。
2. 只在干净、隔离的工作树更新 `pubspec.yaml`、`pubspec.lock` 和必要的生成注册文件。
3. 运行 focused tests、`flutter analyze`、Windows debug build，并核对 Linux/macOS workflow。
4. 若插件注册、文件选择权限或包信息行为变化，补充对应回归证据后才允许提交。

每次准备发布或 Flutter SDK major 升级时重新运行本门禁。
