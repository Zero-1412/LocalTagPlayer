---
name: ltp-apple-ui-design
description: Local Tag Player 的 Apple 式全应用 UI 设计与审查技能。用于媒体库、播放器、标签中心、设置、缓存诊断、Missing/Relink、弹窗、菜单、空状态的视觉重构、动效设计、交互精修、响应式适配、无障碍降级或 UI diff 审查；把 Apple 的克制、层级、直接反馈和流体动效转译为 Flutter Windows 实现，同时保护标签筛选性能、filtered queue 和用户数据。
---

# Local Tag Player Apple UI Design

把“Apple 风格”理解为清晰层级、克制材质、即时反馈、空间连续性和精细排版，不理解为复制 macOS 控件或给所有表面添加毛玻璃。

## 必读路由

- 所有设计或实现任务先读 [references/apple-ui-foundations.md](references/apple-ui-foundations.md)。
- 涉及动画、hover、拖拽、侧栏、sheet、route transition 或动效审查时，再读 [references/motion-craft.md](references/motion-craft.md)。
- 用户只会描述“弹一下”“像 iOS 回弹”等模糊感受时，读 [references/motion-vocabulary.md](references/motion-vocabulary.md)。
- 全应用迁移或跨页面任务还要读 `docs/design/APPLE_UI_MIGRATION.md`，一次只执行其中一个阶段。

## 开始任务

先输出最短确认：

```text
Product goal protected:
Core loop part protected:
Must not change:
Apple-style intent:
Smallest safe change:
Performance risk:
```

根据 `AGENTS.md` 选择 Level 1/2/3。单页面或组件通常是 Level 2；只有触及共享 contract、schema、平台边界、播放器后端或稳定身份时才升级 Level 3。

## 设计人格

目标感受：

```text
calm
precise
premium
content-first
desktop-efficient
```

执行规则：

1. 让视频、标签和当前任务成为视觉中心，装饰不能抢占内容注意力。
2. 结构区域使用稳定、较重的深色表面；浮动工具条、菜单和 sheet 才允许轻量半透明层次。
3. 紫色强调色只表达选择、焦点和关键动作，不铺满大面积背景。
4. 同一功能在媒体库、播放器和维护页使用相同图标、命名、圆角、间距和状态反馈。
5. Windows 桌面优先保持鼠标、键盘、tooltip、右键/更多菜单和高信息密度；不要强行套用移动端导航。
6. 简洁不等于隐藏。常用路径直接可见，高级设置进入下一层，危险操作提供确认或撤销。

## 动效决策

写动画前依次回答：

1. 用户一天会看到多少次？
2. 动画目的属于反馈、空间连续、状态说明还是避免跳变？
3. 是否能在既定时长预算内完成？
4. 是否会延迟筛选、排序、播放或文字输入？

高频键盘动作、搜索输入、列表导航和标签结果提交不得等待装饰动画。弹簧只用于真实拖拽、滑动和可被用户中途反向的物理交互；普通菜单、按钮和侧栏默认使用短、无弹跳的过渡。

## Flutter 实现边界

- 优先复用 `app_theme_tokens.dart`、现有 Theme、`Animated*`、`AnimationController` 和 `RepaintBoundary`，不为视觉效果先引入依赖。
- 直接操作使用 `InkWell`、`FocusableActionDetector`、`Semantics` 或稳定 Flutter 手势链路；不要为缩放效果破坏键盘和辅助技术语义。
- 位移、缩放和淡入优先使用 `Transform` / `SlideTransition` / `ScaleTransition` / `FadeTransition`；动画中避免全列表重建和业务查询。
- `BackdropFilter`、动态 blur、逐帧阴影和大面积透明层默认视为性能风险。只有浮层、范围小、有实色降级且真实窗口测量通过时才能使用。
- 遵守 `MediaQuery.disableAnimations`、`accessibleNavigation` 和 `highContrast`。降低动效时保留颜色、焦点和状态反馈，移除大幅位移、弹跳和视差。
- 中文界面默认使用系统字体链路。中文正文不套用 Web 示例里的固定负字距；字号、字重、行高和文字缩放一起验收。

## 绝对保护项

视觉任务默认不得修改：

```text
SQLite schema
FilterQuery / TagQueryService semantics
folder primary / child hierarchy
filtered playback queue contents or order
PlayerBackend behavior
thumbnail / media-details queue behavior
stable video identity or user data
```

标签点击必须先反馈选择状态和可见结果；计数、缩略图预取和其它重任务继续延后或取消过期任务。播放器必须继续消费来源 filtered queue。

## 实施工作流

1. 读取当前页面、直接组件、现有 widget tests 和最近真实窗口记录。
2. 列出当前状态、目标状态和不改内容；复用已有 token，避免平行设计系统。
3. 一次只改一个页面或一个基础组件族。先基础 token，再组件，再页面，不做全项目机械换色。
4. 为新增或修改的类、字段、方法、参数和关键分支同步写中文维护注释。
5. 先跑 focused widget tests，再跑完整静态验证和 Windows debug build。
6. 自动启动应用，真实点击本阶段入口并截图；检查位置、遮挡、对齐、溢出、对比度、焦点和状态反馈。
7. 对动画做快速反向、连续点击、慢速观察和大媒体库帧耗时检查。

## 设计审查输出

审查 UI 或 motion diff 时，必须先输出表格：

| Before | After | Why |
| --- | --- | --- |
| 当前代码或行为 | 精确目标 | 对用户、性能或一致性的影响 |

随后按以下顺序给出结论：

1. 破坏即时感或核心流程的问题。
2. 应删除或减弱的无目的装饰。
3. layout、paint、GPU、列表 rebuild 或 blur 风险。
4. 可中断性、进入/退出路径和时序。
5. 排版、材质、图标、间距和跨页面一致性。
6. reduced motion、高对比度、文字缩放、键盘和语义。

没有明显问题时明确批准，不为凑数量制造建议。动效机会审查整应用最多给 5–7 项，并同时列出至少 2 项主动拒绝的动画候选。

## 完成前对抗式审查

```text
schema: unchanged / changed with migration notes
FilterQuery / TagQueryService: unchanged / changed intentionally
filtered queue: unchanged / changed intentionally
thumbnail/media queue: unchanged / changed intentionally
user data: preserved / risk noted
motion accessibility: verified / blocker noted
large-library performance: verified / blocker noted
real-window screenshots: verified / blocker noted
prompt impact: satisfies first principles / adds unnecessary scope
```

上游设计知识改编自 `emilkowalski/skills`，许可与来源见本 skill 目录中的 `LICENSE`。
