# CURRENT_TASK.md

# 2026-09-04 · 恢复状态视觉门禁与独立依赖试升

## 当前

- 目标：从第一性原理出发，后续修改进行对抗式审查，任务结束后自己给出下一步计划。
- Windows surface 四状态门禁已通过；Computer Use 原生 App 接口不可用的边界已如实记录。
- `desktop_drop` 0.8.4 独立 Flutter 3.47 门禁全绿并带回主分支。
- `package_info_plus` 10.2.1 独立门禁在解析阶段因 `win32` 冲突阻断，主约束保持 9.0.1。
- 11k 统计门禁扩展为 120 次 rebuild/resize 模拟，同 revision 仍只遍历一次。

## 最近三项

- 主工作树 687 项通过、4 项既有跳过，analyze 0 问题，3.44 clean Debug build 与 5 秒启动通过。
- Flutter 3.47 `desktop_drop` 门禁：解析、focused/full tests、analyze、Debug build、启动全通过。
- Windows integration 四项与四张 PNG 通过；11k 在 120 次同 revision resolve 中只访问 11,000 项。

## 阻塞

- Computer Use 返回 `apps: []` 且运行时无 `getApp`；现有截图是 Windows Flutter surface，
  不是 SendInput/UIA 或系统文件选择器证据。
- `package_info_plus` 10.2.1 与 `file_picker` 11.0.3 的稳定 `win32` 约束不可同时解析。

## 下一步

- 先为 `file_picker` 12.2.0 建立独立静态 API、Windows 文件选择器和三平台构建门禁；通过后再复核 `package_info_plus` 10。
- Computer Use 恢复原生 App 接口后，补系统级点击、目录选择器取消和完整 Settings Route 截图。
- 把 11k 同 revision 单遍历门禁保留在常规回归，后续若进入 profile CI 再增加真实 resize 帧时序。
