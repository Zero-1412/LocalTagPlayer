---
name: ltp-player-filter-queue
description: Local Tag Player 播放器过滤队列技能。用于 PlayerPage、PlaybackSession、filtered playback queue、右侧队列、当前 index、PlayerBackend 或播放诊断稳定性。
---

# Local Tag Player 播放器过滤队列

用于播放器页面、过滤播放队列、右侧队列、当前序号和播放诊断稳定性。

## 上下文

纯播放器页面视觉通常是 Level 2；来源 filtered queue、队列回退、`PlayerBackend` 或平台边界属于共享播放边界，必须升级为 Level 3。

读取：

```text
AGENTS.md
PROJECT.md
CURRENT_TASK.md
docs/chat_tasks/CHAT_4_PLAYER.md
PlayerPage / PlaybackSession 相关源码
```

## 只读队列诊断预算

只诊断“来源 filtered queue 回退”且不修改文件时，必须在最多 10 次工具调用内完成：

1. `ltp-task-router` 与本 Skill 各读取一次，不得重复读取。
2. 对 Level 3 必读文档使用一次合并的精确 `rg`，只取队列边界附近片段；不要逐个读取完整文档。
3. 源码只追踪“媒体库打开参数 → `PlayerPage` 入参 → playback controller 的 `sourcePlaylist` → 二级标签切换”四段链路。
4. 最多再读取一个直接相关 focused test；证据足以判断边界后立即停止。
5. 同一符号或文档搜索不得重复执行；外部计划缺失时记录一次，不得反复探测。
6. 只读诊断不运行 Flutter 全量测试、构建或真实窗口，也不扫描无关页面。

如果 10 次调用内无法定位，输出已确认边界和下一条精确命令，不得用扩大扫描代替证据。

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
