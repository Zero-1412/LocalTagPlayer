---
name: ltp-stable-identity-missing-relink
description: Local Tag Player 稳定视频身份技能。用于 videoId、fingerprint/mediaFingerprint、mutable path、missing state、relink、bulk path replacement，或文件移动后保留 tags/favorites/play records。
---

# Local Tag Player 稳定身份、缺失与重新关联

用于 `videoId`、`fingerprint`、可变路径、missing、relink、批量路径替换和文件移动后的用户数据保留。

## 上下文

这是 Level 3。

读取：

```text
AGENTS.md
PROJECT.md
ARCHITECTURE.md
CURRENT_TASK.md
ROADMAP.md
CHANGELOG.md
docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md
稳定身份相关模型、store、repository 源码
```

## 目标模型

```text
videoId = 稳定数据库身份
fingerprint = 文件 / 媒体身份
path = 当前可变位置
missing = 当前路径无效但记录保留
```

## 规则

- tags、favorites、play records、progress 绑定稳定身份，不绑定可变 path。
- 不立即删除 missing videos。
- relink 和 bulk path replacement 必须保留用户维护数据。
- 任何 schema 修改必须向后兼容、幂等并有迁移说明。
