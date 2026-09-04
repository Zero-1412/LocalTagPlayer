# CURRENT_TASK.md

# 2026-09-04 · file_picker 12 与 package_info 10 串行门禁

## 当前

- 目标：从第一性原理出发，后续修改进行对抗式审查，任务结束后自己给出下一步计划。
- `file_picker 12.2.0` 独立探针已通过 Flutter 3.47 Windows 静态 API 与 Debug build；三平台 workflow 已建立。
- 只有上述探针通过后才运行 `package_info_plus 10.2.1`，其新基线隔离门禁全部通过。
- 主基线已迁移两个稳定版；保存动作直接传真实 bytes，取消不创建 0-byte 文件。
- 11k 统计门禁继续保留 120 次 rebuild/resize 模拟，同 revision 仍只遍历一次。

## 最近三项

- 主工作树 689 项通过、4 项既有跳过，analyze 0 问题，3.44 Debug build 与 5 秒启动通过。
- Flutter 3.47 `package_info_plus 10.2.1` 门禁：解析、focused/full tests、analyze、Debug build、启动全通过。
- Windows `file_picker 12.2.0` 探针解析、静态分析与 Debug build 全通过；Linux/macOS 等待远端 runner。

## 阻塞

- Computer Use 仍返回 `apps: []`；系统级鼠标、目录选择器取消、完整 Settings Route 与
  窗口边框截图尚无 App/Window2 证据。
- Linux/macOS 的实际构建结果必须由新 workflow 的对应 runner 产出，本机 Windows 不冒充通过。

## 下一步

- 推送后读取 `file_picker 12` 三平台 workflow 结果；任一平台失败都回到门禁修复，不降级为文档通过。
- Computer Use 恢复原生 App/Window2 后，补系统级点击、目录选择器取消、完整 Settings Route 与窗口边框截图。
- 把 11k 同 revision 单遍历门禁保留在常规回归，后续若进入 profile CI 再增加真实 resize 帧时序。
