# Chat 3：媒体库标签发现 UI

## 所有权

- grouped filter sidebar、current filter chips、result count；
- 搜索、排序、视图切换和响应式媒体库布局；
- 保存筛选入口的 UI（不提前实现 Smart List 业务）。

## 必须保持

- UI 只提交 `FilterQuery`，不复制过滤；
- 二级标签显示父级且不能越级筛选；
- 搜索统一走稳定 controller；
- 标签点击先更新结果，计数/预取延后并取消过期任务；
- 路径、标签、排序变更验证真实加载和流畅度；
- “更多”先展示菜单，危险动作确认。

## 非目标

不拥有 SQLite、PlayerBackend、filtered queue 内容或缓存策略。

历史：`docs/history/chat/CHAT_3_MEDIA_LIBRARY_TAG_UI_THROUGH_2026-07-30.md`。

分阶段帧、重复路由与启动测量见 `docs/qa/phase_frames_and_upgrade_acceptance_20260905.md`。
标签动画及结果替换的优化必须同时复测操作时延和 build/raster/total 帧分位数，失败等待窗口单列。
