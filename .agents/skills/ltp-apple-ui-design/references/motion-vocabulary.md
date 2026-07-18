# Local Tag Player 动效术语

用于把“更丝滑”“弹一下”“像苹果”等模糊要求转换为可实现、可验收的术语。

## 出现与消失

- **Fade in / Fade out**：只改变透明度。
- **Slide in**：从明确方向进入。
- **Scale in**：从略小尺寸加淡入到完整尺寸，不能从 0 开始。
- **Pop in**：进入时有轻微 overshoot；只用于低频、允许愉悦感的场景。
- **Reveal**：通过裁剪或遮罩逐步露出内容。
- **Enter / Exit**：组件加入或离开界面的完整过渡。

## 状态连续性

- **Crossfade**：两个状态在同一位置交叉淡变。
- **Continuity transition**：保持对象身份，让前后状态看起来属于同一元素。
- **Shared element transition**：同一元素在两个页面或位置间移动并改变尺寸。
- **Layout animation**：尺寸或位置改变时平滑到新几何，而不是跳变。
- **Accordion / Collapse**：区域展开或收起。
- **Direction-aware transition**：前进与返回使用相反方向，帮助理解导航关系。
- **Origin-aware animation**：菜单或 popover 从触发控件所在方向出现。

## 输入反馈

- **Hover effect**：细指针悬停反馈；触摸布局不应误触发。
- **Press / Tap feedback**：pointer-down 时立即轻微缩小或改变颜色。
- **Hold to confirm**：按住期间显示进度，完成后提交危险动作。
- **Drag**：元素 1:1 跟随指针，释放时继承速度。
- **Swipe to dismiss**：滑动移出并关闭。
- **Rubber-banding**：越过边界后阻力逐渐增加，再回弹。
- **Ripple**：从点击位置扩散的 Material 水波；使用时需确认是否符合目标 Apple 式克制感。

## 速度与物理

- **Easing**：动画速度随时间的变化。
- **Ease-out**：快启动、慢结束，适合系统响应用户。
- **Ease-in-out**：慢—快—慢，适合屏幕上已有元素从 A 移到 B。
- **Linear**：恒速，只用于进度、旋转等持续运动。
- **Spring**：由质量、刚度和阻尼决定的物理运动。
- **Damping**：弹簧多快停止振荡。
- **Velocity**：运动速度和方向。
- **Momentum**：释放后继续携带的速度。
- **Interruptible animation**：可在中途从当前画面和速度反向或重新定向。

## 精修与性能

- **Stagger**：多个小元素短间隔依次进入；大媒体列表禁止使用。
- **Orchestration**：让多个属性和组件像一个动作一样同步。
- **Blur**：模糊；可遮盖小型 crossfade 接缝，但大面积使用昂贵。
- **Skeleton / Shimmer**：加载占位；高频大列表优先静态骨架或局部进度。
- **Tabular numbers**：固定数字宽度，避免时间和计数变化时抖动。
- **Jank**：掉帧导致的可见卡顿。
- **Dropped frame**：错过绘制时限的帧。
- **Compositing**：在独立绘制层完成位移或透明度变化。
- **Layout thrashing**：动画反复触发布局、测量和重建。
- **Reduced motion**：降低位移、弹跳和视差，同时保留必要反馈。

## 描述模板

把模糊要求改写成：

```text
<组件> 使用 <术语>，目的为 <反馈/空间连续/状态说明>；
时长 <精确值>，曲线 <精确 token>，锚点 <位置>；
允许/禁止快速反向；reduced motion 下改为 <降级行为>；
不得触发 <业务或性能边界>。
```

本术语表选取并改编自 `emilkowalski/skills` 的 `animation-vocabulary`。
