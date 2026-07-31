# AGENTS.md

## 1. 权威范围

本文件只保存 Local Tag Player 每个任务都必须遵守的长期规则：

- 产品和用户数据边界；
- 最小上下文路由；
- 验证、既有行为保护和交付规则；
- repo Skill 与 Agent eval 约束。

当前状态只写 `CURRENT_TASK.md`；当前架构和优先级分别写
`ARCHITECTURE.md`、`ROADMAP.md`；历史进入 `docs/task_history/`、
dated QA/ADR 或 `CHANGELOG.md`。不要把阶段快照复制回本文件。

## 2. 产品目标与核心闭环

```text
Tag-driven local video discovery player
not a PotPlayer / VLC replacement
not a general professional video player

scan local folders
-> derive folder tags
-> maintain manual tags
-> grouped filtering and alias search
-> current filter chips and result count
-> filtered playback queue
-> player consumes that queue
-> Tag Manager repairs tags
-> cache/diagnostics keep media details stable
```

没有明确要求时，不重做已完成的一阶段 Chat 1–7，也不优先实现字幕、音轨、
逐帧、A-B loop、Smart List、missing/relink、文件移动或标签迁移等扩展。

## 3. 任务路由与上下文预算

修改前选择能安全完成任务的最小 Level：

- Level 1：明确 analyzer/build 单点错误、单文件编译错误、小溢出、拼写。
  只读本文件、报错、直接相关文件及必要 caller/import。
- Level 2：单页面、组件、服务或有限 UI/功能。读本文件、`PROJECT.md`、
  `CURRENT_TASK.md`、一个直接相关 Chat/contract 和相关源码。
- Level 3：schema/migration、`src/core`、repository/platform contract、
  `FilterQuery`、`TagQueryService`、`PlayerBackend`、缓存/播放队列、
  stable identity、missing/relink、文件移动、标签迁移、架构/路线图治理。
  读 current contract、相关 ADR/Chat 片段和直接源码；`CHANGELOG` 与历史只用
  `rg` 精确查询，不得默认全读。
- 生产或真实窗口发现的未授权功能删除一律 Level 3、`independent` 验证。

调查发现触及更高层边界时立即升级。小修复不得读取完整路线图、变更史或全部 Chat。
背景接近上下文窗口 70% 时先压缩或用 `ltp-session-handoff` 交接。

连续开发任务必须显式复述：

```text
从第一性原理出发，后续修改进行对抗式审查，任务结束后自己给出下一步计划
```

开始时只确认：

```text
Product goal protected:
Core loop part protected:
Must not change:
Smallest safe change:
Fewest safe tokens:
```

## 4. 业务与平台硬边界

平台无关逻辑留在 Dart 业务层：

```text
Tag search / Tag management / FilterQuery / PlaybackSession / TagQueryService
```

平台实现留在显式边界后：

```text
FileSystemAdapter / PlayerBackend / FFmpegBackend / DatabaseProvider / AppPaths
```

不得把 Windows 路径、exe 或文件管理器命令散落到 UI/业务层。

标签来源只允许 `manual/folder/rule/filename/import/auto`：

- folder 标签可由当前 root 文件树重算；manual 标签必须保留；
- locked 标签不能被自动流程静默删除；
- 同名 folder/manual 不得混淆；能用 `tagId` 时不用 name 代替；
- 一级 folder 标签只来自 root 第一层，二级只来自所属一级的下一层；
- 二级标签不能提升到一级、脱离父级展示或单独参与真实筛选；
- 历史数据库层级与当前文件树冲突时，以当前文件树为准。

过滤语义：

```text
different groups: AND
same group: OR
excluded tags: NOT
keyword: file name / path / tag name / alias
```

UI 不复制过滤逻辑；筛选必须经过 `FilterQuery` / `TagQueryService`。

播放器只消费来源页面的 filtered queue：

- 右侧队列不得回退全局媒体库；
- 当前序号反映来源队列；
- 二级标签切换留在来源队列；
- 返回媒体库保留筛选状态。

缓存/诊断：

- FFmpeg/FFprobe 只经过 `FFmpegBackend` 或兼容边界；
- 可见项目优先，后台任务限流、可取消，失败可见且可重试；
- 0-byte/不完整 JPEG 不是有效缓存；
- diagnostics dispose 后不得保留 timer/async UI callback。

稳定身份方向：

```text
videoId = stable database identity
fingerprint = media identity
path = mutable location
missing = invalid path while record is preserved
```

tags、favorites、play records、progress 绑定 stable identity，不绑定 mutable path。
schema 修改必须向后兼容、幂等、有 migration 记录、旧库安全并保留用户数据；
不要立即删除 missing video。

## 5. 用户体验与性能

用户体验优先于实现便利。界面、筛选、排序、路径切换、搜索、弹窗和播放器返回不得
在 UI 线程反复全量重算或无差别 rebuild；优先缓存、增量、取消过期任务和延后非关键统计。

- 标签点击先更新可见结果；计数和缩略图预取延后；
- 排序切换不得触发完整标签计数刷新；
- 搜索使用稳定 `TextField` / `TextEditingController` / `EditableText` 链路，
  不退回已知不稳定的 `SearchBar` 输入实现；
- 标签中心按来源、分组、父级和大小写归一合并展示；同名二级 folder 标签显示父路径；
- 媒体库、标签、筛选、排序或路径浏览变更必须验证标签点击、切换后的加载和流畅度；
- “更多”先打开明确菜单；删除/移除等危险动作必须确认；
- 影响解码、缓存或播放稳定性的设置需要确认或撤销路径。

## 6. 修改规则

- 只修改用户授权行为；不做无关清理、大重写或静默语义变化。
- 保留用户未提交改动，不使用破坏性 Git/文件命令。
- 新增/修改代码同步维护中文注释；结构职责用 `/** ... */`，局部意图用 `//`。
  注释解释职责、约束、意图、边界、迁移、来源分离、取消和性能选择，不复述语法。
- 删除实现时同步删除悬空注释。
- 文档和提交信息中文优先；API、协议、路径、命令和固定术语可保留原文。

有意义的代码修改更新：

- `CURRENT_TASK.md`：只更新当前、最近三项、阻塞和下一步；
- `CHANGELOG.md`：对外行为变更；
- 直接相关 Chat/QA 文档；
- 修改 core/schema/platform/shared contract 时更新 `ARCHITECTURE.md`；
- 修改阶段优先级时更新 `ROADMAP.md`。

## 7. 验证与既有行为保护

业务代码至少运行：

```powershell
flutter analyze
flutter build windows --debug
```

同时运行直接相关 focused/widget tests。UI/运行时变更在构建后启动软件并真实点击主要入口；
涉及菜单、弹窗、布局、状态或视觉反馈时截图检查位置、遮挡、对齐、溢出、对比度和状态。
客观不可用时记录阻塞、替代验证和精确人工路径，不得冒充完成。

修改可能删除、移动或替换现有分支/UI 子树前：

1. 建立受保护行为清单：入口、相邻入口、显隐、快捷键、持久化、返回路径。
2. 用源码、focused tests、`CURRENT_TASK` 和精确 Git 历史确认行为。
3. 单列获授权删除项；未列出的一律保留，无法确认时也保留。
4. 审查 diff 中被删 Widget、ValueKey、callback、Route、菜单、Overlay/Stack 和条件分支。
5. 组件存在或组件测试通过不等于页面可达；关键行为必须有页面挂载/可达性证据和真实点击。

受保护行为缺少证据、真实验证失败或删除授权不明时不得提交；先恢复旧行为。
生产未授权删除还必须补：

- 精确 root cause；
- 能在组件孤立/挂载移除时失败的 code guard；
- `evals/agent/regression_cases.json` 只增不删的事故用例；
- 停止编辑后的独立只读验证。

`dart format` 超时必须如实记录，不能声称成功。

## 8. 对抗式审查与交付

最终审查至少写：

```text
schema: unchanged / changed with migration notes
FilterQuery / TagQueryService: unchanged / changed intentionally
filtered queue: unchanged / changed intentionally
thumbnail/media queue: unchanged / changed intentionally
user data: preserved / risk noted
prompt impact: satisfies first principles / unnecessary scope
protected behaviors: preserved / authorized changes listed
unauthorized feature removal: none / blocker
mount and reachability: page-level evidence / not applicable
validation: exact tests/analyze/build/runtime result
```

验证通过后：

1. 检查 `git status`；
2. 只 stage 本任务文件；
3. 使用中文提交；
4. push 当前跟踪分支；
5. 失败时保留本地提交并说明原因。

日志写入文件，只检索 `ERROR/Exception/failed/exit code/undefined symbol` 附近 30–80 行。
不要在提示或 final 粘贴完整历史、日志、diff 或大 JSON/CSV。

## 9. Repo Skill 与 Agent eval

`.agents/skills` 只保存标准目录 Skill；每个 `SKILL.md` frontmatter 只含
`name`、`description`。Skill 用来缩小而不是扩大上下文。

- `ltp-task-router` 只分级，完成后退出；
- 选择一个最小领域 Skill；
- `ltp-apple-ui-design` 只用于明确视觉/动效/交互/无障碍任务；
- 纯 schema、过滤、队列、后端、缓存或 stable identity 不触发 Apple UI；
- 视觉任务最多一个领域 Skill + 一个设计覆盖层。

修改本文件、bootstrap、harness、Skill、description、trigger 或 Agent prompt 时：

1. 按 `docs/agent_eval.md` 更新受影响用例；
2. 运行 `python tool/agent_eval.py validate`；
3. 运行 `python -m unittest discover -s test -p agent_eval_tool_test.py -v`；
4. 关键 Skill 运行时回归使用隔离临时克隆和 N=5，不在真实工作树试验被测 Agent。
