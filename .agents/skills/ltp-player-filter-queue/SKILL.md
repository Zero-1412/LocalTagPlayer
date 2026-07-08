---
name: ltp-player-filter-queue
description: Local Tag Player 播放器过滤队列技能。用于 PlayerPage、PlaybackSession、filtered playback queue、右侧队列、当前 index、PlayerBackend 或播放诊断稳定性。
---

# Local Tag Player 播放器过滤队列

用于播放器页面、过滤播放队列、右侧队列、当前序号和播放诊断稳定性。

## 上下文

通常是 Level 2；如果修改 `PlayerBackend` 或平台边界，升级为 Level 3。

读取：

```text
AGENTS.md
PROJECT.md
CURRENT_TASK.md
docs/chat_tasks/CHAT_4_PLAYER.md
PlayerPage / PlaybackSession 相关源码
```

## 产品规则

播放器消费当前筛选队列，不能回退到全局媒体库列表。

必须保护：

- 当前队列来自媒体库当前可见筛选结果。
- 当前 index 类似 `1/1661`。
- 返回媒体库保留筛选状态。
- 右侧二级标签切换保持在来源过滤队列内。
- 不优先做字幕、音轨、逐帧、A-B loop 等高级播放器功能。

## 禁止

- 不改标签 schema。
- 不改缩略图队列。
- 不重写播放器核心。
- 不把高级播放器功能放在标签发现闭环之前。
