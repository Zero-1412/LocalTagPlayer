# Chat 2：标签数据、媒体库与稳定身份

## 所有权

- SQLite tag/video/relation 模型与 migration；
- `FilterQuery` / `TagQueryService`；
- 扫描、root、stable identity、missing/relink 和批量路径替换；
- favorites、play records、progress 的稳定身份绑定。

## 必须保持

- 同组 OR、跨组 AND、排除 NOT；
- folder 来源可重算，manual/locked 数据保留；
- 一级/二级 folder 标签服从当前 root 父子层级；
- 路径变化不创建第二个用户身份；
- 扫描器只产出候选，Repository 拥有数据库写入。

## 非目标

不拥有播放器 UI、视觉风格、缓存后端或未经验证的物理文件移动。

历史：`docs/history/chat/CHAT_2_MEDIA_LIBRARY_THROUGH_2026-07-30.md`。
