# 标签中心 UI 外壳重构目标

## 任务范围

本轮只重构 Tag Manager 的视觉外壳与信息层级，不改变标签管理的业务所有权。页面仍由
`TagManagerPage` 持有搜索、选中标签、编辑字段和用量刷新状态；创建、保存、批量
manual 打标、风险检查、返回路径和持久化回调保持原样。

## Before

- 顶部是通用 `AppBar` 标题，页面身份与“维护工作区”的上下文不够明确。
- 左侧只有搜索、标签组 chip 和默认 `ListTile` 列表，标签发现栏缺少稳定的标题、范围计数
  和选中定位。
- 右侧详情直接从标签名称进入表单，标签来源、分组和使用规模需要滚动后才逐渐建立上下文。
- 空详情、选中详情和风险操作都使用相近的边界强度，维护动作的重要性不够分层。

## After

- 顶部使用“维护工作区 / 标签中心”两级标题，刷新与新建保持原位置和原回调，底部增加
  轻量工作区边界。
- 左侧成为标签发现 rail：显示当前可见条目数、搜索入口、分组过滤和带来源/使用量语义的
  紧凑列表；selected 使用低面积色洗加定位线表达，不扩大紫色覆盖面。
- 右侧成为标签 inspector：先展示标签身份、来源、分组、使用量和 stable ID，再进入属性、
  批量打标签和高风险检查分区。
- 空状态与选中状态共享相同的 panel 边界；高风险操作使用独立的低对比度危险表面和现有
  阻塞说明，继续避免把“检查影响”误解为执行删除/合并。
- 桌面保持左右工作区，紧凑窗口改为上下堆叠；文字缩放时仍以可滚动、可见焦点和不溢出为
  验收标准。

## 明确不变

- `TagItem`、`TagGroup`、SQLite/schema、manual/folder 来源边界和用户数据不变。
- 页面不实现合并、删除或任何新的标签迁移语义；现有引用检查和只读阻塞弹窗不变。
- `FilterQuery`、`TagQueryService`、媒体库当前筛选、来源 `filtered queue`、播放器、缩略图
  与媒体详情队列不变。
- 所有既有 `ValueKey`、输入 controller、focus order、route、返回快捷键和 callback 保持可达。

## 本轮增量：共享工作区表面与挂载证据

本轮在既有标签发现 rail / inspector 视觉目标上继续收敛外壳，不改变上述信息架构：

| Before | After | 目的 |
| --- | --- | --- |
| 页面主体依靠匿名 `DecoratedBox` 区分左侧列表和右侧详情 | 页面拥有“标签中心工作区”语义容器，左右分别是“标签导航工作区”和“标签 inspector 工作区” | 让用户立即理解当前在浏览标签集合，还是在维护一个标签 |
| 结构表面只有颜色/描边，页面级 identity 不明显 | 使用实色 `Material`、弱描边、统一圆角和稳定 surface key | 形成与设置、诊断页一致的 Calm Desktop Media Workspace 层级，并便于截图/可达性检查 |
| 空详情和已选详情共享视觉边界，但外壳契约不显式 | 空详情与已选详情共用 inspector surface；搜索、分组、编辑字段和动作 key 全部保留 | 避免“筛选 A、编辑 B”的错觉，不改变选中、清空和返回语义 |
| 外壳调整容易把标签维护动作误认为普通列表点击 | 外壳只负责分区、语义和裁切；保存、批量 manual、影响检查仍由原页面回调执行 | 保持来源边界、引用检查和用户数据安全路径 |

### 本轮保护清单

- `_filteredTagRows` 仍只在 Tag Manager 内进行展示层搜索/分组筛选，不改变 `FilterQuery`、
  `TagQueryService` 或媒体库当前筛选。
- 搜索继续使用唯一的 `TextField`、`TextEditingController` 和清除入口；分组选择仍只影响左侧列表。
- `TagManagerDetail` 的显示名称、别名、分组、排序、收藏、隐藏、保存、批量 manual 增删、
  合并/删除影响检查和焦点顺序全部保留。
- folder 标签不可作为普通 manual 批量对象；删除/合并仍只检查引用并显示只读影响说明。
- 不修改 `LibraryApplicationFacade`、标签模型、SQLite schema、播放器/缩略图队列、filtered playback queue、
  stable identity 或用户数据。

### 本轮验证目标

- 页面级可达性能够找到 `tagManager.page`、`tagManager.workspace`、导航 surface 和 inspector surface。
- 默认与 150% 文字缩放下，搜索、空详情、左右工作区和返回入口均无溢出或裁切。
- 既有搜索、分组、详情焦点、危险操作只读反馈 focused 测试继续通过。
- 真实 Debug 窗口从媒体库进入标签中心，检查导航/inspector、空详情、选中标签和返回媒体库路径。
