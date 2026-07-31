# Chat 1：架构与跨平台边界

## 所有权

- composition root、模块依赖方向、repository/platform contract；
- SQLite Provider、AppPaths、FileSystemAdapter 和跨平台构建；
- 架构 current contract、ADR、发布边界和迁移安全。

## 必须保持

- Presentation 不拥有平台命令或持久化；
- 扫描器不直接写业务数据库；
- schema migration 向后兼容、幂等并保留用户数据；
- Windows 实现不泄漏到 Dart core；
- current contract 写 `ARCHITECTURE.md`，时间线进入 history/ADR。

## 非目标

不借架构整理重写业务、改变过滤/队列语义或自动启用实验播放器后端。

历史：`docs/history/chat/CHAT_1_ARCHITECTURE_THROUGH_2026-07-30.md`。
