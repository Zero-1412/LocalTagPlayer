# NEW_CHAT_BOOTSTRAP.md

Local Tag Player 是一个 Flutter Windows 本地标签视频播放器。

项目定位：

```text
Tag-driven local video discovery player
not a general professional video player
```

新对话不要依赖历史聊天记录，请以项目文件为准。

开始任何代码任务前，先判断任务等级，并按最小安全上下文读取文件。不要每个小任务都读取完整项目历史。

```text
Level 1: Small Fix
- 用于 analyzer/build 报错、单文件编译错误、缺失符号、小 UI 溢出、拼写修复。
- 只读 AGENTS.md、具体报错、直接相关源码文件；必要时只查直接引用。
- 不读完整 ROADMAP / CHANGELOG / 全部 CHAT 文档 / 完整未来规划。

Level 2: Bounded Feature / UI Task
- 用于一个页面、组件、服务的小功能或当前 Chat 的有限阶段。
- 读 AGENTS.md、PROJECT.md、CURRENT_TASK.md、一个相关 docs/chat_tasks/CHAT_*.md、直接相关源码。
- 只有涉及 shared contracts / src/core / 平台边界时才读 ARCHITECTURE.md。

Level 3: Architecture / Schema / Boundary Task
- 用于 SQLite schema、src/core、平台接口、FilterQuery、TagQueryService、PlayerBackend、FFmpegBackend、stable identity、missing/relink、ROADMAP/ARCHITECTURE 修改。
- 这类任务才读完整 PROJECT / ARCHITECTURE / CURRENT_TASK / ROADMAP / CHANGELOG / 相关 CHAT 文档 / local_tag_player_flutter_cross_platform_plan_v2.md。
```

核心原则：

```text
1. 从第一性原理出发。
2. 以对抗式审查结束。
3. 不要把项目当普通专业播放器。
4. 不要重做已经完成的 Chat 1-7 第一阶段。
5. 不要重复粘贴完整项目历史，优先读取项目文件。
6. 不要做无关清理、无关格式化或大范围重构。
7. 优先小步、可回滚修改。
8. 以最少的安全 token 完成当前任务；不要为小任务引入完整项目历史、无关文件读取或长输出。
9. 如果任务调查中发现需要改 schema / FilterQuery / TagQueryService / 平台边界 / stable identity / player-cache queue，必须升级为 Level 3。
10. 除代码本身、第三方 API、协议、命令、路径、固定术语和外部错误信息外，文档、代码注释、Git 提交信息、任务记录和交接摘要都以中文为第一语言。
```

`.agents/skills` 是本项目的 repo-scoped Codex skill 目录。需要专门流程时，优先使用最小相关 skill，例如 `$ltp-small-fix`、`$ltp-tag-filter-data`、`$ltp-player-filter-queue`。

当前必须保护的核心闭环：

```text
scan local folders
-> derive initial folder tags
-> add / edit manual tags
-> grouped tag filtering
-> keyword / alias search
-> current filter chips + result count
-> filtered playback queue
-> player consumes current queue
-> tag manager fixes tags
-> cache / diagnostics stay stable
```

禁止随意破坏：

```text
SQLite schema
FilterQuery
TagQueryService
folder / manual / rule / filename / import / auto tag source rules
player filtered queue
FFmpeg / FFprobe backend boundary
thumbnail / media details queue
```

代码修改后至少运行：

```powershell
flutter analyze
flutter build windows --debug
```

已知本机注意事项：

```text
flutter run CLI may timeout even when debug exe can run.
dart format may timeout locally.
Do not claim they succeeded unless they actually completed.
```

任务输出保持简短，通常不超过 80 行，不输出完整 diff 或完整日志：

```text
changed files
key behavior changes
validation result
adversarial review
next step
```

低 token 版第一性原理：

```text
Product goal protected:
Core loop part protected:
Must not change:
Smallest safe change:
Fewest safe tokens:
```

低 token 版对抗式审查：

```text
schema: unchanged / changed with migration notes
FilterQuery / TagQueryService: unchanged / changed intentionally
filtered queue: unchanged / changed intentionally
thumbnail/media queue: unchanged / changed intentionally
user data: preserved / risk noted
prompt impact: satisfies first principles / adds unnecessary scope or context
validation: analyze/build result
```
