# Chat 7：响应式 UI 与平台 polish

## 所有权

- compact/medium/expanded 布局；
- 跨页面视觉一致性、键盘、reduced motion 和高对比度；
- macOS/Linux 的展示层适配点。

## 必须保持

- 主要入口在窄窗、最大化和全屏可达；
- 菜单、弹窗、Overlay、队列和诊断无裁切/遮挡/溢出；
- 动画不阻塞标签筛选、播放或后台协调；
- UI 变更完成真实点击、截图和无障碍降级检查；
- 视觉重构不删除未获授权功能或改变业务语义。

## 非目标

不拥有 SQLite、过滤语义、PlayerBackend、缓存后端或 stable identity。

历史：`docs/history/chat/CHAT_7_RESPONSIVE_UI_THROUGH_2026-07-30.md`。
