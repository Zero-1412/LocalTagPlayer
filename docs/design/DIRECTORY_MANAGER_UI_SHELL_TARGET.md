# 目录管理 UI 外壳 Before / After 目标

## 范围

本轮只调整目录管理页面的维护工作区外壳、标题栏动作密度和目录列表内容边界：

- “维护工作区 / 目录管理”上下文标题；
- 添加目录、重新扫描的 expanded/compact 动作形态；
- 目录状态摘要与 root 列表的稳定桌面宽度；
- 现有深色维护主题、确认弹窗和数据保留说明的连续性。

页面继续只编排注入的 `onAddDirectory`、`onRescan`、`onRemoveRoot` 回调，不直接访问
磁盘、SQLite 或扫描后端。

## Before

- 使用单层原始 `AppBar`，添加目录和重新扫描按钮以两枚独立按钮堆叠在右侧；
- 窄窗口没有统一的图标动作降级，标题栏容易被双动作挤压；
- 内容区直接铺满页面，目录摘要和 root 列表缺少与其它维护页一致的桌面内容边界；
- 返回入口与 Missing/Relink、设置页的维护上下文语义不一致。

## After

- 标题栏统一显示“维护工作区 / 目录管理”，保留返回和两个既有动作 key；
- expanded 保留“添加目录 / 重新扫描”文字动作，compact 使用两个带 tooltip 的图标动作，重新扫描
  作为主要动作保持更高对比度；
- 内容居中限制在维护工作区宽度内，先展示目录数量与扫描状态，再展示 root 列表；
- 空态、150% 文字缩放、解除管理确认、稳定身份数据保留说明和 busy 状态继续可达。

## 明确不改

- root、detached、扫描和解除管理业务语义；
- `LibraryApplicationFacade`、Repository、FileSystemAdapter 和扫描协调器；
- schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend；
- 标签、收藏、播放记录、进度、稳定视频身份和其它用户数据。

## 验收重点

- 1248×714 与 150% 文字缩放下双动作、目录摘要、root 路径和解除管理按钮不裁切；
- 添加、重新扫描、解除管理和返回媒体库入口保持原 key、回调和确认路径；
- 不新增目录读取、扫描重算、列表查询、blur 或持续动画。
