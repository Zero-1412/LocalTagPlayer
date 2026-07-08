# CHAT_6_TAG_MANAGER.md

当前版本：`0.2.2`
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
