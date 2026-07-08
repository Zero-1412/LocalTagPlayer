# Chat 7 主界面 smoke 补充记录

## 任务

对 debug exe 启动后的主界面做第一轮 smoke test，目标是确认主界面功能无大问题，发现问题后小范围修复。

## 覆盖入口

- 媒体库、最近播放、智能收藏。
- 标签中心、设置、排序菜单。
- 右侧标签筛选面板收起和恢复。
- 主界面底部“播放”入口到播放器页面，并确认右侧筛选结果队列来自当前列表。

## 修复

- 右侧标签筛选面板收起后，恢复窄条原本只暴露为普通文本，自动化和辅助技术无法稳定识别“展开标签筛选”按钮。
- 收起窄条已补充按钮语义、Tooltip 和稳定 smoke key：`LibrarySmokeKeys.collapsedTagRail`。
- 新增 `collapsedTagDiscoveryRailSmokeHarness` widget smoke test，覆盖 key、Tooltip 和点击回调。

## 非目标

- 未修改 SQLite schema。
- 未修改 `FilterQuery` / `TagQueryService` 查询语义。
- 未修改播放器 filtered queue、open worker 或播放 backend。
- 未修改缩略图/media 队列。
- 未进入 Smart List、missing / relink、标签删除/合并迁移范围。

## 验证

```powershell
dart format lib\src\widgets\library_widgets.dart test\widget_test.dart
flutter test
flutter analyze
flutter build windows --debug
```

结果：全部通过。

真实窗口复测：右侧标签面板收起后可见“展开标签筛选”按钮语义，点击窄条可恢复面板；主界面底部播放入口可进入播放器，队列显示 `1 / 11078`，返回主界面正常。

## 2026-07-08 追加 QA

- 顶部搜索框从 `SearchBar` 改为 `TextField`，用于稳定真实键盘和 widget 输入链路。
- 新增顶部搜索框 widget smoke test：输入 `lupa` 后，controller 与 `onSearchChanged` 同步更新。
- 真实窗口中，Computer Use 的 `type_text` / `set_value` 对 Flutter Windows 文本控件仍不稳定；逐键输入可触发搜索筛选，说明真实键盘链路已接入 `onChanged`。
- 本轮尝试继续覆盖目录管理弹窗、添加目录取消、本地媒体库路径进入、右侧一级/二级筛选；但 Windows 自动化出现前台窗口进程状态异常，未完成稳定截图级复测。
- 人工复测路径保留：打开/关闭目录管理弹窗；点击“添加目录”后取消；点击左侧本地媒体库 root 进入路径浏览并返回；点击右侧一级标签和全部二级标签，确认当前筛选 chips 与结果数量收敛。

## 2026-07-08 布局缩放真实窗口验证

- debug exe 普通窗口约 1268px 宽时，左侧导航、中央结果区和右侧标签筛选均可见，中心区保持 3 列视频卡片，未出现横向 overflow。
- 最大化约 2560px 宽时，左侧导航扩展到宽屏上限，右侧标签筛选扩展到宽屏上限，中央结果区扩展为 6 列视频卡片，三栏比例未退回固定宽度表现。
- 验证后关闭 debug exe；本次没有进入标签查询、播放队列、schema 或缓存队列改动范围。

## 2026-07-08 主界面布局缩放补测

- expanded 主界面三栏宽度改为基于窗口总宽度计算：左侧导航约 20%，右侧标签筛选约 32%，中央结果区使用剩余空间。
- 右侧标签筛选面板不再固定 482px，放大窗口时会随窗口增长；缩小时会在最小宽度保护内收缩，优先保留中央视频结果区。
- 新增 `mainLibraryLayoutSlotsForWidth` 测试，验证 1280 / 1600 / 1920 宽度下左右栏与中央区同步增长，并验证三栏宽度总和等于窗口宽度。
- 本次只调整主界面视觉布局比例，不修改标签筛选语义、播放队列、SQLite schema 或缓存队列。
