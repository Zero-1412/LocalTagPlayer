# Agent / Skill Eval 基线

本文档定义 Local Tag Player 的 Agent Eval 最小闭环：

```text
输入用例
-> 隔离临时克隆执行 Codex
-> 捕获原始 JSONL 与规范化 Trace
-> 记录结构化结果和实际文件变化
-> 确定性评分 / 可选 Rubric judge
-> 汇总 N 次稳定性和 suite 通过率
```

Eval 用来验证 Agent 是否真实遵守项目规则，不替代 Flutter 单元测试、真实媒体 smoke 或人工 UI 验收。

## 文件结构

```text
evals/agent/trigger_cases.json
evals/agent/capability_cases.json
evals/agent/regression_cases.json
evals/agent/schemas/*.json
evals/agent/rubrics/*.json
tool/agent_eval.py
test/agent_eval_tool_test.py
```

运行产物写入被 `.gitignore` 排除的 `artifacts/agent_eval/<timestamp>/`，每个 trial 至少包含：

```text
raw_trace.jsonl        遮盖本地绝对路径后的 Codex CLI 原始事件
trace.jsonl            规范化事件、工具调用与 token
result.json            Agent 结构化最终结果
changed_files.json     隔离仓库的实际 Git 变化
report.json            单次确定性评分
judge_result.json      可选 Rubric judge 结果
summary.json           N 次稳定性和 suite 汇总
```

报告同时记录 Codex CLI 版本、显式或默认模型标识、延迟和 token；CLI 未提供可靠价格表时 `estimated_cost_usd` 保持 `null`，不得编造成本。

## 结构化完成合同

所有被测结果必须输出：

```text
task_contract: goal / scope / non_goals / done_when / deliverable
validation_mode: single_agent / structured / independent
validation: requirement_id / status / method / evidence
promotion_decision: promoted / not_promoted / needs_manual_qa
```

Scorer 会确定性检查 `done_when.id` 唯一、完成项与验证记录一一对应、`passed` 证据非空、
验证模式与方法一致，以及失败/阻塞项不会被错误晋级。Level 1 使用 `single_agent`；Level 2
使用 `structured`；Level 3 使用 `independent`，且至少包含一条独立只读验证记录。

## 用例分层

### Trigger

每个 repo skill 至少维护两个正触发和两个负触发。正例检查应该选中，负例检查不应误选；Skill description 变化时必须更新并重跑相关 trigger 用例。

### Capability

用于仍在探索的能力，允许初始通过率较低。用例连续达到目标、预期过程稳定且没有硬失败后，复制到 regression；能力集可以修改或替换。

### Regression

用于已经确认的产品边界和历史 badcase，只增不删。确定性核心约束要求所有 trial 通过；生产或真实窗口发现的 Agent badcase 必须补成回归用例。

## Trace 约定

规范化 `trace.jsonl` 每行一个 JSON 事件。当前保留：

- `raw_event`：完整 Codex JSONL 事件，便于以后重新归一化。
- `tool_call`：可识别的命令或 MCP 工具调用及参数。
- `usage`：输入、缓存输入和输出 token 汇总。
- `invalid_raw_event`：无法解析的原始行，不允许静默丢失。

评分必须使用隔离仓库的真实 `git status`，不能只信任 Agent 自报的 `changed_files`。运行器会遮盖用户目录、真实仓库和隔离克隆的绝对路径；Trace 和报告仍不得输入令牌、用户媒体路径、数据库内容或其它秘密。

## 评分规则

每个 trial 从 100 分开始，80 分通过：

- 完成状态错误：扣 100。
- 任务等级错误：扣 20。
- 缺少应触发 Skill 或误触发禁止 Skill：每项扣 40。
- 修改只读用例或命中禁止文件：扣 100。
- 缺少必要工具：每项扣 15；使用禁止工具：每项扣 30。
- 工具顺序不满足用例：扣 15。
- TaskContract、验证覆盖或晋级逻辑不一致：扣 100。
- 验证模式或预期晋级结论错误：扣 100。
- 缺少 Rubric judge：扣 20；主观评分低于 80：扣 30。
- Rubric 出现硬失败：扣 100。

确定性 scorer 负责事实、文件、工具、状态和结构；LLM Rubric 只负责 Apple 观感、层级、清晰度等不能稳定脚本化的判断。

## 工具调用与 token 预算

每个 suite 都有默认成本门槛，用例可通过 `budgets` 收紧或按基线显式覆盖：

| Suite | 工具调用 | 输入 token | 输出 token |
| --- | ---: | ---: | ---: |
| Trigger | 12 | 250,000 | 8,000 |
| Capability | 32 | 1,500,000 | 20,000 |
| Regression | 64 | 1,800,000 | 20,000 |

- 任一预算超限都是确定性硬失败，直接扣 100；不能用最终答案正确掩盖无界读取。
- 输入 token 使用 Codex Trace 报告的累计输入，缓存输入单独记录但不从总量中扣除，便于跨运行比较真实上下文成本。
- `item.started` 与 `item.completed` 使用同一 `item.id` 时只计一次真实工具调用，避免事件生命周期重复消耗预算。
- scorer 把生效预算和实际 usage 写入 `report.json`；基础设施错误报告也保留同样结构。
- 被测 prompt 会声明本次门槛，并要求精确搜索、只读必要片段、停止重复读取；具体领域 Skill 仍负责定义安全的最小证据链。
- 单试次达到硬超时后，运行器会终止对应 Codex 完整进程树；Windows 不得只结束 wrapper 而留下继续占用管道的子进程。

`reg-player-source-queue` 是关键共享队列诊断，单独收紧为 12 次工具调用、600,000 输入 token 和 8,000 输出 token。60 万门槛按 challenger 的 487,159 输入 token 校准，仍相对旧五轮平均约 139 万输入 token 保留超过 50% 的压缩要求；工具门槛没有放宽。

## 稳定性门槛

- `stable identity`、标签过滤、播放队列、缓存和用户数据：默认 N=5，要求 5/5。
- 普通能力探索：默认 N=3，记录分布，不用单次通过冒充稳定。
- Apple UI：业务边界、文件范围和无障碍硬约束要求全通过；视觉质量使用 Rubric，平均分不得低于 80。
- 同一用例只要有一个 trial 失败，`stable` 就是 `false`。
- CLI、网络、模型版本和 Schema 加载错误标记为 `infrastructure_error`，不计入 Agent 平均分或通过率；修复环境后必须重跑，不能把它当作通过。

如果所有 trial 都失败，先检查用例、baseline、Schema 和 scorer，不要立即扩大 Agent prompt 或业务改动。

## 2026-07-18 运行时基线

- Codex CLI：`0.144.5`；模型：`gpt-5.6-sol`；workspace snapshot：启用。
- `router-pos-1`：1/1，100 分，0 文件改动。
- `reg-filter-semantics`：5/5，平均 100 分，`stable=true`。
- `router-pos-2`：1/1，100 分，实际 Level 3；2 次工具调用，输入 45,292、输出 984 token。
- `reg-player-source-queue`：修正为来源 filtered queue 共享边界 Level 3 后重新执行 5/5，平均 100 分，`stable=true`；每轮 10/12/10/10/10 次工具调用，累计输入 2,557,003、缓存输入 2,228,736、输出 22,363 token，平均耗时 232.991 秒。相对旧基线累计输入 6,950,585 token 下降约 63%，五轮均满足单轮预算且保持零文件改动。
- `reg-cache-zero-byte`：5/5，平均 100 分，`stable=true`。
- `reg-identity-preserve-data`：5/5，平均 100 分，`stable=true`。
- 四组关键回归均无基础设施错误和文件改动；产物位于被 Git 忽略的 `artifacts/agent_eval/20260718-*`，不提交包含真实本地 Trace 的运行目录。
- 本轮零模型成本验证确认 58 个用例、44/6/8 suite 分布、11 个 Skill 的 2 正 2 负覆盖；11 项 scorer 单元测试全部通过。

## 2026-07-19 分级结构化验证基线

- Codex CLI：`0.144.5`；模型：`gpt-5.6-terra`；`reasoning_effort=low`；workspace snapshot：启用；单试次硬超时：1200 秒。
- `reg-level1-single-agent`：5/5，平均 100 分，`stable=true`；累计输入 113,198、缓存输入 49,920、输出 5,321 token，平均耗时 131.765 秒。
- `reg-level2-validation-coverage`：5/5，平均 100 分，`stable=true`；累计输入 404,105、缓存输入 275,200、输出 14,722 token，平均耗时 158.428 秒。
- `reg-level3-validator-rejection`：5/5，平均 100 分，`stable=true`；累计输入 753,549、缓存输入 544,768、输出 14,119 token，平均耗时 164.500 秒。
- 三组均为 5 个有效试次、零基础设施错误、零真实工作树改动；产物位于 Git 忽略的 `artifacts/agent_eval/20260719-final-snapshot-*`，不提交本地 Trace。
- 零模型成本验证确认 61 个用例、44/6/11 suite 分布、11 个 Skill 的 2 正 2 负覆盖；16 项 scorer 单元测试和三个修改 Skill 的目录验证全部通过。

## 命令

先执行零模型成本的目录与评分器验证：

```powershell
python tool/agent_eval.py validate
python -m unittest discover -s test -p agent_eval_tool_test.py -v
```

运行一个关键回归用例的五次隔离试验：

```powershell
python tool/agent_eval.py run --case-id reg-filter-semantics --trials 5
```

验证分级结构化合同的三个隔离回归：

```powershell
python tool/agent_eval.py run --case-id reg-level1-single-agent --trials 5 --workspace-snapshot --model gpt-5.6-terra --reasoning-effort low --trial-timeout-seconds 1200
python tool/agent_eval.py run --case-id reg-level2-validation-coverage --trials 5 --workspace-snapshot --model gpt-5.6-terra --reasoning-effort low --trial-timeout-seconds 1200
python tool/agent_eval.py run --case-id reg-level3-validator-rejection --trials 5 --workspace-snapshot --model gpt-5.6-terra --reasoning-effort low --trial-timeout-seconds 1200
```

运行 Apple UI 能力用例并启用独立 Rubric judge：

```powershell
python tool/agent_eval.py run --case-id cap-apple-review-1 --trials 3 --judge
```

提交前需要测量当前 challenger 时，显式添加 `--workspace-snapshot`。运行器只复制 Git 未忽略的改动到临时克隆并创建临时基线提交；使用前先检查 `git status`，避免把无关未跟踪文件带入被测上下文：

```powershell
python tool/agent_eval.py run --case-id router-pos-1 --trials 1 --workspace-snapshot
```

汇总已有运行目录：

```powershell
python tool/agent_eval.py summarize artifacts/agent_eval/<timestamp>
```

`run` 必须显式指定 `--case-id` 或 `--suite`，避免无意启动大量模型调用。运行器用 `git clone --local --no-hardlinks` 创建临时隔离仓库，并以 `read-only` sandbox 执行被测 Agent；真实工作树不作为试验场。

## 基线与晋级

1. 人工确认用例 prompt、期望 Skill、Level、文件范围和 scorer。
2. 保存首次 N 次运行的 `summary.json` 作为 baseline。
3. 修改 Agent、Skill、prompt、trigger 或 harness 后，只重跑受影响能力集和完整回归集。
4. Capability 达到稳定门槛后进入 Regression，原回归用例不得删除。
5. 把模型、Codex 版本、用例版本、平均分、trial 分布、延迟和 token 一起记录到 `CURRENT_TASK.md` 或对应 Chat 文档。

本基线的方法分层参考腾讯技术工程文章[《AI Agent & Skill 测评方案及落地实践》](https://mp.weixin.qq.com/s/PUbGqheJhFMmb6hGj1ZtOw)，并按本项目的 Flutter Windows、用户数据和隔离执行约束收敛。
