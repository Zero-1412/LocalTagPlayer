# Local Tag Player Apple 式全应用 UI 迁移蓝图

## 2026-07-18 Phase 1 排序控件几何补充

- expanded 当前排序入口从弹性拉伸收敛为 168px，六项菜单共享同宽、同左边缘和按钮下方 6px 展开关系，避免控件与弹层形成两个互不相关的视觉尺度。
- 方向入口保留 48px 命中区，动作带只以 380px 稳定普通/多选模式并在动作分组之间分配少量余量；没有引入列表动画、排序重算或过滤刷新。
- 入口/菜单几何、expanded 分层和 150% 文字缩放 focused tests、完整 211 项测试、静态分析与 Windows debug build 通过；真实触控板中段隐藏、回顶和 Phase 3 连续截图待空闲窗口补验。

## 2026-07-18 Phase 1 顶部边界与 Phase 3 剩余组件族补充

- expanded 媒体库只在结果绝对顶部显示顶部信息区；离开后持续收起，只有回到 offset 0 并稳定 140ms 才恢复。动效预算仍为收起 160ms、恢复 220ms，且可从当前进度反向。
- 越过首次结果视口后显示 44px 深色 `chevron.up` 回顶入口；紫色只表达可交互焦点，移除白色带竖杆箭头和亮环，保留 tooltip、键盘、Semantics、220–520ms 距离型回顶与 reduced motion 终态。
- 视频数据备份页完成保护范围、响应式同步状态和维护动作分层；标签编辑器完成维护页深色材质、标题上下文、搜索清除、当前/候选标签分区和 150% 布局，Phase 3 蓝图所列页面均已有代码覆盖。
- 实现只观察顶部边界和首屏阈值，不按像素重建页面；备份、导出、标签来源、筛选、排序、增量结果、缩略图队列和 filtered queue 行为不变。
- focused tests、完整 210 项测试、`flutter analyze` 与 Windows debug build 通过；“日期”六项菜单已完成实窗截图。滚动、真实触控板惯性、备份页和标签编辑器终态因检测到用户输入留待下次空闲窗口补验。

状态：Phase 0、Phase 1 已完成；Phase 2 播放器及左滑快速反向真实终态已验收；Phase 3 蓝图页面均已完成代码、测试与构建，备份检查/导出和标签编辑器仍待空闲窗口补齐真实截图。

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
- 最新 1249×714、11,163 条媒体窗口已补齐“输入 `chamosan` → 20 条结果 → 清除 → 标签父子选择 → 清空”的连续截图；搜索链路、结果状态、chip 和列表首屏同步，无位置、遮挡、对齐或溢出问题。
- 未改变 `FilterQuery` / `TagQueryService`、filtered queue、结果排序、缩略图 Future、滚动状态或用户数据。

Phase 1 主工作区交付记录（2026-07-18）：

- 左导航、顶部工具栏、右侧标签发现与视频卡片统一实色层级，删除旧式强描边、双重投影和分散控件外观；所有现有动作和 Semantics 保留。
- 卡片使用 `AppRadius.card` 完整内容表面和短 hover/focus/press 反馈；侧栏与卡片动效遵守 reduced motion，未增加列表 stagger、blur 或后台媒体读取。
- 网格保留稳定列数、增量加载、卡片 identity、滚动控制器与缩略图 Future；125%/150% 只增加标题行高，150% 长标题实体测试无 RenderFlex 溢出。
- 真实窗口继续完成“打开视频 → 返回媒体库”，窗口与进程保持，来源队列和 11,163 条结果恢复；125%/150% 结果状态按文字倍率扩展后完整显示五位数数量，卡片标题、工具栏和侧栏无裁切、重叠或溢出。
- 完整 198 项测试、analyze 和 Windows debug build 通过，3 项显式 benchmark 跳过。
- 未改变 `FilterQuery` / `TagQueryService`、filtered queue、播放器/缓存后端、稳定身份或用户数据。

### Phase 2：播放器

目标：视频为视觉中心，控制层在需要时清晰出现，队列保持来源上下文。

范围：

- 顶栏、视频表面、底部控制条、进度、音量、全屏 chrome、右侧队列和详情统一材质与时序。
- 队列滑动操作使用连续跟手、速度和边界阻力；不改变队列数据。
- 控制显示/隐藏遵守 reduced motion、输入焦点和原生文件对话框门禁。
- 播放期间所有视觉效果接受 GPU、解码和 I/O 共同压测。

验收路径：播放/暂停、seek、音量、队列切换、队列搜索、详情、全屏、Esc、返回媒体库。

Phase 2 交付记录（2026-07-18）：

- 播放器新增共享画布、结构/抬升表面、描边、文字、状态与阴影 token，并由 `playerWorkspaceTheme` 统一路由内主题；未引入全窗口 blur 或新依赖。
- 顶栏以当前文件名为主信息，以 filtered queue 序号和筛选摘要为次信息；视频结构表面、底部浮动控制、全屏 chrome 与 360–460px 右侧列表/详情使用同一材质和圆角层级。
- 队列搜索、二级标签、卡片选择/播放、左滑收藏/删除、离屏定位、详情标签维护、设置三级列表、错误恢复、截图、诊断与返回路径全部保留。
- 侧栏选中态和主进度条移除渐变发光与装饰猫耳，紫色只表达当前选择、焦点和有效进度；设置过渡遵守 reduced motion，高对比度由播放器局部主题强化实色描边。
- 播放器 30 项 focused tests、完整 193 项测试、analyze 与 Windows debug build 通过；50,000 条队列搜索基准约 25–34ms，未触发全列表重建或新媒体读取。
- Windows 自动化两次无法激活已启动的唯一 Debug 窗口，均返回 `failed to activate captured window`。真实点击、截图、全屏资源状态和 100%/125%/150% 文字缩放仍需按 `CURRENT_TASK.md` 路径补验后，才能把 Phase 2 标记为完整验收。
- `FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存队列、稳定身份与用户数据未改变。

Phase 2 空间与动效精修（2026-07-18）：

- 顶栏使用对称安全区保持文件名真正居中；底部 chrome 以左侧音量语境、中央传输控制和右侧工具动作建立稳定主次，所有既有入口继续直接可达。
- 全屏队列改为根 Stack 内固定覆盖层，以短距离右侧滑入和淡入替代视频区域宽度动画，避免播放纹理逐帧重排；没有引入大面积 blur、弹跳或整列 stagger。
- 列表/详情在 160ms 内完成方向连续切换，旧队列随后卸载；队列左滑保持 1:1 跟手，并按剩余距离 ease-out 吸附，支持快速反向中断。
- 播放器 chrome 复用无描边交互表面，普通态保持克制，focus/high contrast 强制轮廓；reduced motion 取消位移与缩放，只保留 80ms 淡入。
- focused widget 126 项、完整 194 项测试、analyze 与 Windows debug build 通过，3 项显式 benchmark 跳过；50,000 条队列搜索约 29ms。
- 最新 Debug EXE 已启动并唯一定位，但窗口激活时检测到用户输入，自动化已停止抢占；Phase 2 的真实点击、截图和 100%/125%/150% 文字缩放仍待空闲窗口补验。
- 空闲窗口已补验 1248×714 播放/暂停、seek、列表/详情，以及 2560×1440 全屏覆盖队列、自动收起和 Esc；视频未随覆盖队列缩宽，各态无明显位置、遮挡、对齐、溢出或对比度问题。自动化拖拽失败后由人工完成左滑、回拖和快速反向，定时截图确认展开终态稳定；单键 `F` 仍由 UI 全屏路径代验。
- 受控 `flutter run` 复验确认左上返回正常恢复 11,163 条媒体库和原筛选状态，上一轮进程消失属于调试会话/窗口句柄丢失。Debug 专用三档文字缩放开关完成 100%/125%/150% 真实截图；125% 控制条溢出已通过“空间不足仅隐藏辅助时间、始终保留中央传输和操作入口”修复，150% 无溢出。
- 未修改 `FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存队列、稳定身份或用户数据。

### Phase 1 主界面信息架构复修（2026-07-18）

- 在保留视频卡片后，把媒体库外壳从“左侧后台菜单 + 单根大工具条 + 右侧竖排恢复条”收敛为资料库导航、页面标题、主搜索操作与横向标签入口。
- 标题、五位数结果和标签入口形成第一层；搜索、排序、多选与视图形成第二层；只有活动筛选存在时才出现第三层状态，减少静止态 chrome。
- 右侧标签面板关闭后宽度归零，恢复入口仍具备 tooltip、Semantics 和稳定 key；展开侧栏不复制筛选或计数逻辑。
- 100%/125%/150% 真实窗口以及完整 202 项测试、analyze、Windows debug build 通过；没有修改过滤、队列、缓存或用户数据边界。

### Phase 1 顶部信息区二次收敛（2026-07-18）

- 根据真实截图反馈移除 expanded 搜索/动作行的外层大圆角容器，避免结构表面继续包裹已有边框控件；中小布局不变。
- 标题排版、结果数和标签入口收敛为轻量上下文层；搜索到排序使用 12px 紧邻关系，排序与多选/视图在稳定动作带内分组。
- 多选切换保持搜索宽度，48px 命中区、真实 `TextField`、筛选与排序回调、filtered queue 均保持。
- 真实 150% focused test、完整 205 项测试、analyze、Windows debug build 与 1248×714 截图通过；没有新增 blur、列表动画、查询或媒体读取。

### Phase 1 排序动作带补齐（2026-07-18）

- 固定动作带仍承担普通/多选模式宽度稳定职责，但不再把剩余宽度暴露为无语义空洞；expanded 当前排序字段弹性铺开并直接显示当前状态。
- 字段、方向、多选和视图切换形成连续操作序列，medium/compact 维持紧凑图标；没有复制排序逻辑或增加列表计算。
- 150% 文字缩放、动作间距与多选切换回归、完整 205 项测试、analyze、Windows debug build 和 1248×714 实窗截图通过；检测到用户输入后停止菜单自动点击。

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

Phase 3 首个组件族交付记录（2026-07-18）：

- 标签中心采用圆角双栏结构，搜索收敛为稳定 `TextField`；详情按使用、属性、批量 manual 和风险操作分组，标签来源与引用边界不变。
- 设置首页采用实色分组面板与共享交互表面，二级设置卡片统一 14px 内容圆角；没有改变设置持久化、确认或返回语义。
- 缓存诊断采用状态摘要、覆盖率、响应式关键指标、后台任务和失败处理分区；加载态保持结构锚点，`CacheStats`、队列门禁和动作回调不变。
- focused tests、完整 202 项测试、analyze 与 Windows debug build 通过，3 项显式 benchmark 跳过。
- 真实 1248×714 窗口已补齐标签搜索/清除/详情、设置四入口/四个二级页/返回，以及缓存加载/终态/返回截图；各静止态无明显遮挡、错位或横向溢出。

Phase 3 目录与重关联组件族交付记录（2026-07-18）：

- 目录管理升级为页面级维护工作区，按状态摘要、目录集合和 root 卡片建立层级；添加、扫描与 detached 解除管理继续复用原业务回调。
- Missing/Relink 采用状态摘要、稳定身份说明和响应式待处理列表；批量路径替换按映射、摘要、搜索、预览状态和动作分区，原只读预览与二次确认边界不变。
- 深色维护主题统一 Dialog、FilledButton、OutlinedButton 与 TextButton；确认层不再退回全局浅色主题，危险动作仍保留独立红色语义。
- 150% 文字缩放 focused tests、完整 204 项测试、analyze、Windows debug build 与 1248×714 真实窗口连续截图通过；未增加列表重算、文件读取、blur 或装饰动画。
- SQLite schema、过滤语义、filtered queue、缓存队列、relink 服务、稳定身份和用户数据未改变。

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
