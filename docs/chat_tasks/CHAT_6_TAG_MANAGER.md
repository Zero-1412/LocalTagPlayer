# CHAT_6_TAG_MANAGER.md

## 2026-07-17 标签中心分组反馈

- 标签中心分组摘要增加“全部”和带勾选强调的 ChoiceChip；点击后只筛选当前展示列表，选中详情不属于新分组时清除详情。
- 展示筛选不写入媒体库 `FilterQuery`，不改变标签来源、usage 统计、批量打标或 filtered queue；维护页面统一使用媒体库深色 token。

## 2026-07-17 标签编辑候选完整性与入口统一

- 公共标签编辑器的候选改从规范化 `TagItem` 索引读取，而不是只汇总已出现在视频兼容字段中的名称；当前层级未隐藏标签全部可选，包括尚未关联视频的记录。
- 候选仍按一级/二级父级隔离；folder 等来源只提供可复用名称，选中后保存为独立 manual 关系，当前视频由路径派生的 folder 标签继续锁定。
- “全部 manual 标签”更名为“全部可用标签”，并移除前 24 项截断；滚动区域展示完整集合。
- focused tests 覆盖来源/父级/隐藏边界、未使用标签及 30 项完整渲染；完整 164 项测试、静态分析与 Windows debug build 通过。
- 中间构建真实窗口确认“原神”旧候选只有 24 项；最新构建因用户正在目标窗口全屏播放而未继续自动点击，保留卡片与播放器两入口人工对比路径。

## 2026-07-11 播放器 manual 标签快速选择

- 快速编辑器增加最近使用、收藏标签和即时搜索分区；输入仍可创建新的 manual 标签。
- folder 标签继续以锁定 chip 展示，只能由目录结构维护；rule/filename/import/auto 不会被提升为 manual。
- 保存仍优先使用真实关联 tagId，只更新当前视频和 `video_tags` 必要关系，不触发全库标签计数重算。

## 2026-07-10 播放器内快速编辑 manual 标签

- 播放器提供当前视频的快速 manual 标签编辑入口，复用现有标签维护能力，不在播放器复制标签数据规则。
- folder 来源标签以锁定 chip 展示并给出维护提示，只能由目录结构变更；manual 标签可以新增或移除。
- 保存时优先使用当前视频真实关联的 `tagId`，同名复用遵守 manual 来源边界，同时保留其它来源标签和兼容字段。
- 隔离 profile 真实窗口验证新增标签立即显示、队列不变且重启后持久化；本轮不修改 schema。

当前版本：`0.2.3`
状态：第一阶段完成
负责人：Chat 6 / 标签管理器 + 批量打标

## 规划来源

主要来源：

```text
<private-planning-document>
```

如果本文档与该文件冲突，以外部规划为准。

## 范围

在分组标签模型和筛选引擎可用后，负责长期标签维护 UI 和批量标签操作。

允许：

- 标签管理页面。
- 标签组管理 UI。
- 标签详情编辑器。
- 标签别名。
- 标签重命名 / 合并 / 删除。
- favorite / hidden / sort 控件。
- 给当前筛选结果批量打标签。
- 批量移除标签。
- 与 Chat 2/3 协调后的保存筛选 / 智能列表管理。

禁止：

- 播放器 backend 改动。
- 缩略图队列内部逻辑。
- 未经过 Architecture 协调的平台专属文件操作。
- 没有兼容性和文档记录的破坏性标签 / schema migration。

## P1 任务

- 增加标签管理页面。
- 搜索标签。
- 创建标签。
- 重命名标签。
- 合并重复标签。
- 维护别名。
- 维护标签组。
- hidden / favorite / sort 标签。
- 给当前筛选结果批量添加标签。
- 从选中或筛选视频中批量移除标签。
- 保持批量操作平台无关。

## 新对话提示

```text
这是 Chat 6 / 标签管理器 + 批量打标。项目路径：<project-root>。
请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_6_TAG_MANAGER.md

职责：标签管理页、标签组、标签别名、重命名、合并、隐藏 / 收藏 / 排序、批量打标签和批量移除标签。不要改播放器内核、缩略图队列或平台文件操作。
当前目标：在 Tag Model + Filter Engine 稳定后，提供长期维护大量标签的入口。用户应能维护别名、合并重复标签，并能给当前筛选结果批量打标签。
修改代码后运行：
- flutter analyze
- flutter build windows --debug

涉及 schema、src/core 或共享模型时，更新 ARCHITECTURE.md、ROADMAP.md 和本文档版本记录。
```

## 变更记录

- `0.2.2`：历史阶段中，媒体库侧栏“我的标签库”曾支持创建或复用标签作为快捷入口；移除快捷入口不删除真实标签记录或视频关系，破坏性标签维护仍归 Tag Manager。该侧栏入口后续已被“本地媒体库”路径浏览方向替换。
- `0.2.1`：验收修复：Tag Manager 直接展示标签组；批量添加 / 移除限制为 `manual` 来源标签；创建 manual 标签时拒绝覆盖同组非 manual 标签。
- `0.2.0`：新增第一阶段 Tag Manager 入口和页面；支持查看 groups / tags / aliases / source 使用数量、搜索标签、创建 manual 标签、编辑 displayName / aliases / hidden / favorite / sortOrder / group，并对当前筛选结果批量添加 / 移除 manual 标签。删除 / 合并仍是带 `video_tags` 引用检查的保护性占位；folder 派生标签不硬删除。
- `0.1.0`：从 `local_tag_player_flutter_cross_platform_plan_v2.md` 创建任务。
