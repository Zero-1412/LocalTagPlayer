# CURRENT_TASK.md

# 2026-09-04 · file_picker 12 与 package_info 10 串行门禁

## 当前

- 目标：从第一性原理出发，后续修改进行对抗式审查，任务结束后自己给出下一步计划。
- `file_picker 12.2.0` 独立探针与 Flutter 3.47 Windows/Linux/macOS workflow 已全部通过。
- 只有上述探针通过后才运行 `package_info_plus 10.2.1`，其新基线隔离门禁全部通过。
- 主基线已迁移两个稳定版；保存动作直接传真实 bytes，取消不创建 0-byte 文件。
- 11k 统计门禁继续保留 120 次 rebuild/resize 模拟，同 revision 仍只遍历一次。

## 最近三项

- 主工作树 689 项通过、4 项既有跳过，analyze 0 问题，3.44 Debug build 与 5 秒启动通过。
- Flutter 3.47 `package_info_plus 10.2.1` 门禁：解析、focused/full tests、analyze、Debug build、启动全通过。
- Windows/Linux/macOS `file_picker 12.2.0` 探针均完成解析、静态分析与 Debug build。

## 阻塞

- Computer Use 仍返回 `apps: []`；系统级鼠标、目录选择器取消、完整 Settings Route 与
  窗口边框截图尚无 App/Window2 证据。

## 下一步

- 持续保留 `file_picker 12` 三平台 workflow；任一平台失败都回到门禁修复，不降级为文档通过。
- Computer Use 恢复原生 App/Window2 后，补系统级点击、目录选择器取消、完整 Settings Route 与窗口边框截图。
- 把 11k 同 revision 单遍历门禁保留在常规回归，后续若进入 profile CI 再增加真实 resize 帧时序。
