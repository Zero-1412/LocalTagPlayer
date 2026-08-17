# 全局 UI 标准盘点与复用边界（2026-08-17）

## 结论

当前工程已经有一套可复用的 Apple 式基础 token 和 `AppInteractionSurface`，但页面级
仍存在多处直接组合 `Material`、`InkWell`、`Tooltip`、`Semantics` 的交互外壳。
本轮先收口用户最常使用、且存在展开/折叠重复实现的主界面功能栏，新增
`AppNavigationItem` 作为共享导航入口；其它带有特殊手势、覆盖层、拖动或业务语义的
控件暂不机械替换，避免为了格式统一破坏既有行为。

## 已确认的统一标准

| 范畴 | 统一标准 |
| --- | --- |
| 圆角 | 控件使用 `AppRadius.control`，卡片使用 `AppRadius.card`，面板使用 `AppRadius.panel`，浮层使用 `AppRadius.floating` |
| 间距 | 使用 `AppSpacing` 四像素节奏，不在页面新增相近的 magic number |
| 交互 | 普通点击入口优先使用 `AppInteractionSurface`；它统一 press、hover、focus、键盘激活和 reduced motion |
| 导航 | `AppNavigationItem` 同时承载展开/折叠密度、选中态、禁用态、tooltip 和 `Semantics(selected: ...)` |
| 命中区 | 主导航展开高度 38px，折叠入口 46px；工具栏关键动作继续遵循现有 40–48px 标准 |
| 颜色 | 结构表面保持实色；紫色只表达选中、焦点和明确的品牌/主动作，不用持续阴影制造可点击感 |
| 无障碍 | 保留稳定 label、selected、enabled、键盘焦点、文本缩放、高对比度和 reduced motion 链路 |
| 业务边界 | UI 只转发意图；过滤继续走 `FilterQuery` / `TagQueryService`，播放继续消费来源 filtered queue |

## Before / After

| 区域 | Before | After |
| --- | --- | --- |
| 主功能栏展开入口 | `LibrarySidebarNavItem` 自己组合 `Padding`、`Semantics`、`Material`、`InkWell` 和选中装饰 | 复用 `AppNavigationItem`，统一交互表面、选中语义和 38px 高度 |
| 主功能栏折叠入口 | `CollapsedSidebarItem` 再次复制 tooltip、语义、`Material`、`InkWell` 和 46px 图标按钮 | 与展开入口共享 `AppNavigationItem`，只切换内容密度，保留 tooltip 和 46px 命中区 |
| 主功能栏品牌折叠按钮 | 品牌区单独组合 `Material`、`InkWell` 和语义 | 复用 `AppInteractionSurface`，保留品牌色、旋转反馈、稳定 key 和原有回调 |
| 主功能栏偏好 | 只在当前 Route 保存，初始为展开 | 首次使用默认折叠；通过现有 `library_sort.json` 保存，下一次进入恢复上次状态 |
| 旧偏好文件 | 没有主功能栏字段 | 缺字段按折叠处理；显式 `false` 保留为展开，兼容旧文件且不改 schema |

## 全局盘点与后续迁移顺序

已经检查媒体库、播放器、标签管理、设置和维护页的直接交互外壳。当前可以分为三类：

1. 可直接复用基础交互表面的普通导航/动作入口：优先迁移到
   `AppInteractionSurface` 或 `AppNavigationItem`。
2. 带有长按排除、滑动删除、拖动进度、原生纹理覆盖、菜单 anchor 或连续动画的控件：
   保留页面专用实现，只复用 token、无障碍和局部主题，不能用通用按钮覆盖其状态机。
3. 卡片、对话框、bottom sheet、popup menu、chip、dropdown、snackbar：按组件族建立
   一个 owner 和 focused tests，再逐页迁移，避免同时改变多个页面的视觉和交互。

建议下一轮顺序：标签发现的普通行/上下文入口 → 播放器队列的普通动作 → 设置与维护页
列表项 → 共享浮层（menu、dialog、tooltip、snackbar）。每一族迁移前都要保留入口、
key、tooltip、快捷键、返回路径、危险动作确认和业务回调的页面级可达性证据。

## 本轮明确不改变的边界

- 不修改 `FilterQuery`、`TagQueryService`、标签层级和计数语义。
- 不修改来源页面的 filtered playback queue、播放器当前序号或返回筛选状态。
- 不修改缩略图/媒体详情队列、缓存后端、schema、stable identity、missing/relink 或用户数据。
- 不全局替换所有 `Material` / `InkWell`；特殊交互必须保留其局部状态机和性能策略。

## 验证记录

- `test/library_view_preferences_controller_test.dart`：默认折叠、旧 JSON 兼容、展开状态往返。
- `test/app_theme_tokens_test.dart`：共享导航入口展开 38px、折叠 46px、选中语义和 tooltip。
- `test/widget_test.dart`：主界面展开/折叠动作、入口可达性和现有页面行为。
- `flutter analyze`、`flutter build windows --debug` 与真实窗口检查在停止编辑后执行；真实窗口需检查首次默认折叠、切换后重新进入恢复、100/125/150% 文本缩放、high contrast、reduced motion、无溢出和 tooltip。

