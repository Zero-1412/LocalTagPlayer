# Flutter 动效设计与审查

## 目录

1. 是否应该动画
2. 时长与曲线
3. 可中断与手势
4. 性能
5. 审查工作流
6. 验收

## 1. 是否应该动画

每个候选必须通过四道门：

| 门 | 问题 | 不通过时 |
| --- | --- | --- |
| 频率 | 用户一天看到多少次？ | 高频动作删除或极度减弱动画 |
| 目的 | 是否提供反馈、空间连续、状态说明或避免跳变？ | 删除 |
| 速度 | 能否在预算内完成？ | 缩短或删除 |
| 功能 | 是否妨碍阅读、输入、筛选、排序或播放？ | 删除 |

频率决策：

```text
键盘输入、快捷键、列表导航、连续标签选择: 即时或近乎无动画
hover、按钮、常用切换: 轻微反馈
菜单、popover、筛选面板、route: 标准短动画
首次使用、空状态、明确完成: 可以使用少量愉悦动效
```

不要给 11,000 条结果逐项 stagger。只允许在小型、低频、一次性集合中使用 30–60ms 的短 stagger，且动画期间不得阻塞点击。

## 2. 时长与曲线

建议 Flutter token：

| 场景 | 时长 | 曲线 |
| --- | --- | --- |
| pointer-down / press | 90-140ms | 强 ease-out |
| hover / focus / color | 120-180ms | ease / ease-out |
| tooltip / 小 popover | 120-180ms | ease-out |
| dropdown / segmented / toggle | 150-220ms | ease-out 或屏上移动 ease-in-out |
| route / dialog | 180-240ms | 进入 ease-out，退出更短 |
| side sheet / drawer | 240-320ms | 屏上移动 ease-in-out；只有手势驱动才用 spring |

现有左右侧栏 320ms 是经过真实窗口验证的结构动画，可保留；新普通 UI 默认小于 300ms。退出通常比进入短 20%–30%。

Flutter 映射：

```text
进入/退出: Curves.easeOutCubic 或项目更强的统一 ease-out token
屏上 A->B 移动: Curves.easeInOutCubic
连续进度/旋转: linear
手势释放: SpringSimulation，默认临界阻尼、无弹跳
动量拖拽: 只在真实速度输入存在时允许轻微欠阻尼
```

禁止从 `scale: 0` 出现。浮层常用 `0.95-0.98 -> 1` 加 opacity；Dialog 保持中心锚点，popover 从触发点方向出现。

## 3. 可中断与手势

- 快速重复触发时从当前 presentation value 重新定向，不从逻辑起点重播。
- `AnimationController.animateTo` 按剩余距离缩短时长；真实拖拽释放使用 `animateWith(SpringSimulation)` 并传递速度。
- 拖动阶段内容 1:1 跟随指针，保留抓取偏移，不在 release 后才播放完整动画。
- 约 8–10px 移动阈值后再确认拖拽方向，避免点击与拖拽竞争。
- 边界使用逐渐增强的阻力，不做突然硬停。
- 进入与退出沿同一路径；右侧面板回到右侧，底部 sheet 回到底部。
- 动画期间不得禁用可安全反向的输入。

普通点击侧栏不是手势，不需要为了“Apple 风格”强行上 spring 或 bounce。

## 4. 性能

Flutter 中 `Transform` 和 `Opacity` 也不是自动免费的。审查以下风险：

- 动画是否触发 `LayoutBuilder` 下的大列表逐帧重排。
- width/height 动画是否导致视频网格换列、卡片身份变化或缩略图 Future 失效。
- `Opacity` 是否创建大面积离屏缓冲。
- `BackdropFilter`、动态 blur、复杂阴影是否覆盖整个窗口或滚动列表。
- 动画 build 是否调用筛选、排序、统计、文件 I/O 或数据库查询。
- 是否缺少稳定 key、缓存和 `RepaintBoundary`。
- 播放期间是否与解码、FFmpeg、缩略图和媒体详情争用 GPU/I/O。

标签点击、排序和搜索必须优先更新可见结果；动画、计数和装饰不能进入关键输入路径。

## 5. 审查工作流

### Recon

用精确搜索定位：

```text
Animated*
AnimationController
Tween
Curves
SpringSimulation
Transform
Opacity / FadeTransition
BackdropFilter / ImageFilter
MouseRegion / GestureDetector / Listener
onTapDown / onHover / onPan*
```

记录现有 token、页面频率、业务状态和性能约束，不重新争论已有文档明确批准的取舍。

### 八类检查

1. 目的与频率。
2. 曲线与时长。
3. 物理感与锚点。
4. 可中断性。
5. layout、paint、GPU 与 rebuild 性能。
6. reduced motion、high contrast、键盘与语义。
7. token 和全应用一致性。
8. 少量真正缺失的动效机会。

### 输出

先给单一表格：

| # | Severity | Category | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- | --- |

Severity：

```text
HIGH: 延迟输入、卡顿、错误队列/状态、不可访问或强烈不适
MEDIUM: 明显迟钝、错误来源、不可反向、缺少 reduced motion
LOW: token、间距、轻微排版和有限 polish
```

审查整个应用时最多报告 5–7 个高置信问题。另列 2–5 个主动拒绝的动画候选，并说明是被频率、目的、速度还是功能门槛拒绝。

## 6. 验收

- focused widget test 覆盖起点、中间帧、终点和快速反向。
- 使用 `MediaQueryData(disableAnimations: true)` 和 `highContrast: true` 覆盖降级。
- 真实窗口连续点击、快速横扫、键盘导航和窗口缩放。
- UI 变更截图检查位置、遮挡、对齐、溢出、对比度和状态反馈。
- 大媒体库记录 build/raster/total 帧时间；播放页同时观察解码和队列滚动。
- 不确定“感觉”的动画以 0.25x 慢速或逐帧截图检查，不凭代码猜测。

本参考改编自 `emilkowalski/skills` 的 `review-animations`、`improve-animations`、`find-animation-opportunities` 和 `emil-design-eng`，已替换 Web/CSS 专属规则。
