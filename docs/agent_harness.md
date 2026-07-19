# Agent Harness 迭代闭环

本文档把 `AGENTS.md` 中的长程执行规则整理为可复用的每轮迭代模板。它用于较大功能、架构边界、真实窗口 QA、真实媒体目录 smoke test 和需要多轮验证的修复任务；小修复仍优先按 Level 1 最小上下文处理。

## 目标

Local Tag Player 的 Agent Harness 目标不是扩大任务范围，而是让每次较大修改都能围绕同一个可验证闭环推进：

```text
定义目标
-> 选择最小上下文级别
-> 基于当前 champion 做一个 challenger patch
-> 自测和真实场景验证
-> 对抗式审查
-> 判断 challenger 是否晋级
-> 记录结果并提交
```

Agent 必须保护项目定位：

```text
Tag-driven local video discovery player
not a PotPlayer / VLC replacement
not a general professional video player
```

## 结构原则

后续 agent 框架优化只按以下四条原则演进，不把临时经验继续堆进主规则：

- 主规则稳定：`AGENTS.md` 只保留长期有效的产品边界、安全约束和验证规则，不承载单次任务细节。
- 能力按需加载：repo skills、`docs/agent_harness.md`、`docs/qa/*` 和 `docs/chat_tasks/*` 只在任务触发时读取，避免把全部历史塞进上下文。
- 长程任务持久化记录：较大功能、Level 3 任务和真实媒体目录 QA 必须在 `CURRENT_TASK.md` 或对应 `docs/chat_tasks/CHAT_*.md` 留下目标、baseline、patch、验证和剩余阻塞。
- 验证结果决定是否晋级：本轮 `challenger` 只有在必要验证通过、核心闭环未退化、用户数据无新增风险时，才成为新的 `champion`。

## Agent Eval 门禁

Champion / Challenger 是开发迭代模型，不等于 Agent 已经通过测评。修改 Agent 规则、Skill、description、trigger、prompt 或本 Harness 时，还必须执行 [`docs/agent_eval.md`](agent_eval.md) 定义的自动化闭环：

```text
input
-> isolated Codex execution
-> raw JSONL + normalized Trace + artifacts
-> deterministic scorer / optional Rubric judge
-> comparable score + N-trial stability
```

门禁规则：

- 每个 Skill 至少有两个正触发和两个负触发用例。
- 确定性事实、工具、文件范围、状态和产物结构由脚本评分；Apple 观感等主观质量才交给 Rubric judge。
- capability 用例允许迭代；达到稳定门槛后复制到 regression。
- regression 只增不删；生产 badcase、真实窗口误操作和越界修改必须转成回归用例。
- stable identity、标签过滤、filtered queue、缓存和用户数据相关用例默认 N=5，要求 5/5。
- 被测 Agent 只在临时隔离克隆中运行；真实工作树仅保存用例、脚本和已确认的基线报告。

优先保护的产品闭环：

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

## 适用范围

使用本文档的场景：

- Level 2 的有限功能、UI 任务或真实窗口 QA。
- Level 3 的 schema、`src/core`、repository contract、平台边界、stable identity、missing/relink、player/cache queue 任务。
- 需要连续运行验证命令、分析失败、修复并重新验证的任务。
- 需要真实媒体目录 smoke test 的任务。
- 需要判断本轮修改是否优于当前基线的任务。

不使用本文档扩展范围的场景：

- analyzer/build 单点错误、拼写、小溢出等 Level 1 小修复。
- 用户明确要求只做调查、只回答问题或暂不修改文件。
- 与 Local Tag Player 无关的一次性任务。

## 分级验证模式

任务 Level 同时决定验证方式，避免小修复承担不必要的编排成本：

| Level | 验证模式 | 执行与验证关系 |
| --- | --- | --- |
| Level 1 | `single_agent` | 同一 Agent 完成最小修改和最小验证，不启动独立 Validator。 |
| Level 2 | `structured` | 同一 Agent 可以执行验证，但进入验证阶段后停止编辑，并逐项记录证据。 |
| Level 3 | `independent` | 实现与最终验证分离；由独立 Agent 或上下文重置后的只读验证回合完成。 |

Level 2 遇到主观 UI 判断、第二次验证失败或证据互相冲突时，应升级为独立验证阶段，
但任务业务 Level 不因此自动变成 Level 3。Level 3 Validator 不得修复代码；发现缺口后返回
结构化失败记录，由下一轮 Executor 决定是否重试。

## Task Contract

Level 2 / 3 在实施前必须建立最小任务合同；Level 1 可以只保留一条完成条件：

```text
task_level:
validation_mode:

TaskContract:
  goal:
  scope:
  non_goals:
  done_when:
    - id:
      assertion:
      required: true / false
  deliverable:
```

`done_when.id` 在本轮内必须唯一。完成条件描述用户可观察行为、确定性边界或必须交付的产物，
不要只写“代码已修改”“看起来正常”等无法验证的过程描述。

## 结构化验证记录

每个 `done_when` 必须恰好对应一条验证记录：

```text
ValidationRecord:
  requirement_id:
  status: passed / failed / blocked / not_run
  method: deterministic / same_agent / independent / human
  evidence:

PromotionDecision:
  promoted / not_promoted / needs_manual_qa
```

确定性规则：

- `passed` 必须包含具体命令、测试名、截图路径、点击路径、diff 事实或其它可复核证据。
- 未运行、超时、工具缺失或窗口不可用必须记录为 `blocked` / `not_run`，不得降格成通过。
- 任一必选项 `failed` 时只能 `not_promoted`。
- 任一必选项 `blocked` / `not_run` 时不得 `promoted`；需要人工复测时使用 `needs_manual_qa`。
- Level 1 可以使用 `same_agent`，但不得伪装成 `independent`。
- Level 3 至少有一条关键完成项由 `independent` 记录覆盖；确定性工具证据作为该记录的依据或补充。
- Flutter test、analyze、build、真实点击和截图分别记录，不用一条“完整验证通过”合并所有证据。

## Validator 只读边界

独立验证阶段只允许读取任务合同、diff、直接相关源码、测试输出、运行日志和截图；可以运行
非破坏性检查，但不得写文件、修复代码、提交或推送。Validator 只返回覆盖项、缺项、风险和
晋级建议，不能通过缩窄 `done_when`、删除失败测试或改写用户目标来制造通过。

## 状态与重试归档

较大任务使用以下最小状态流：

```text
planned -> executing -> validating -> promoted
                         |
                         +-> retry_archive -> executing
                         +-> needs_manual_qa / blocked
```

重试只归档：上一轮临时结论、最近失败原因、已确认事实、未覆盖的 `done_when` 和下一条精确动作。
同一任务最多保留最近两轮摘要；不要把完整工具轨迹、日志或 diff 重新塞回上下文。连续重复同一
动作且没有新增证据时必须收口为失败、阻塞或更换验证方法。

## Champion / Challenger 定义

`champion` 是当前可接受的开发基线，至少满足：

- 最近一次相关验证通过，通常包括 `flutter analyze` 和 `flutter build windows --debug`。
- 未破坏标签发现、分组过滤、filtered playback queue、Tag Manager、缓存诊断等核心闭环。
- 没有为单个 badcase 写入硬编码或绕开真实业务规则。
- 对用户维护数据没有新增未说明风险。

`challenger` 是本轮修改，必须满足：

- 从当前 `champion` 出发，只改本轮任务需要的文件。
- 明确说明它试图改善的行为、缺陷或验证缺口。
- 通过同等级或更强的验证后，才允许晋级为新的 `champion`。

当验证信号很弱、样本很少或只改善一个入口但引入其它退化时，`challenger` 不晋级；保留分析结论，继续从原 `champion` 出发。

## 每轮迭代模板

每次较大任务按以下顺序执行。

### 1. 固定目标和边界

在动手前用低 token 形式确认：

```text
Product goal protected:
Core loop part protected:
Must not change:
Smallest safe change:
Fewest safe tokens:
```

同时写清楚本轮非目标。没有明确要求时，不实现 Smart List、missing/relink、文件移动、标签删除/合并迁移或高级播放器功能。

### 2. 选择上下文级别

先按 `AGENTS.md` 判断 Level 1 / 2 / 3。

- Level 1 只读报错和直接相关文件。
- Level 2 读取 `AGENTS.md`、`PROJECT.md`、`CURRENT_TASK.md`、一个相关 `docs/chat_tasks/CHAT_*.md`、直接相关源文件。
- Level 3 才读取 `ARCHITECTURE.md`、`ROADMAP.md`、`CHANGELOG.md`、跨平台计划和相关底层文件。

如果调查中发现必须修改 schema、`FilterQuery`、`TagQueryService`、平台边界、stable identity 或 player/cache queue，立即升级为 Level 3。

### 3. 制定最小计划

计划必须回答：

- files to inspect：只列直接相关文件。
- expected ownership layer：UI、service、repository、core、platform boundary 或 docs。
- possible migration/risk：是否影响旧库、用户数据、过滤语义、播放队列或缓存。
- validation commands：本轮能实际运行的验证命令。

计划不要把完整历史粘贴进当前上下文。

### 4. 实施 challenger patch

执行时遵守：

- 只修改本轮需要的文件。
- 不回滚用户已有改动。
- 不做无关格式化、无关清理或大重构。
- 业务逻辑必须留在所属层，平台逻辑必须留在边界后。
- 新增或修改代码时，同步更新中文维护注释。

### 5. 验证

代码修改后至少运行：

```powershell
flutter analyze
flutter build windows --debug
```

UI 或运行时行为变更，尽量运行：

```powershell
flutter run -d windows
```

如果 `flutter run` 在 CLI 中挂起或超时，记录为环境限制，并尽量改用 debug exe 或真实窗口 smoke test。

文档-only 修改不强制运行 Flutter 构建；至少检查文档内容、git diff 和工作树范围。

### 6. 对抗式审查

完成修改和验证后，必须写短审查：

```text
schema: unchanged / changed with migration notes
FilterQuery / TagQueryService: unchanged / changed intentionally
filtered queue: unchanged / changed intentionally
thumbnail/media queue: unchanged / changed intentionally
user data: preserved / risk noted
prompt impact: satisfies first principles / adds unnecessary scope or context
validation: analyze/build result
```

如果发现风险，优先修复；不能修复时说明阻塞原因和人工复测路径。

### 7. 晋级判断

本轮 `challenger` 只有同时满足以下条件，才晋级为新 `champion`：

- 目标行为改善或缺陷被修复。
- 必要验证通过。
- 没有引入核心闭环退化。
- 没有用硬编码、绕过业务层或缩窄测试覆盖来换取通过。
- 用户数据风险为无，或已经有迁移说明和回滚路径。

如果 `challenger` 未晋级，不要继续沿着失败 patch 扩大改动；回到当前 `champion` 重新设计下一轮。

### 8. 记录和提交

通过验证并决定接受后：

1. 检查 `git status`。
2. 只 stage 本轮相关文件。
3. 使用中文提交信息。
4. 提交成功后 push 到当前分支远程跟踪分支。
5. 如果远程不存在、认证失败或网络失败，记录原因并保留本地提交。

## 真实媒体目录 Smoke Checklist

真实媒体目录 smoke test 必须用非破坏性方式执行。优先使用临时 profile；如果必须使用真实 profile，先说明风险并避免删除、迁移或重写用户维护数据。

### 准备

- 确认测试目录包含多层文件夹、不同一级/二级标签、至少一个无二级目录视频。
- 确认目录规模足以暴露性能问题；大库测试优先覆盖 1000+ 或真实 11000+ 视频场景。
- 如需隔离数据，使用 `LOCAL_TAG_PLAYER_DATA_DIR` 指向临时目录。
- 记录应用启动方式：`flutter run -d windows`、debug exe 或其它方式。

### 扫描和标签派生

- 添加根目录后能递归扫描视频。
- 一级 folder tag 来自根目录下第一层文件夹。
- 二级 folder tag 来自一级目录下第二层文件夹。
- 一级目录下没有二级目录的视频进入“默认专辑”语义。
- 重新扫描不会删除 manual tags。
- 扫描异常文件不会中断整次扫描。

### 分组过滤和搜索

- 点击一级标签后结果收敛，当前筛选 chips 可见。
- 点击二级标签后结果继续收敛，chips 与结果数量同步。
- 同组标签保持 OR，不同组保持 AND，排除标签保持 NOT。
- 关键字搜索匹配文件名、路径、标签名和别名。
- 清空筛选能恢复全部结果。
- 标签计数不会因为当前筛选错误消失或错乱。

### 播放队列

- 从当前筛选结果点击播放，播放器右侧队列来自当前 filtered result。
- 队列标题和序号反映当前来源，例如 `1 / 1661`。
- 右侧二级标签切换只在来源过滤队列内切换。
- 返回媒体库后筛选状态仍保留。
- 播放快速切换不会被旧 open 请求覆盖。

### Tag Manager

- 创建 manual tag 不会伪装成 folder tag。
- 批量添加 manual tag 只影响当前目标结果。
- 批量移除 manual tag 不删除 folder 来源关系。
- 同名 folder tag 和 manual tag 不混淆。
- 删除/合并入口如果未实现真实迁移，必须保持保护态或明确提示。

### 缓存和诊断

- 可见视频优先生成缩略图。
- 后台缩略图任务有限流。
- 0-byte 或半截 JPEG 不被当作有效缓存。
- 缩略图失败原因可见且可重试。
- 媒体信息读取经过 FFmpegBackend / FFprobe 边界。
- 诊断页关闭后没有继续刷新 UI 的 timer 或 async callback。

### 响应式和真实窗口

- 普通窗口和最大化窗口都无明显 overflow。
- 顶部搜索、排序、视图切换、右侧标签面板入口可见且可点击。
- compact / medium / expanded 下主要入口不遮挡。
- UI 文案保持中文，无乱码。

## Champion / Challenger 记录格式

较大任务完成后，在 `CURRENT_TASK.md`、相关 `docs/chat_tasks/CHAT_*.md` 或交接摘要中记录：

```text
Harness iteration:
task contract:
baseline champion:
challenger patch:
changed files:
validation:
real media smoke:
regression check:
promotion decision:
retry archive:
next exact step:
```

字段含义：

- `baseline champion`：本轮开始前的 commit、验证状态或已知稳定状态。
- `task contract`：本轮 goal、scope、non-goals、done_when 和 deliverable 的紧凑版本。
- `challenger patch`：本轮尝试改善的行为。
- `changed files`：只列本轮相关文件。
- `validation`：命令和结果，不要声称未完成的命令通过。
- `real media smoke`：真实目录点击路径、阻塞原因或人工复测清单。
- `regression check`：过滤、队列、缓存、用户数据和平台边界是否受影响。
- `promotion decision`：`promoted` / `not promoted` / `needs manual QA`。
- `retry archive`：仅在未晋级时记录最近失败原因、已确认事实和下一条精确动作。
- `next exact step`：下一步可直接执行的命令或任务。

## 子任务和会话交接

只有在以下情况才拆子任务或新会话：

- 上下文接近 70%，需要交接摘要。
- 日志很长，需要专门做错误聚类和附近片段分析。
- Level 3 任务需要分离设计审查、实现和真实窗口 QA。
- 当前任务已经完成，下一步属于不同模块或不同交付物。

交接摘要保持短格式：

```text
Goal:
Current status:
Changed files:
Validation:
Remaining blocker:
Do-not-change constraints:
Next exact command/task:
```

不要把完整历史、完整日志或完整 diff 复制到新会话。
