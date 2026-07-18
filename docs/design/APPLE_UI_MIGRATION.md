# Local Tag Player Apple 式全应用 UI 迁移蓝图

状态：Phase 0 已完成；Phase 1 已启动，搜索与筛选状态组件族已完成。

## 目标

把全应用统一为平静、精确、内容优先的桌面媒体体验：结构清晰、材质克制、反馈即时、动效可中断、文字易读、焦点明确，并在 11,000 条真实媒体库和播放状态下保持流畅。

Apple 式观感不等于复制 macOS，也不等于全窗口毛玻璃。Windows 当前是主要平台，因此保留桌面信息密度、鼠标/键盘深度工作流、系统文件选择器和现有平台边界。

## 不可改变

```text
folder 一级/二级标签层级
FilterQuery / TagQueryService 语义
搜索 TextField 输入链路
filtered playback queue 内容与顺序
PlayerBackend / FFmpegBackend 行为
thumbnail / media-details queue
stable video identity 与用户数据
```

## 视觉系统方向

### 层级

```text
画布: 稳定深色背景
结构表面: 较实的侧栏、详情、设置分组
交互表面: 搜索、筛选、按钮、卡片状态
浮动表面: 菜单、popover、sheet、dialog
```

结构表面继续以实色和弱描边为主。只有小范围浮动表面允许半透明、柔和高光和 blur；必须提供实色降级并通过真实 GPU/raster 验证。

### 设计人格

```text
calm / precise / premium / content-first / desktop-efficient
```

- 紫色只表达当前选择、焦点和主动作。
- 视频画面、标签上下文和文件名优先于装饰。
- 常用操作直接可见，高级操作下一层，危险操作确认或可撤销。
- 圆角、阴影、动画和透明度必须能解释层级或状态，不做无目的统一堆叠。

### 动效

```text
press: 90-140ms
hover/focus: 120-180ms
popover/dropdown: 120-220ms
route/dialog: 180-240ms
drawer/side sheet: 240-320ms
```

普通 UI 无弹跳；只有真实拖拽、滑动或动量释放使用 spring。键盘输入、快捷键、标签结果提交和排序不得等待装饰动画。reduced motion 下移除位移、弹跳和视差，保留短淡入和状态颜色。

## 分阶段实施

### Phase 0：共享 token 与无障碍策略

目标：先建立所有页面共同依赖的视觉语言，不改变页面信息架构。

范围：

- 整理颜色、材质、圆角、间距、排版、阴影和语义动效 token。
- 建立 `disableAnimations`、`accessibleNavigation`、`highContrast` 降级策略。
- 建立可复用 press/focus/hover 表面，但保留 `InkWell`、键盘和 Semantics。
- 建立浮层实色与可选透明材质，不默认启用大面积 blur。
- 增加 token、文字缩放和 reduced-motion focused tests。

主要候选文件：

```text
lib/src/widgets/app_theme_tokens.dart
lib/src/app.dart
新建少量 lib/src/widgets/design_system/* 基础组件
test/widget_test.dart 或对应 focused tests
```

完成门槛：没有业务行为变更；全部现有页面仍可运行；analyze、完整测试和 Windows build 通过。

Phase 0 交付记录（2026-07-18）：

- 共享 token 已覆盖颜色、材质、圆角、间距、排版、阴影和语义动效；全局主题构建从组合根移到可测试函数。
- `AppAccessibilityData/Scope` 已接入 `disableAnimations`、`accessibleNavigation`、`highContrast` 与系统文字缩放。
- `AppInteractionSurface` 保留 `InkWell`、键盘、焦点和 Semantics；透明材质需要显式请求，高对比度自动回退实色。
- focused tests、完整 189 项测试、analyze 与 Windows debug build 通过；11,163 条真实媒体库完成最大化主界面、设置页和返回路径截图。
- 未修改页面信息架构、过滤语义、filtered queue、播放器/缓存后端、稳定身份或用户数据。Phase 1 应复用本基线，不另建平行 token。

### Phase 1：媒体库发现页

目标：让首页成为全应用 Apple 式基准，同时保护大库性能。

范围：

- 左侧导航、顶部搜索/筛选状态、右侧标签发现、视频卡片和结果视图统一层级。
- expanded 标签面板评估保持打开，medium/compact 使用 sheet 的明确完成路径。
- 卡片 hover、press、更多菜单和动态预览统一反馈。
- 保持网格列数、卡片身份、滚动位置和缩略图 Future 稳定。

验收路径：搜索、一级/二级标签、分组 OR/AND、排除、排序、网格/列表、多选、打开播放器、返回后保持筛选。

Phase 1 首批交付记录（2026-07-18）：

- 保留页面唯一真实 `TextField`、`TextEditingController`、`FocusNode` 和统一 `onChanged` 链路；视觉状态不介入过滤计算。
- 搜索表面复用 Phase 0 的圆角、间距、排版和语义动效 token，以真实 hover/focus 反馈取代只依赖关键词的边框状态；reduced motion 与 high contrast 有确定性降级。
- 筛选状态使用低对比度实色表面，空状态明确显示“全部视频”；活动 chip 维持中性，结果数量改为强调点加主要文字，避免整段紫色争夺注意力。
- 关键词清除和清空筛选复用 40px `AppInteractionSurface`，保留 tooltip、键盘焦点、按压和 Semantics；状态变化提供 live-region 描述。
- 4 项 focused tests 覆盖焦点、命中区、筛选语义、150% 文字缩放、reduced motion 和 high contrast；完整 193 项测试、analyze 与 Windows debug build 通过。
- 真实 1249×714、11,163 条媒体窗口确认搜索焦点、结果状态和列表首屏无位置、遮挡、对齐或溢出问题。继续输入时检测到用户操作目标窗口，自动 QA 已停止；下一空闲窗口补“输入 → 清除 → 标签选择 → 清空”连续截图。
- 未改变 `FilterQuery` / `TagQueryService`、filtered queue、结果排序、缩略图 Future、滚动状态或用户数据。

### Phase 2：播放器

目标：视频为视觉中心，控制层在需要时清晰出现，队列保持来源上下文。

范围：

- 顶栏、视频表面、底部控制条、进度、音量、全屏 chrome、右侧队列和详情统一材质与时序。
- 队列滑动操作使用连续跟手、速度和边界阻力；不改变队列数据。
- 控制显示/隐藏遵守 reduced motion、输入焦点和原生文件对话框门禁。
- 播放期间所有视觉效果接受 GPU、解码和 I/O 共同压测。

验收路径：播放/暂停、seek、音量、队列切换、队列搜索、详情、全屏、Esc、返回媒体库。

### Phase 3：标签与数据维护页面

目标：复杂维护任务保持轻、稳、可预期。

页面：

```text
Tag Manager
设置首页与二级页
缩略图缓存与诊断
Missing / Relink
目录管理
备份检查与导出
标签编辑器
```

统一列表选择、分组标题、统计卡片、输入、空状态、加载、错误、确认和撤销。危险动作继续明确影响范围，不用动画弱化风险。

### Phase 4：全局细节组件

目标：消除页面之间的小型不一致。

范围：Dialog、BottomSheet、PopupMenu、Tooltip、Snackbar、Dropdown、Segmented control、Chip、IconButton、进度、错误与成功反馈。

菜单和 popover 从触发点方向出现；Dialog 保持中心。进入与退出路径对称，退出稍快。无意义的 shimmer、pulse、bounce 和长 stagger 一律不引入。

### Phase 5：响应式与跨平台 polish

目标：在 expanded、medium、compact 和 Windows/macOS/Linux 上保持同一设计语言。

- expanded 保留高信息密度和常驻上下文。
- medium 使用可折叠侧栏和非模态 side sheet。
- compact 使用 drawer/bottom sheet 和紧凑列表。
- macOS 适配 Command 与平台导航习惯；Linux 保留实色材质降级。

## 每阶段验证门槛

```powershell
dart format <本阶段文件>
flutter test <focused tests>
flutter test
flutter analyze
flutter build windows --debug
flutter run -d windows
```

真实点击和截图必须覆盖本阶段主要入口，并检查：

```text
位置 / 遮挡 / 对齐 / 溢出
颜色与文字对比
hover / press / focus / selected / disabled / error
100% / 125% / 150% 文字缩放
reduced motion / high contrast
动画快速反向与连续点击
11,000 条媒体库滚动、筛选和排序帧耗时
播放器解码、队列滚动和全屏资源状态
```

## 提交策略

一次提交只交付一个阶段内的一个可验证组件族或页面。不得以“全局 Apple 化”为由机械格式化、批量替换颜色、重写导航或混入业务重构。每个提交都记录 Before/After 截图、验证结果、未覆盖路径和下一步。

设计执行与审查统一使用 `.agents/skills/ltp-apple-ui-design`。
