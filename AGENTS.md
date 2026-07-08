# AGENTS.md

## 0. 项目快照

项目：Local Tag Player

定位：

```text
Tag-driven local video discovery player
not a PotPlayer / VLC replacement
not a general professional video player
```

核心闭环：

```text
scan local folders
-> derive initial folder tags
-> add/edit manual tags
-> distinguish folder/manual/rule/filename/import/auto tag sources
-> grouped tag filtering
-> keyword / alias search
-> current filter chips + result count
-> filtered playback queue
-> player consumes current queue
-> Tag Manager fixes tags
-> cache/diagnostics keep thumbnails and media details stable
```

已完成的一阶段工作：

```text
Chat 1: 架构与跨平台边界
Chat 2: 标签模型与过滤引擎
Chat 3: 媒体库标签 UI
Chat 4: 播放器过滤队列
Chat 5: 缩略图、诊断与 FFmpegBackend
Chat 6: 标签管理器与批量打标
Chat 7: 响应式 UI 与平台 polish
```

当前验证状态：

```text
flutter analyze: passed
flutter build windows --debug: passed
debug exe can start
flutter run may hang / timeout in CLI
dart format may timeout locally
manual real-window QA with large media library is still needed
```

下一阶段优先级：

```text
1. 稳定开发基线：Git / backup、flutter run、dart format
2. 使用真实媒体目录做手动 smoke test
3. Stable Video Identity + Missing / Relink 设计
4. videoId + fingerprint + mutable path 迁移
5. Smart List 持久化
6. 标签删除 / 合并的真实实现
7. 自动标签规则
8. macOS / Linux 桌面准备
```

不要在没有明确要求时重做 Chat 1-7 的一阶段工作。
不要把本项目当成通用专业播放器。
在标签发现、稳定身份、标签维护稳定前，不要优先做字幕、音轨、逐帧、A-B loop 等高级播放器功能。

## 1. 上下文读取规则

修改代码前，先选择能安全完成任务的最小上下文级别。
不要为了小修复读取完整项目历史。

### Context Budget / Handoff

当背景信息窗口达到、超过或接近软件限定上下文长度的 70% 时，必须优先压缩上下文或把当前对话记录、任务状态、已改文件、验证结果和下一步计划传递给下一个新对话，保证继续开发时上下文占用不超过软件限定值的 70%。

每次执行连续开发任务时，都必须显式遵守并复述这句话：

```text
从第一性原理出发，后续修改进行对抗式审查，任务结束后自己给出下一步计划
```

### Level 1: Small Fix

适用：analyzer/build 报错、单文件编译错误、缺失符号、小 UI 溢出、拼写修复。

只读：

```text
AGENTS.md
明确的报错或用户给出的 blocker
直接相关源文件
必要时只查直接 imports/callers
```

不要读取完整 `ROADMAP.md`、`CHANGELOG.md`、全部 `docs/chat_tasks/CHAT_*.md` 或完整跨平台计划。
只用 `rg` 查精确符号或错误；除非直接引用无法解析，否则不要全项目扫描。

### Level 2: Bounded Feature / UI Task

适用：一个有限功能、一个页面/组件/服务改动、一个 Chat 阶段内的有限任务。

读取：

```text
AGENTS.md
PROJECT.md
CURRENT_TASK.md
一个相关 docs/chat_tasks/CHAT_*.md
直接相关源文件
通过精确符号搜索找到的小片段
```

仅当任务触及 `src/core`、共享模型、repository contracts、平台边界或共享 route/layout contract 时读取 `ARCHITECTURE.md`。
仅当优先级或阶段归属不清时读取 `ROADMAP.md`。
仅当更新历史记录或确认行为是否已改过时读取 `CHANGELOG.md`。

### Level 3: Architecture / Schema / Boundary Task

仅适用：SQLite schema/migrations、`src/core`、平台接口、repository contracts、`FilterQuery`、`TagQueryService`、`PlayerBackend`、`FFmpegBackend`、stable identity、missing/relink、文件移动、标签删除/合并迁移、项目 roadmap/architecture 文档修改。

读取：

```text
AGENTS.md
PROJECT.md
ARCHITECTURE.md
CURRENT_TASK.md
ROADMAP.md
CHANGELOG.md
当前任务相关 docs/chat_tasks/CHAT_*.md
<private-planning-document>
相关源文件
```

如果外部跨平台计划与旧实现习惯冲突，外部计划优先。

如果 Level 1/2 调查发现必须修改 schema、共享查询语义、平台边界、stable identity 或 player/cache queue，立即升级为 Level 3。

## 2. 第一性原理规则

开始任务前先用最短形式确认：

```text
Product goal protected:
Core loop part protected:
Must not change:
Smallest safe change:
Fewest safe tokens:
```

不要为了局部实现细节破坏标签发现闭环。

## 3. 对抗式审查规则

完成计划或代码修改前，做短审查：

```text
schema: unchanged / changed with migration notes
FilterQuery / TagQueryService: unchanged / changed intentionally
filtered queue: unchanged / changed intentionally
thumbnail/media queue: unchanged / changed intentionally
user data: preserved / risk noted
prompt impact: satisfies first principles / adds unnecessary scope or context
validation: analyze/build result
```

如果发现风险，修复或清楚说明。

## 4. 平台边界规则

平台无关逻辑：

```text
Tag search
Tag management
FilterQuery
PlaybackSession
TagQueryService
```

平台相关逻辑必须留在边界后：

```text
FileSystemAdapter
PlayerBackend
FFmpegBackend
DatabaseProvider
AppPaths
```

不要把 Windows 路径、exe、文件管理器命令或平台假设散落到 UI 或业务逻辑中。

## 5. 标签来源规则

```text
folder tags = path-derived initial classification
manual tags = user-maintained data
```

合法来源：

```text
manual
folder
rule
filename
import
auto
```

规则：

```text
1. folder tags 可以由路径规则重新计算。
2. manual tags 必须保留。
3. rule / filename / import / auto tags 由各自系统负责。
4. locked tags 不能被自动流程静默删除。
5. 同名 folder tag 和 manual tag 不能混淆。
6. 能用 tagId 时优先用 tagId，不要只按 name 匹配。
```

## 6. 过滤规则

默认语义：

```text
different groups: AND
same group: OR
excluded tags: NOT
keyword: file name / path / tag name / tag alias
```

不要在 UI 中复制过滤逻辑。
过滤必须经过 `FilterQuery` / `TagQueryService`，除非当前任务明确修改该层。

## 7. 播放队列规则

```text
播放器消费当前过滤队列。
```

规则：

```text
1. 从过滤后的媒体库结果打开 PlayerPage 时，传入该过滤队列。
2. 右侧队列不能回退到全局媒体库列表。
3. 当前 index 显示应类似 1/1661。
4. 返回媒体库必须保留过滤状态。
5. 右侧二级标签切换必须保持在来源过滤队列内。
6. 标签发现闭环稳定前，不优先做高级播放器功能。
```

## 8. 缓存与诊断规则

```text
FFmpeg / FFprobe 访问必须经过 FFmpegBackend 或兼容层。
```

规则：

```text
1. 可见项目优先级更高。
2. 后台任务必须限流。
3. 失败项目应可重试。
4. 失败原因应可见。
5. 0-byte 或不完整 JPEG 不能当作有效缓存。
6. diagnostics UI dispose 后不能保留 timers 或 async callbacks。
```

## 9. SQLite / Migration 规则

任何 schema 修改必须：

```text
1. 向后兼容。
2. 幂等。
3. 有文档记录。
4. 对旧数据库安全。
5. 保留用户维护的数据。
6. 通过 flutter analyze 和 flutter build windows --debug。
```

不要立即删除 missing videos。
未来行为应先标记 missing。

## 10. Stable Identity 方向

未来方向：

```text
videoId = stable database identity
fingerprint = file / media identity
path = current mutable location
missing = path invalid but record is preserved
```

tags、favorites、play records、playback progress 应绑定 stable video identity，而不是 mutable path。

## 11. 注释规则

所有新增代码都必须同步增加能帮助后续维护的注释。注释覆盖范围包括：

```text
1. 类 / widget / service 的总体功能注释。
2. 字段用途注释。
3. 方法职责注释。
4. 参数含义注释，尤其是回调、状态输入、筛选上下文输入。
5. 条件分支意图注释，说明为什么需要该条件。
6. 容易误解的业务规则。
7. 平台边界决策。
8. SQLite migration 假设。
9. 标签来源规则。
10. folder/manual/rule tag 分离。
11. async queue 或 cancellation 行为。
12. 缓存有效性规则。
13. relink / missing / fingerprint 逻辑。
14. 不明显的性能选择。
```

修改代码时必须同步更新对应注释，避免注释描述旧行为。
删除代码时必须删除对应注释，避免留下悬空说明。
发现周边代码缺少必要注释时，应自行补充，目标是保证代码可读性和后续维护安全。
代码注释必须使用中文；只有 API 名称、协议名、字段名、固定术语或外部错误信息需要原文保留时，才允许夹带英文。
类、widget、service、字段、方法、参数等面向 API / 结构的说明使用块级文档注释 `/** ... */`。方法内部、条件分支、局部实现意图使用普通行注释 `//`。
注释应解释“职责、约束、意图、边界”，不要只复述语法。

好：

```dart
/**
 * 目录标签可由路径重新计算，但手动标签必须在文件移动后保留。
 */
```

差：

```dart
// i 加 1。
```

## 12. 文档规则

有意义的代码修改后，更新相关文档：

```text
CURRENT_TASK.md
CHANGELOG.md
docs/chat_tasks/CHAT_*.md
如果修改 src/core、schema、平台边界或共享 contract，更新 ARCHITECTURE.md
如果修改优先级或阶段归属，更新 ROADMAP.md
```

## 13. 验证规则

代码修改后至少运行：

```powershell
flutter analyze
flutter build windows --debug
```

UI 或运行时行为变更还要尽量验证：

```powershell
flutter run -d windows
```

UI 修改完成后，必须自行启动应用并模拟点击测试对应改动功能。测试范围至少覆盖本次新增或修改的主要交互入口，并与当前蓝图 UI 做短对比，输出下一步完善计划。
如果本地自动化或运行窗口不可用，必须记录阻塞原因、已完成的替代验证，以及仍需人工复测的点击路径。

如果 `dart format` 本地超时：

```text
记录为已知本地 formatter 问题。
不要声称格式化成功，除非它确实完成。
```

### Git 提交规则

每次完成代码或文档修改并通过对应验证后，都必须进行一次 git 提交。

规则：

```text
1. 提交前先检查 git status。
2. 只 stage 本次任务相关文件；不要把无关用户改动、临时产物、构建产物或工具缓存一起提交。
3. 如果工作树已有无关改动，保留它们，不回滚、不整理，只提交本次范围。
4. 提交信息必须简短说明本次可验证交付物。
5. 如果验证失败或用户明确要求暂不提交，必须说明原因并不提交。
```

## 14. 安全规则

```text
不要做无关清理。
不要在没有明确要求时重写大系统。
不要静默改变 schema、player behavior、tag semantics 或 cache invalidation。
不要在当前任务没有明确要求时实现 Smart List、missing/relink、文件移动、标签删除/合并迁移或高级播放器功能。
优先小而可回滚的修改。
```

## 15. Token 预算规则

目标：

```text
用最小安全上下文完成最小可验证修改。
```

规则：

```text
1. token 使用是任务正确性的一部分。
2. 不要把完整项目历史粘贴进每个任务。
3. 先选择 Level 1 / 2 / 3。
4. 任务提示只包含 task level、目标、已知 blocker、可能相关文件、验证命令、明确非目标。
5. Level 1 不读完整 ROADMAP、CHANGELOG、全部 Chat docs 或跨平台计划。
6. 除非直接符号搜索失败或任务是 Level 3，否则不要全项目扫描。
7. 命令失败时不要打印完整日志，只总结关键错误、文件和行号。
8. final 不输出完整 diff，只总结改动文件和关键行为。
9. 避免无关格式化、宽泛清理和大重构。
10. 优先小而可回滚的修改。
```

## 16. 会话、日志与交接规则

每个 Codex 会话尽量服务一个交付物。

继续同一会话的情况：

```text
same bug fix
same PR / patch set
same bounded feature phase
same validation loop
```

新建或恢复独立会话的情况：

```text
small fix -> unrelated UI redesign
media library task -> player backend task
project coding -> blog/research/writing
one-off investigation unrelated to Local Tag Player
```

切换会话时，写短交接摘要，不复制完整历史：

```text
Goal:
Current status:
Changed files:
Validation:
Remaining blocker:
Do-not-change constraints:
Next exact command/task:
```

日志规则：

```text
日志放文件中。
只搜索 ERROR / Exception / failed / exit code / undefined symbol。
只读匹配附近 30-80 行。
不要输出完整日志。
```

Level 3 或范围不清时，先写短计划再编辑：

```text
files to inspect
expected ownership layer
possible migration/risk
validation commands
```

## 17. Repo Skills 规则

`.agents/skills` 是本项目的 repo-scoped Codex skill 目录。

规则：

```text
1. 每个 skill 必须有 `SKILL.md`。
2. 每个 `SKILL.md` 必须使用标准 YAML frontmatter。
3. frontmatter 只放 `name` 和 `description`。
4. `name` 必须是小写字母、数字和连字符。
5. `description` 必须写清楚触发场景。
6. skill 用来缩小范围，不用来扩大上下文。
7. 优先调用最小相关 skill，不要叠加多个重叠 skill。
```

可用项目 skills：

```text
$ltp-task-router
$ltp-small-fix
$ltp-log-triage
$ltp-session-handoff
$ltp-tag-filter-data
$ltp-media-library-tag-ui
$ltp-player-filter-queue
$ltp-cache-diagnostics
$ltp-stable-identity-missing-relink
$ltp-tag-manager-batch-tagging
```

稳定规则放在 `AGENTS.md`、`NEW_CHAT_BOOTSTRAP.md` 和 `.agents/skills`。
临时任务材料放在用户提示末尾或独立文件中。
