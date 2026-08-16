# Missing / Relink UI 外壳 Before / After 目标

## 范围

本轮只调整缺失与重新关联页面的维护工作区外壳和信息表面：

- 返回与页面级批量路径替换入口的上下文层级；
- 缺失状态摘要与待处理列表的桌面内容宽度；
- 结构 surface、交互 surface、窄窗口动作降级和维护主题连续性。

单条 relink、批量路径替换、文件选择器、fingerprint 校验、stable `videoId`、
`LibraryApplicationFacade` 提交和返回结果继续由现有页面/服务拥有。

## Before

- 使用单层原始 `AppBar`，标题没有“维护工作区”上下文；
- 批量路径替换按钮直接放在标题栏右侧，窄窗口下缺少图标降级；
- 内容直接铺满页面，摘要与待处理列表虽有深色 surface，但没有统一内容边界；
- 返回入口没有稳定页面级 key，和设置、标签中心的维护导航语义不一致。

## After

- 标题栏统一显示“维护工作区 / 缺失与重新关联”，保留返回和批量路径替换 key；
- expanded 使用文字动作，compact 使用带 tooltip 的图标动作，避免标题栏挤压；
- 内容居中限制在桌面维护宽度内，摘要先说明缺失状态与数据保留策略，再进入列表；
- 保持现有空态、单条关联、批量预览、错误反馈、150% 文字缩放和键盘命中路径。

## 明确不改

- `videoId`、fingerprint、mutable path 与 missing 语义；
- 单条 `RelinkMissingVideoCommand` 与批量路径替换 service；
- 标签、收藏、播放记录、进度和其它用户数据；
- schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend；
- 文件选择器、Repository 提交、错误确认和返回媒体库的业务时序。

## 验收重点

- 1248×714 与 150% 文字缩放下标题、批量入口、摘要、列表和单条按钮不裁切；
- 空态与有 missing 项状态共享稳定布局；
- 返回、批量预览、单条重新关联仍可达，失败时不改变稳定身份；
- 不引入 blur、列表重算、文件读取或持续动画。
