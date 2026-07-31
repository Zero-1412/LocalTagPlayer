# Agent Harness

本文档只定义 Level 2/3 和真实媒体 QA 的可执行合同。产品、安全、代码、验证和 Git
硬规则以根目录 `AGENTS.md` 为唯一权威来源；本文不复制这些规则。

## 适用范围

使用 Harness：

- Level 2 有限功能、UI 或真实窗口 QA；
- Level 3 schema、core、repository/platform contract、stable identity、
  missing/relink、player/cache queue 或架构治理；
- 需要多轮验证、真实媒体目录或 champion/challenger 决策。

不使用 Harness 扩大：

- Level 1 单点小修复；
- 用户明确要求只调查、只回答或不写文件；
- 与 Local Tag Player 无关的工作。

## 最小迭代

```text
TaskContract
-> 最小上下文和直接证据
-> challenger patch
-> deterministic validation
-> 停止编辑
-> structured/independent review
-> PromotionDecision
-> 当前状态与提交
```

## TaskContract

Level 2/3 实施前填写：

```yaml
task_level: 2 | 3
validation_mode: structured | independent
goal:
scope:
non_goals:
done_when:
  - id:
    assertion:
    required: true
deliverable:
```

规则：

- `done_when.id` 本轮唯一；
- assertion 必须是用户可观察行为、确定性边界或明确产物；
- 不把“已修改代码”“看起来正常”当完成条件；
- 每个 `done_when` 恰好对应一条验证记录。

## ValidationRecord

```yaml
requirement_id:
status: passed | failed | blocked | not_run
method: deterministic | same_agent | independent | human
evidence:

promotion_decision: promoted | not_promoted | needs_manual_qa
```

- `passed` 必须写具体命令、测试、截图、点击路径、diff 或其它可复核证据；
- 未运行、超时、工具缺失或窗口不可用必须如实记录；
- required 项失败只能 `not_promoted`；
- required 项 blocked/not_run 不得 `promoted`；
- Level 3 至少一项关键记录使用 `independent`；
- analyze、build、focused test、真实点击和截图分别记录。

## 验证模式

| Level | 模式 | 要求 |
|---|---|---|
| 1 | `single_agent` | 同一 Agent 做最小修改和验证，不伪装独立复核 |
| 2 | `structured` | 编辑结束后停止写入，按完成项逐项复核 |
| 3 | `independent` | 实现与最终复核分离；Validator 只读 |

Level 2 遇到主观 UI 争议、重复验证失败或证据冲突时可升级为独立复核，但业务 Level
不自动改变。

## Validator 只读边界

Validator 只读取任务合同、diff、直接源码、测试输出、日志和截图；可以运行非破坏性检查，
不得修复、改文件、提交或推送。它只能返回：

```text
covered requirements
missing evidence
regression risks
promotion recommendation
```

Validator 不得缩窄用户目标、删除失败测试或改写完成条件来制造通过。

## Champion / Challenger

`champion` 是任务开始前已有验证证据的基线。`challenger` 只包含本任务需要的改动。

只有同时满足以下条件才晋级：

- 目标行为或验证缺口确实改善；
- required 验证通过；
- 核心标签发现闭环没有退化；
- 没有硬编码、绕过业务层或缩窄测试；
- 用户数据无新增风险，或 migration/回滚证据完整；
- 未授权功能删除为零。

否则保持原 champion，把本轮结果记为 `not_promoted` 或 `needs_manual_qa`。

## 真实媒体 Smoke 索引

只在任务触及相应领域时选择以下小节，不默认执行全部：

### 扫描与标签

- root 第一/第二层正确派生一级/二级 folder 标签；
- 无二级目录视频进入默认专辑语义；
- 重扫不删除 manual/locked 标签；
- 异常文件不终止整次扫描。

### 筛选与搜索

- 同组 OR、跨组 AND、排除 NOT；
- 关键词覆盖文件名、路径、标签名、别名；
- chips、结果数量与可见结果一致；
- 清空筛选恢复全部结果；
- 高频点击不被计数或预取阻塞。

### 播放队列

- 播放器队列来自当前 filtered result；
- 序号、二级标签切换和返回状态保持来源语境；
- 快速切换不会被旧 open 请求覆盖。

### Tag Manager

- manual/folder 来源不混淆；
- 批量操作只影响目标结果；
- 未实现可靠迁移的删除/合并入口保持保护态。

### 缓存与诊断

- 可见项目优先、后台限流；
- 0-byte/半截 JPEG 无效；
- 失败原因可见且可重试；
- FFmpeg/FFprobe 经过边界；
- dispose 后无 timer/async UI 回调。

### 响应式与真实窗口

- compact/medium/expanded 主要入口可达且无 overflow；
- 搜索、排序、视图、标签面板、菜单和弹窗可点击；
- 文案、对齐、遮挡、对比度、状态反馈和 reduced motion 符合任务要求。

真实媒体测试优先使用临时 profile；必须用真实 profile 时，不删除、迁移或重写用户数据。

## 重试与交接

```text
planned -> executing -> validating -> promoted
                         |
                         +-> retry_archive -> executing
                         +-> needs_manual_qa / blocked
```

只保留最近两轮：失败原因、已确认事实、未覆盖项和下一条动作。不要复制完整日志、diff
或工具轨迹。上下文接近 70% 时使用：

```text
Goal:
Current status:
Changed files:
Validation:
Remaining blocker:
Do-not-change constraints:
Next exact task:
```

## 最小记录

较大任务只在 `CURRENT_TASK.md` 记录短状态；完整证据进入相关 QA/Chat/ADR：

```text
task contract:
baseline champion:
challenger:
changed files:
validation:
real media smoke:
promotion decision:
remaining blocker:
next exact step:
```

修改 Agent 规则、Skill、prompt、trigger 或 Harness 时，按 `docs/agent_eval.md`
更新用例并运行零模型成本门禁；关键 Skill 的 N=5 在隔离临时克隆中执行。
