# Chat 6：标签管理与批量打标

## 所有权

- create/rename/merge/delete tag 的已验证业务入口；
- aliases、hidden/favorite/sort order；
- 当前过滤结果的批量 manual tag 增删。

## 必须保持

- 优先使用 `tagId`；
- manual/folder 来源不混淆；
- 用户主动添加的 manual 标签使用独立顶层关系，不沿用 folder 父子层级；
- 单视频编辑器的 folder 锁定项与 manual 编辑集合必须分开传递；同名时按 `tagId + source` 保留两条关系，不能用名称或目录层级推断 manual 是否存在；
- 批量移除 manual 不删除 folder 关系；
- locked 标签不被自动流程静默删除；
- merge/delete 只有 migration、回滚和用户数据验证完整时才开放；
- 批量目标固定为用户确认的结果快照。

## 非目标

不拥有筛选实现、PlayerBackend、缓存后端或媒体物理移动。

历史：`docs/history/chat/CHAT_6_TAG_MANAGER_THROUGH_2026-07-30.md`。
