# Local Tag Player 技能生态对抗式审计报告

审计日期：2026-07-31

审计对象：项目级 Skill、规则、提示词、工作流、自动化脚本、Agent 评测、配置与相关工程文档

审计方式：静态资产扫描、调用关系检索、Git 演化分析、零模型成本评测、依赖检查、权威资料对照

## 1. 最终裁决

```text
PROJECT_STATUS: TECH_DEBT_ACCUMULATION
```

这些资产既不是“全部有用”，也不是“全部应删”。

- 仍在推动项目进化的核心资产：11 个领域 Skill、Agent 评测工具及用例、发布门禁、平台边界文档、少数可重复 QA 脚本。
- 已开始拖累项目的资产：失去“当前状态”边界的 `CURRENT_TASK.md`、全量 Level 3 启动规则、重复的 Agent 入口文件、乱码元数据、无调用的松散提示文件、未进入 CI 的评测、重复率高且硬编码本机路径的 QA 脚本、混在活跃区的历史实验文档。
- 不需要架构重置：产品核心、数据边界和大多数领域 Skill 的方向正确；问题集中在 Agent 治理层的分层、生命周期和自动验证，而不是播放器业务架构本身。

一句话结论：

> Local Tag Player 的技能生态曾经显著提升执行一致性，现在则呈现“核心仍有效、外围治理债快速累积”的状态；如果不治理，新增规则会继续降低而不是提高 Agent 的有效决策能力。

## 2. 第一性原理与审计边界

```text
Product goal protected:
  Tag-driven local video discovery player。

Core loop part protected:
  扫描 -> 标签 -> 分组筛选 -> filtered queue -> 播放 -> 标签维护 -> 缓存诊断。

Must not change:
  schema、FilterQuery / TagQueryService 语义、filtered queue、
  PlayerBackend、缓存失效规则、用户数据和既有功能可达性。

Smallest safe change:
  本轮只新增证据型审计报告，不直接删除或重写被审资产。

Fewest safe tokens:
  以目录、调用关系和高风险文件为路由；历史文件只做元数据和精确证据抽样。
```

本次纳入 180 个治理相关资产：

- 179 个被 Git 跟踪的项目规则、Skill、文档、脚本、工作流、锁文件及平台环境配置；
- 1 个本机存在但被 `.gitignore` 排除的 `.codex/config.toml`，纳入风险审查，不把它误认为仓库可复现配置。

未把业务源码逐文件纳入评分；只通过精确调用检索判断治理资产是否被代码、测试、工作流或文档消费。Git 的“最近修改”表示该路径最近一次提交日期，不等于内容最近验证日期。

## 3. 可量化发现

### 3.1 上下文预算已经失衡

使用 `o200k_base` 对固定 Level 3 启动材料计数：

| 文件 | 约 tokens | 约行数 | 角色是否适合全量启动读取 |
|---|---:|---:|---|
| `AGENTS.md` | 5,541 | 596 | 部分适合，过长 |
| `PROJECT.md` | 1,589 | - | 部分适合 |
| `CURRENT_TASK.md` | 46,172 | 1,686 | 不适合，已混入历史 |
| `ARCHITECTURE.md` | 33,436 | 1,330 | 不适合每次全读 |
| `ROADMAP.md` | 13,428 | 926 | 不适合每次全读 |
| `CHANGELOG.md` | 81,877 | 2,739 | 只应按需查询 |
| **合计** | **182,043** | - | **已占 272k 配置窗口的 66.9%** |

这还没有包括系统提示、用户任务、相关 Chat 文档、私有计划和源文件；实际 Level 3 会越过项目自己规定的 70% 交接阈值。

按文件声明职责做保守“有效信号”提取：

- `AGENTS.md`、`PROJECT.md` 全量计入；
- `CURRENT_TASK.md` 只计最近三项、稳定状态、阻塞和下一步；
- `ARCHITECTURE.md` 只计当前 canonical contract 与最新 delta；
- `ROADMAP.md` 只计当前优先级；
- 启动时不计 `CHANGELOG.md`。

估算得到：

```text
有效信息比例 = 29,702 / 182,043 = 16.3%
```

这不是模型准确率，而是按文档自身职责计算的“启动上下文信号率”。即使阈值上下浮动，结论也不会改变：绝大多数固定启动 token 是历史、重复或本应按需检索的材料。

### 3.2 `CURRENT_TASK.md` 已发生可复现的治理回归

提交 `781b24f`（2026-07-21，`拆分当前任务活跃区与历史归档`）曾把该文件收缩到约 38 行，并明确只保留当前任务、最近三项、稳定状态、阻塞和下一步。

到 2026-07-30：

- 文件达到约 1,686 行；
- 体积约 161 KB；
- 相比瘦身后的版本约增长 40 倍；
- 再次容纳大量已完成记录和多段历史“活跃任务”。

因此它不是“将来可能膨胀”，而是已经证明：只靠文字约束，无法维持当前状态文件的生命周期边界。

### 3.3 规则语义重复明显

在 `AGENTS.md`、启动入口、Agent harness 和 Skill 中进行精确主题计数：

| 主题 | 出现次数 | 涉及文件数 |
|---|---:|---:|
| Level 1 | 18 | 6 |
| Level 2 | 15 | 9 |
| Level 3 | 30 | 12 |
| `FilterQuery` | 17 | 7 |
| `TagQueryService` | 17 | 7 |
| filtered queue | 13 | 6 |
| 当前任务读取 | 15 | 9 |
| context / 上下文 | 36 | 16 |
| 对抗式审查 | 11 | 7 |

重复并不都错误：领域 Skill 应重申自己的边界。但同一套 Level、读取范围、验证和交接规则同时存在于全局规则、启动文件、harness、模板和 Skill，已经形成多源事实。

### 3.4 自动验证有效，但没有进入交付闭环

本地零模型成本验证：

```text
python tool/agent_eval.py validate
PASS: 62 cases
  trigger: 44
  capability: 6
  regression: 12

python -m unittest discover -s test -p agent_eval_tool_test.py -v
PASS: 17 tests
```

这证明评测资产不是“无人使用的摆设”。但两个 GitHub Actions 工作流都没有运行这些零成本门禁，因此 Skill、prompt、Agent 规则的回归仍可直接进入主分支。

### 3.5 配置和脚本存在可移植性问题

- `.codex/config.toml` 把 `model_context_window` 和自动压缩阈值都硬编码为 `272000`，与 70% 交接规则冲突，也可能在模型变化后过时。
- 同一配置把绝对路径 `E:\LocalTagPlayer` 加入 `writable_roots`；在 clone/worktree 中会把原始仓库额外暴露为可写根，且无法复现。
- `docs/AGENT_SKILL_INSTALL.md` 和 Apple UI Skill 的 `agents/openai.yaml` 已出现实际乱码。
- 至少四个播放器压力/矩阵脚本硬编码 `E:\flutter\bin\flutter.bat`；一个脚本默认使用当前不存在的 `X:\test-media`。
- 多个实验脚本的标准化非注释行与其它脚本重合超过 50%，最高约 84%，说明它们更适合成为参数化 runner 的薄清单，而不是独立复制实现。

### 3.6 依赖并非失效，但已有升级债

`flutter pub outdated --no-dev-dependencies` 显示：

- `file_picker`：当前 `8.3.7`，最新稳定版 `11.0.2`；
- `package_info_plus`：当前 `9.0.1`，可解析/最新 `10.2.1`；
- 另有多个可升级的传递依赖。

这不构成立即跨大版本升级的理由，但说明 `pubspec.yaml` 需要单独的兼容性升级批次和回归矩阵，不能长期只依赖发布前偶然发现。

## 4. 权威实践对照

### 4.1 采用的权威证据

1. [OpenAI：Custom instructions 与 Skills](https://learn.chatgpt.com/docs/customization/overview)

   官方建议让 `AGENTS.md` 保持精简，把可复用工作流做成按需加载的 Skill；Skill 通过元数据、`SKILL.md`、引用/脚本逐层披露。Local Tag Player 的 Skill 方向正确，但全局规则和启动材料没有保持“小而稳定”。

2. [OpenAI：Codex 配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)

   未显式设置上下文窗口时可使用模型默认值；`writable_roots` 是附加可写根。由此判断本机绝对路径和固定窗口值属于脆弱配置，而不是必要项目资产。

3. [Anthropic：Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)

   建议从最简单可组合方案开始，仅在收益明确时增加复杂度，并警惕框架抽象带来的调试成本。Local Tag Player 当前的主要风险正是治理层复杂度增长快于自动收益证明。

4. [Anthropic：Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

   强调上下文是有限资源，应保留最小高信号 token、减少重叠工具，并通过即时检索和压缩管理长任务。该实践直接反对把 `CHANGELOG.md` 和完整架构历史作为每次 Level 3 的固定前缀。

5. [Liu 等：Lost in the Middle，TACL 2024](https://aclanthology.org/2024.tacl-1.9/)

   研究显示长上下文性能会随相关信息位置而显著变化，信息位于中间时尤其容易退化。它否定了“窗口装得下就应全部装入”的假设。

6. [SWE-agent：Agent-Computer Interfaces Enable Automated Software Engineering，2024](https://arxiv.org/abs/2405.15793)

   论文表明 Agent-Computer Interface 的设计会显著影响软件工程 Agent 的表现。这支持保留 Local Tag Player 的任务路由、日志筛选和评测工具，但要求把入口做得更清晰、可执行、可测。

7. [GitHub：Copilot 自定义指令](https://docs.github.com/en/copilot/concepts/prompting/response-customization)

   推荐使用短、独立、路径相关的指令并避免冲突。项目应把 Flutter UI、SQLite、播放器后端规则下沉到最接近代码或对应 Skill，而不是继续增长根级规则。

8. [GitHub：Copilot CLI 自定义方式比较](https://docs.github.com/en/enterprise-cloud@latest/copilot/concepts/agents/copilot-cli/comparing-cli-features)

   官方指出单一工作流优先用 Skill，过大或过于具体的通用指令会干扰其它任务。该结论支持删除松散 prompt，保留单一职责 Skill。

9. [GitHub：Actions 安全使用参考](https://docs.github.com/en/actions/reference/security/secure-use)

   对第三方 Action 使用完整提交 SHA 能降低供应链漂移风险。当前工作流使用 `@v2`、`@v3`、`@v7`、`@v8` 和 `@stable` 等移动引用，需要配合 Dependabot 或固定 SHA。

10. [OpenAI：Evaluation flywheel](https://developers.openai.com/cookbook/examples/evaluation/building_resilient_prompts_using_an_evaluation_flywheel#next-steps)

    建议把 grader 集成进 CI/CD，并持续收集生产失败模式。项目已有良好 eval 雏形，但尚未完成 CI 闭环。

### 4.2 当前方案与行业实践

| 维度 | Local Tag Player | 权威实践 | 差距 |
|---|---|---|---|
| 根级规则 | 596 行，混合产品、上下文、编码、QA、Git、事故处理 | 小而稳定，只放跨任务长期约束 | 高 |
| Skill | 11 个，领域划分总体清楚 | 单一职责、渐进披露、低重叠 | 低至中 |
| 当前状态 | 1,687 行，历史重新回流 | 短状态 + 历史归档 + 自动预算 | 高 |
| 长文档加载 | Level 3 固定读取约 182k tokens | 即时检索、按段加载、压缩 | 高 |
| Prompt 来源 | AGENTS、CLAUDE、bootstrap、harness、松散模板并存 | 单一事实源 + 路径作用域 | 高 |
| Agent eval | 62 用例、17 工具测试，本地可运行 | 进入 CI/CD，故障样本持续增长 | 中 |
| 工作流供应链 | Action 使用移动 tag | 完整 SHA 或自动可信更新 | 中高 |
| QA 脚本 | 覆盖广，但复制、硬编码、状态不清 | 参数化 runner + manifest + 可重现环境 | 高 |
| 历史证据 | 很丰富，但活跃/归档混杂 | immutable archive + 短索引 | 中高 |
| 业务架构治理 | 边界和事故规则较强 | 用自动测试保护不变量 | 中 |

## 5. 评分规则

每项 0–25 分：

- 创新价值：是否提供项目特有、难以替代的能力；
- 当前有效性：是否仍被调用、验证并符合当前架构；
- 维护成本：**25 表示低成本/易维护，0 表示高成本**；
- 未来兼容：是否适应新模型、worktree、平台和项目阶段。

总分解释：

```text
0–39   严重拖累：DELETE / ARCHIVE / 立即修复
40–59  需要重构：MODIFY / MERGE
60–79  保留优化：KEEP + 改进
80–100 核心资产：KEEP
```

“ARCHIVE”不表示内容错误，而表示它是证据或历史，不应继续出现在默认执行面。

## 6. 逐文件资产清单与裁决

### 6.1 根级规则、配置、发布资产

| 文件 | 类型/当前作用 | 调用者 | 最近修改 | 分数 | 风险 | 裁决 |
|---|---|---|---|---:|---|---|
| `AGENTS.md` | 全局 Agent 规则 | 所有 Agent | 2026-07-23 | 53 | 高：过长、多职责 | MODIFY |
| `PROJECT.md` | 产品与项目入口 | Level 2/3 Agent | 2026-07-29 | 56 | 中：混入 Agent 流程及未解析占位符 | MODIFY |
| `CURRENT_TASK.md` | 当前状态 | Level 2/3 Agent | 2026-07-30 | 30 | 严重：40 倍回膨胀 | MODIFY |
| `ARCHITECTURE.md` | canonical 架构与演化记录 | Level 3 Agent/维护者 | 2026-07-30 | 66 | 高：当前契约与历史混合 | MODIFY |
| `ROADMAP.md` | 优先级与阶段 | Level 3/按需 | 2026-07-30 | 61 | 中高：完成历史过多 | MODIFY |
| `CHANGELOG.md` | 全量变更历史 | 发布/按需查询 | 2026-07-30 | 59 | 高：81k tokens 不应启动全读 | ARCHIVE/SPLIT |
| `NEW_CHAT_BOOTSTRAP.md` | 最短任务路由入口 | 新会话 | 2026-07-18 | 85 | 低 | KEEP |
| `CLAUDE.md` | 其它 Agent 兼容入口 | Claude 类工具 | 2026-07-08 | 42 | 中高：复制规则并可能漂移 | MERGE |
| `SKILLS_SUMMARY.md` | 手工 Skill 清单 | 无可靠调用 | 2026-07-08 | 22 | 高：漏掉 Apple UI Skill | DELETE |
| `.codex/config.toml` | 本机 Codex 配置 | 当前开发机，未跟踪 | 本机状态 | 45 | 高：绝对路径、固定窗口、策略冲突 | MODIFY |
| `.gitignore` | 忽略生成物、媒体和秘密 | Git | 当前仓库 | 86 | 低 | KEEP |
| `.metadata` | Flutter 项目元数据 | Flutter 工具 | 当前仓库 | 83 | 低 | KEEP |
| `analysis_options.yaml` | Dart lint 配置 | analyzer/CI | 2026-07-04 | 83 | 低 | KEEP |
| `pubspec.yaml` | Flutter 依赖与项目配置 | Flutter | 2026-07-30 | 69 | 中：大版本升级债 | MODIFY |
| `pubspec.lock` | 可复现依赖锁 | Flutter/CI | 当前仓库 | 81 | 低 | KEEP |
| `README.md` | 用户/贡献入口 | 用户、开发者 | 当前仓库 | 85 | 低 | KEEP |
| `INSTALL.md` | 安装说明 | 用户、发布 | 当前仓库 | 82 | 低 | KEEP |
| `CODE_SIGNING_POLICY.md` | 签名边界 | 发布流程 | 当前仓库 | 88 | 低 | KEEP |
| `LICENSE` | 法律许可 | 分发 | 当前仓库 | 96 | 低 | KEEP |
| `THIRD_PARTY_NOTICES.md` | 第三方声明 | 分发 | 当前仓库 | 94 | 低 | KEEP |
| `packaging/README.md` | 打包入口 | 维护者 | 当前仓库 | 80 | 低 | KEEP |
| `packaging/macos/package_notarized.sh` | macOS 签名/公证 | 发布维护者 | 当前仓库 | 79 | 中：需在 macOS CI 验证 | KEEP |
| `packaging/windows/local_tag_player.iss` | Windows 安装器 | release workflow | 当前仓库 | 86 | 低 | KEEP |
| `packaging/windows/sign_release.ps1` | Windows 签名 | release workflow | 当前仓库 | 87 | 低 | KEEP |
| `test/fixtures/legacy_interaction_manifest.json` | 兼容回归 fixture | 测试 | 当前仓库 | 88 | 低 | KEEP |

### 6.2 Skill 与提示资产

| 文件 | 当前作用/调用者 | 分数 | 风险 | 裁决 |
|---|---|---:|---|---|
| `.agents/skills/ltp-task-router/SKILL.md` | Level/模式路由；新任务 | 86 | 中：Level 3 仍导向全量材料 | KEEP/MODIFY |
| `.agents/skills/ltp-small-fix/SKILL.md` | 小修复最小上下文 | 88 | 低 | KEEP |
| `.agents/skills/ltp-log-triage/SKILL.md` | 大日志关键片段排查 | 91 | 低 | KEEP |
| `.agents/skills/ltp-session-handoff/SKILL.md` | 长会话压缩与移交 | 84 | 中：阈值与本机 compact 配置冲突 | KEEP/MODIFY |
| `.agents/skills/ltp-tag-filter-data/SKILL.md` | 标签数据/过滤语义 | 90 | 低 | KEEP |
| `.agents/skills/ltp-media-library-tag-ui/SKILL.md` | 媒体库标签发现 UI | 88 | 低 | KEEP |
| `.agents/skills/ltp-player-filter-queue/SKILL.md` | filtered playback queue | 91 | 低 | KEEP |
| `.agents/skills/ltp-cache-diagnostics/SKILL.md` | 缓存、FFmpeg、诊断 | 89 | 低 | KEEP |
| `.agents/skills/ltp-stable-identity-missing-relink/SKILL.md` | stable identity/missing/relink | 90 | 低 | KEEP |
| `.agents/skills/ltp-tag-manager-batch-tagging/SKILL.md` | 标签维护和批量打标 | 87 | 低 | KEEP |
| `.agents/skills/ltp-apple-ui-design/SKILL.md` | 显式 Apple UI 覆盖层 | 78 | 中：体积较大但触发边界清楚 | MODIFY |
| `.agents/skills/ltp-apple-ui-design/references/apple-ui-foundations.md` | Apple 视觉原则 | 76 | 中：需注明验证日期/适用版本 | KEEP/MODIFY |
| `.agents/skills/ltp-apple-ui-design/references/motion-craft.md` | 动效实现参考 | 75 | 中 | KEEP/MODIFY |
| `.agents/skills/ltp-apple-ui-design/references/motion-vocabulary.md` | 动效词汇 | 74 | 中 | KEEP/MODIFY |
| `.agents/skills/ltp-apple-ui-design/agents/openai.yaml` | Skill UI 元数据 | 28 | 高：中文字段已乱码 | MODIFY |
| `.agents/skills/context_policy.md` | 松散上下文规则 | 27 | 高：不被发现为 Skill，重复 AGENTS | DELETE |
| `.agents/skills/prompt_template.md` | 松散任务模板 | 34 | 中高：无调用、重复 bootstrap/harness | MERGE 后 DELETE |

所有 `SKILL.md` 最近集中修改于 2026-07-18 至 2026-07-23；它们不是陈旧资产。真正的问题是缺少 CI 触发评测，而不是 Skill 数量本身。

### 6.3 Agent harness 与评测

| 文件 | 当前作用/调用者 | 分数 | 风险 | 裁决 |
|---|---|---:|---|---|
| `docs/agent_harness.md` | Agent 执行合同与模式 | 58 | 高：与 AGENTS/Skill 重复 | MODIFY |
| `docs/agent_eval.md` | 评测方法、结果与运行记录 | 72 | 中：方法和历史基线混合 | SPLIT |
| `tool/agent_eval.py` | 目录验证、运行与评分 | 90 | 中：1080 行但已有 17 个测试 | KEEP |
| `test/agent_eval_tool_test.py` | 评测工具单元测试 | 91 | 低 | KEEP |
| `evals/agent/trigger_cases.json` | Skill 正/负触发用例 | 89 | 低 | KEEP |
| `evals/agent/capability_cases.json` | 能力结果用例 | 84 | 中：样本仍偏少 | KEEP/MODIFY |
| `evals/agent/regression_cases.json` | 事故回归，只增不删 | 91 | 低 | KEEP |
| `evals/agent/rubrics/apple_ui.json` | UI Skill judge rubric | 82 | 中：只有一个领域有 rubric | KEEP/MODIFY |
| `evals/agent/schemas/agent_result.schema.json` | Agent 输出 schema | 86 | 低 | KEEP |
| `evals/agent/schemas/judge_result.schema.json` | Judge 输出 schema | 86 | 低 | KEEP |

### 6.4 GitHub 工作流

| 文件 | 当前作用/调用者 | 最近修改 | 分数 | 风险 | 裁决 |
|---|---|---|---:|---|---|
| `.github/workflows/desktop-cross-platform.yml` | 桌面跨平台 build/test | 2026-07-25 | 63 | 高：无 PR 触发、无 Agent eval、移动 Action tag | MODIFY |
| `.github/workflows/release-packages.yml` | tag/手工发布、签名与包验证 | 2026-07-30 | 69 | 中高：移动 Action tag；发布时才跑完整门禁 | MODIFY |

### 6.5 自动化脚本

| 文件 | 当前作用 | 主要调用者 | 分数 | 裁决 |
|---|---|---|---:|---|
| `scripts/qa/main_window_stress_semantic.mjs` | 主窗口语义压力测试 | 文档/应用 smoke key | 88 | KEEP |
| `tool/check_release_branch_integration.ps1` | 发布分支集成门禁 | release workflow | 89 | KEEP |
| `tool/check_release_notes_preview.ps1` | 发布说明预览门禁 | release workflow | 88 | KEEP |
| `tool/verify_windows_debug_package.ps1` | Windows 包验证 | release/维护者 | 85 | KEEP |
| `tool/manage_stress_artifacts.ps1` | marker 保护的压力产物管理 | 多个压力脚本 | 82 | KEEP |
| `tool/generate_player_quality_samples.ps1` | 生成质量基线样本 | QA runner | 77 | KEEP/MODIFY |
| `tool/generate_nvofa_motion_stress_samples.ps1` | 生成 NVOFA 样本 | NVOFA 实验 | 64 | ARCHIVE |
| `tool/summarize_library_add_remove_stress.ps1` | 汇总库增删压力结果 | 对应压力脚本 | 76 | KEEP/MODIFY |
| `tool/summarize_player_stress_metrics.ps1` | 汇总播放器压力结果 | 多个压力脚本 | 80 | KEEP |
| `tool/benchmark_thumbnail_gpu_paths.ps1` | 缩略图 GPU 路径基准 | 按需 QA | 72 | KEEP/MODIFY |
| `tool/run_gpu_capability_matrix.ps1` | GPU 能力矩阵 | QA 文档 | 75 | KEEP/MODIFY |
| `tool/run_downscale_quality_ab.ps1` | 质量 A/B 通用实现 | 多个质量 wrapper | 82 | KEEP，作为统一 runner |
| `tool/run_fixed_quality_baseline.ps1` | 固定质量基线 | QA 文档 | 71 | MERGE |
| `tool/run_natural_compression_quality_ab.ps1` | 自然压缩 A/B | QA 文档 | 65 | MERGE |
| `tool/run_compression_quality_ab.ps1` | 压缩实验 | 无可靠外部调用 | 38 | ARCHIVE |
| `tool/run_hdr_mapping_visual_qa.ps1` | HDR mapping 视觉实验 | 无可靠外部调用 | 38 | ARCHIVE |
| `tool/run_native_output_size_ab.ps1` | 输出尺寸 wrapper | `run_downscale_quality_ab` | 43 | MERGE 后 DELETE |
| `tool/run_texture_sampling_ab.ps1` | 纹理采样 wrapper | `run_downscale_quality_ab` | 41 | MERGE 后 DELETE |
| `tool/run_player_queue_visual_qa.ps1` | 队列视觉实验 | 无可靠外部调用 | 39 | ARCHIVE |
| `tool/run_library_add_remove_player_stress.ps1` | 库增删+播放压力 | 手工；硬编码本机路径 | 48 | MODIFY/MERGE |
| `tool/run_player_real_library_stress.ps1` | 真实媒体库压力 | 手工；硬编码 Flutter | 52 | MODIFY/MERGE |
| `tool/run_player_backend_stability_matrix.ps1` | 后端稳定矩阵 | QA 文档；硬编码 Flutter | 61 | MODIFY |
| `tool/run_mpv_hwnd_d3d11_probe.ps1` | mpv HWND/D3D11 探针 | 实验 QA | 60 | ARCHIVE |
| `tool/build_local_video_plugin_probe.ps1` | 本地视频插件探针 | 实验 QA | 56 | ARCHIVE |
| `tool/run_nvidia_scaling_ab.ps1` | NVIDIA scaling A/B | 实验 QA | 58 | MERGE/ARCHIVE |
| `tool/run_nvidia_true_hdr_ab.ps1` | NVIDIA HDR A/B | 实验 QA | 58 | MERGE/ARCHIVE |
| `tool/run_nvidia_vsr_hdr_ab.ps1` | VSR/HDR wrapper | NVIDIA 实验 | 45 | MERGE 后 ARCHIVE |
| `tool/run_nvofa_driver_probe.ps1` | NVOFA driver 探针 | 实验 QA | 55 | ARCHIVE |
| `tool/run_nvofa_execute_probe.ps1` | NVOFA execute 探针 | 实验 QA | 57 | ARCHIVE |
| `tool/run_nvofa_motion_ab.ps1` | NVOFA motion A/B | 实验 QA | 58 | ARCHIVE |
| `tool/run_nvofa_vapoursynth_interpolation_probe.ps1` | VapourSynth/NVOFA 探针 | 实验 QA | 52 | ARCHIVE |
| `tool/run_vapoursynth_motion_host_probe.ps1` | motion host 探针 | 实验 QA | 51 | ARCHIVE |
| `tool/run_vapoursynth_real_frame_probe.ps1` | real frame 探针 | 实验 QA | 52 | ARCHIVE |
| `tool/vapoursynth_nvofa_interpolation.vpy` | NVOFA VapourSynth 脚本 | 对应 probe | 57 | ARCHIVE |
| `tool/vapoursynth_passthrough_probe.vpy` | VapourSynth passthrough | 对应 probe | 58 | ARCHIVE |

脚本归档前必须先建立 manifest，记录命令、输入、最后成功环境、对应结论和替代 runner；不能仅凭“无直接字符串调用”立即物理删除，因为部分脚本是人工实验入口。

### 6.6 文档资产

以下分组列出每一个文件；组内每个文件继承该行的类型、调用模式、风险和分数。

| 文件或文件组 | 当前作用/调用者 | 分数 | 风险 | 裁决 |
|---|---|---:|---|---|
| `docs/AGENT_SKILL_INSTALL.md` | Skill 安装说明；人工 | 24 | 高：全文乱码、内容已被 repo 自动发现替代 | DELETE |
| `docs/NEW_CHAT_BOOTSTRAP.md` | 旧路径兼容跳转 | 64 | 中：长期双入口 | ARCHIVE，保留一次迁移提示 |
| `docs/RELEASE_NOTES_0.2.0.md`、`docs/RELEASE_NOTES_0.2.3.md`、`docs/RELEASE_NOTES_0.2.4.md` | 不可变发布记录；用户/发布 | 90 | 低 | KEEP |
| `docs/architecture/ADR_001_PROGRESSIVE_ARCHITECTURE_MIGRATION.md` | 决策记录 | 89 | 低 | KEEP |
| `docs/architecture/ARCHITECTURE_COMPLETION_2026_07_29.md` | 完成证据 | 72 | 中：不应作为当前契约 | ARCHIVE |
| `docs/architecture/ARCHITECTURE_REFACTOR_2026_07_29.md` | 已执行重构计划 | 63 | 中 | ARCHIVE |
| `docs/architecture/CODE_DEVELOPMENT_STANDARDS_2026_07_29.md` | 开发规范 | 58 | 高：与 AGENTS 重复 | MERGE |
| `docs/architecture/LIBRARY_REPOSITORY_AFFINITY_2026_07_29.md` | repository 归属边界 | 83 | 低 | KEEP |
| `docs/chat_tasks/CHAT_1_ARCHITECTURE.md` | 阶段历史/领域 Skill 按需引用 | 65 | 中 | SPLIT 当前合同后 ARCHIVE 历史 |
| `docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md` | 阶段历史/领域 Skill 按需引用 | 66 | 中 | SPLIT/ARCHIVE |
| `docs/chat_tasks/CHAT_3_MEDIA_LIBRARY_TAG_UI.md` | 阶段历史/领域 Skill 按需引用 | 68 | 中 | SPLIT/ARCHIVE |
| `docs/chat_tasks/CHAT_4_PLAYER.md` | 1,487 行播放器阶段历史 | 48 | 高：超大且被 Skill 引用 | SPLIT/ARCHIVE |
| `docs/chat_tasks/CHAT_5_THUMBNAIL_DIAGNOSTICS.md` | 阶段历史/领域 Skill 按需引用 | 67 | 中 | SPLIT/ARCHIVE |
| `docs/chat_tasks/CHAT_6_TAG_MANAGER.md` | 阶段历史/领域 Skill 按需引用 | 67 | 中 | SPLIT/ARCHIVE |
| `docs/chat_tasks/CHAT_7_MAIN_UI_SMOKE_2026_07_08.md` | UI smoke 证据 | 65 | 中 | ARCHIVE |
| `docs/chat_tasks/CHAT_7_RESPONSIVE_UI.md` | UI 阶段历史 | 66 | 中 | SPLIT/ARCHIVE |
| `docs/design/APPLE_UI_MIGRATION.md` | Apple UI 蓝图，Skill 引用 | 71 | 中：完成/待办状态混合 | MODIFY |
| `docs/media_kit_2_windows_experiment_20260724.md` | 一次性实验记录 | 55 | 中 | ARCHIVE |
| `docs/qa/NVIDIA_VSR_HDR_GATE.md` | 当前 NVIDIA 功能门禁 | 82 | 低 | KEEP |
| `docs/qa/main_window_latency_smoke.md` | 可重复主窗口门禁 | 84 | 低 | KEEP |
| `docs/qa/main_window_semantic_stress_gate.md` | 可重复语义压力门禁 | 86 | 低 | KEEP |
| `docs/qa/windows_hardware_decode_matrix.md` | 当前硬解兼容矩阵 | 80 | 中：需注明最近验证日期 | KEEP/MODIFY |
| `docs/qa/dependency_audit_20260727.md` | 依赖审计快照 | 72 | 中：会随依赖变化 | ARCHIVE |
| `docs/qa/library_add_remove_player_stress_20260714.md` | 压力测试证据 | 72 | 中 | ARCHIVE |
| `docs/qa/library_scan_playback_coordination_20260715.md` | 协调测试证据 | 74 | 中 | ARCHIVE |
| `docs/qa/adversarial_full_app_stress_20260728.md` | 全应用压力证据 | 76 | 中 | ARCHIVE |
| `docs/qa/player_backend_stability_matrix_20260728.md` | 后端矩阵结果 | 76 | 中 | ARCHIVE，保留短当前矩阵 |
| `docs/qa/player_backend_windows_comparison_plan_20260728.md` | 已完成/过长计划 | 44 | 高 | ARCHIVE |
| `docs/qa/player_gpu_capability_matrix_20260722.md` | GPU 能力快照 | 72 | 中 | ARCHIVE |
| `docs/qa/player_hdr_sdr_baseline_20260722.md` | HDR/SDR 基线 | 73 | 中 | ARCHIVE |
| `docs/qa/player_quality_baseline_20260722.md` | 质量基线 | 75 | 中 | ARCHIVE，当前摘要进 gate |
| `docs/qa/professional_player_feature_research_20260727.md` | 专业播放器研究 | 39 | 高：与产品非目标相冲突 | ARCHIVE |
| `docs/qa/rtx_video_sdk_feasibility_20260727.md` | RTX 可行性实验 | 55 | 中 | ARCHIVE |
| `docs/task_history/CURRENT_TASK_HISTORY_THROUGH_2026-07-19.md` | 正确的历史归档 | 88 | 低：不在默认读取链 | KEEP/ARCHIVE |

下列 23 个 2026-07-27 至 2026-07-30 的实验/结果文档，逐文件评分 60，统一裁决为 `ARCHIVE`；它们有证据价值，但不应占据活跃执行面：

```text
docs/qa/angle_d3d11_interop_20260727.md
docs/qa/child_hwnd_airspace_20260727.md
docs/qa/media_kit_libmpv_facade_20260728.md
docs/qa/mpv_hwnd_overlay_region_20260728.md
docs/qa/mpv_nvidia_native_d3d11_20260727.md
docs/qa/mpv_nvidia_scaling_isolated_20260727.md
docs/qa/mpv_nvidia_true_hdr_20260728.md
docs/qa/nvidia_auto_activation_20260728.md
docs/qa/nvidia_vsr_daily_ab_20260728.md
docs/qa/nvofa_cuda_execute_20260728.md
docs/qa/nvofa_vapoursynth_interpolation_20260728.md
docs/qa/player_backend_selection_nvidia_auto_20260728.md
docs/qa/player_downscale_quality_ab_20260730.md
docs/qa/player_fvp_same_method_windows_ab_20260729.md
docs/qa/player_native_output_size_gate_20260730.md
docs/qa/player_natural_compression_ab_20260727.md
docs/qa/player_project_learning_and_fvp_windows_probe_20260728.md
docs/qa/player_smooth_motion_20260727.md
docs/qa/player_texture_sampling_ab_20260730.md
docs/qa/vapoursynth_motion_runtime_20260728.md
docs/qa/vapoursynth_r78_real_frames_nvofa_20260728.md
docs/qa/windows_hwnd_lifecycle_zero_copy_boundary_20260728.md
docs/qa/windows_renderer_preference_20260727.md
```

### 6.7 平台与环境配置

以下配置是 Flutter/CMake/Rust 平台构建输入，有明确工具调用，不应因“很少人工编辑”误删。

| 文件组（每项均已纳入） | 当前作用/调用者 | 分数 | 风险 | 裁决 |
|---|---|---:|---|---|
| `linux/CMakeLists.txt`、`linux/flutter/CMakeLists.txt`、`linux/runner/CMakeLists.txt` | Linux 构建；CMake/Flutter | 82 | 低 | KEEP |
| `windows/CMakeLists.txt`、`windows/flutter/CMakeLists.txt`、`windows/runner/CMakeLists.txt` | Windows 构建；CMake/Flutter | 84 | 低 | KEEP |
| `windows/native_player/CMakeLists.txt` | 原生播放器构建 | 87 | 中：关键平台边界 | KEEP |
| `windows/rust_library_scan/Cargo.toml`、`Cargo.lock` | Rust 扫描器依赖/锁 | 87 | 低 | KEEP |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` | macOS 图标清单 | 82 | 低 | KEEP |
| `macos/Flutter/Flutter-Debug.xcconfig`、`macos/Flutter/Flutter-Release.xcconfig` | Flutter macOS 构建配置 | 84 | 低 | KEEP |
| `macos/Runner/Configs/AppInfo.xcconfig`、`macos/Runner/Configs/Debug.xcconfig`、`macos/Runner/Configs/Release.xcconfig`、`macos/Runner/Configs/Warnings.xcconfig` | Xcode 构建配置 | 84 | 低 | KEEP |
| `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist`、`macos/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | Xcode workspace 元数据 | 78 | 低 | KEEP |
| `macos/Runner/Info.plist`、`macos/Runner/DebugProfile.entitlements`、`macos/Runner/Release.entitlements` | macOS 权限/应用配置 | 88 | 中：安全敏感 | KEEP |
| `windows/runner/Runner.rc`、`windows/runner/runner.exe.manifest` | Windows 资源/运行时清单 | 86 | 低 | KEEP |
| `.gitignore`、`linux/.gitignore`、`macos/.gitignore`、`windows/.gitignore`、`windows/rust_library_scan/.gitignore` | 平台生成物隔离 | 84 | 低 | KEEP |
| `windows/native_player/README.md`、`windows/runner/NATIVE_PLAYER.md`、`windows/native_player/THIRD_PARTY_NOTICES.md` | 原生边界/许可 | 86 | 低 | KEEP |
| `windows/rust_library_scan/Cargo.lock`、`windows/rust_library_scan/README.md` | Rust 扫描器锁文件/说明 | 84 | 低 | KEEP |
| `windows/tools/ffmpeg/bin/README.md` | FFmpeg 放置与边界说明 | 83 | 低 | KEEP |

## 7. 隐藏问题

### 7.1 过度工程化

项目不是因为“有 11 个 Skill”而过度工程化。11 个 Skill 基本对应真实边界，且总正文约 5.2k tokens，远小于固定 Level 3 文档。

过度工程化发生在外围：

- 同一执行规则有 4–6 个文字入口；
- 事故规则不断追加到根级提示，却没有等量转成确定性测试；
- 一周内产生大量 GPU/播放器实验脚本和结果文档，但缺少生命周期状态；
- QA wrapper 复制实现，而不是由 manifest 声明参数；
- 配置同时采用模型窗口硬编码和人工 70% 阈值。

这属于“治理复杂度超过可验证收益”，不是业务抽象层本身过多。

### 7.2 Agent 效率下降路径

```text
规则增长
  -> 固定启动材料增长
  -> 相关证据被历史稀释
  -> Agent 为确认优先级继续读取更多文件
  -> 执行前 token 与决策时间增长
  -> 任务中途更早压缩/交接
  -> 新的交接和事故规则再次进入文档
```

具体表现：

- token 浪费：Level 3 固定材料约 182k；
- 上下文污染：`CHANGELOG`、已完成 QA、历史“当前任务”混入当前决策；
- 决策变慢：同一约束在根规则、Skill、harness、Chat 文档间核对；
- 执行路径变长：为了遵守读取规则，Agent 在真正检查相关源码前已经接近交接阈值；
- 错误安全感：文字要求“必须真实点击”不能替代能在 CI 失败的可达性测试。

### 7.3 项目阶段判断

```text
阶段：C — 复杂系统阶段，但仍承受快速迭代压力
```

依据：

- 已有 SQLite、stable identity、多个播放器后端、C++/Rust 平台边界；
- 有跨平台构建、签名、发布、回归和大媒体库性能要求；
- 用户数据、队列、缓存、硬解和 UI 可达性之间存在真实耦合；
- 最近提交密集，仍不是纯维护期。

因此不应回到“少规则、随意试错”的 A 阶段，也不应继续用更多 prose 解决复杂性。正确方向是：**减少默认文字约束，增加自动不变量、按需上下文和可复现门禁。**

## 8. 删除、合并、归档与保留清单

### 8.1 DELETE

1. 文件：`SKILLS_SUMMARY.md`

   原因：手工清单已漏项，repo-scoped Skill 可自动发现。

   影响：无运行时功能下降；减少一个漂移源。

   替代：由目录验证自动生成 Skill 索引。

2. 文件：`.agents/skills/context_policy.md`

   原因：不是合法 Skill、无调用、重复根规则。

   影响：无能力下降。

   替代：保留压缩后的 `AGENTS.md` 单一上下文政策。

3. 文件：`docs/AGENT_SKILL_INSTALL.md`

   原因：内容乱码，且项目内安装说明已不适用于当前 repo 自动发现。

   影响：不影响项目内 Agent。

   替代：在 `README` 的贡献部分保留一行 repo Skill 位置说明。

4. 合并验证后删除：`.agents/skills/prompt_template.md`、`tool/run_native_output_size_ab.ps1`、`tool/run_texture_sampling_ab.ps1`。

   原因：前者无调用；后两者与通用 runner 高度重复。

   影响：必须先用 manifest 保留等价参数入口。

   替代：`NEW_CHAT_BOOTSTRAP.md` + 参数化 `tool/qa/run_quality.ps1`。

### 8.2 MODIFY / MERGE

| 优先级 | 文件 | 当前问题 | 建议结构 |
|---|---|---|---|
| P0 | `CURRENT_TASK.md` | 当前/历史混合，回膨胀 40 倍 | 强制上限 120 行；只留当前、最近三项、阻塞、下一步；CI 检查 |
| P0 | `AGENTS.md` | 596 行、多职责、多处重复 | 收缩为产品边界、数据安全、路由、验证原则；领域细节下沉 Skill |
| P0 | `.codex/config.toml` | 绝对路径、窗口硬编码、阈值冲突 | 删除附加仓库根；使用模型默认窗口；compact 留安全余量 |
| P0 | `.../agents/openai.yaml` | 乱码未被 eval 捕获 | 修复 UTF-8；给 validator 增加解码及中文字段断言 |
| P0 | GitHub workflows | Agent eval 不进 CI、无 PR 门禁 | PR 运行零成本 eval/单测；Action 固定 SHA 或 Dependabot |
| P1 | `ARCHITECTURE.md` | 当前契约与迁移史混合 | `current-contract.md` + `adr/` + `history/` |
| P1 | `ROADMAP.md` | 完成史过多 | 只保留未来 1–2 个里程碑；完成项归档 |
| P1 | `CHANGELOG.md` | 单文件 81k tokens | 按版本/年份拆分；根文件只索引和未发布内容 |
| P1 | `PROJECT.md` | 产品信息与 Agent 流程混合 | 只保留定位、技术栈、运行入口；移除重复程序规则 |
| P1 | `CLAUDE.md` | 双事实源 | 缩成指向 `AGENTS.md` 和 bootstrap 的兼容入口 |
| P1 | `docs/agent_harness.md` | 重复 Level/规则 | 只保留可执行合同、模式差异和命令 |
| P1 | QA 脚本 | 复制、硬编码、状态不清 | 三个 runner + 一个 manifest；从 PATH 发现 Flutter |
| P2 | Chat/QA 文档 | 证据丰富但无生命周期 | current contract 与 dated evidence 分离 |
| P2 | `pubspec.yaml` | 两个主要包跨大版本落后 | 单独升级批次、平台矩阵验证，不与治理重构混做 |

### 8.3 ARCHIVE

- 已完成的架构重构计划和 completion report；
- 2026-07-27 至 2026-07-30 的 GPU、mpv、NVOFA、VapourSynth 一次性实验；
- “professional player”功能研究，避免与项目定位争夺优先级；
- 已完成的 Chat 阶段叙事和过长播放器比较计划；
- 无当前调用、依赖特定本机环境的实验脚本。

归档不是随意搬目录。每个归档项必须保留：

```text
status
last_verified
environment
conclusion
replacement
related_commit
```

### 8.4 核心资产

| 文件/资产 | 为什么重要 | 未来作用 |
|---|---|---|
| 领域 `ltp-*` Skill | 把标签、队列、缓存、身份边界按需注入 | 继续作为渐进披露核心 |
| `tool/agent_eval.py` + `evals/agent` | 已有可运行、可扩展的防回归机制 | 接入 PR 门禁，承接事故规则 |
| `NEW_CHAT_BOOTSTRAP.md` | 足够短的任务入口 | 成为唯一人类可见路由 |
| release workflow 与签名脚本 | 直接保护可交付包 | 固定供应链版本、保留包验证 |
| ADR、repository affinity、平台边界文档 | 记录不可从代码轻易推断的决策 | 作为按需架构证据 |
| semantic stress 与稳定门禁 | 能验证真实交互语义 | 继续从 prose 转向 executable guard |

## 9. 推荐目录结构

不建议为了“看起来整齐”移动 Flutter 业务源码。只重构 Agent 治理面：

```text
LocalTagPlayer/
├── AGENTS.md                         # <= 250 行的长期硬规则
├── NEW_CHAT_BOOTSTRAP.md             # 唯一会话入口
├── .agents/
│   └── skills/
│       └── ltp-*/                    # 单一职责、渐进披露
├── docs/
│   ├── current/
│   │   ├── CURRENT_TASK.md           # <= 120 行
│   │   ├── ARCHITECTURE_CONTRACT.md
│   │   └── ROADMAP.md
│   ├── adr/
│   ├── gates/                        # 仍在执行的 QA 门禁
│   ├── history/
│   │   ├── task/
│   │   ├── chat/
│   │   ├── qa/2026-07/
│   │   └── changelog/
│   └── audits/
├── evals/
│   └── agent/
├── tool/
│   ├── agent_eval.py
│   └── qa/
│       ├── manifest.yaml
│       ├── run_quality.ps1
│       ├── run_player_stress.ps1
│       └── run_native_probe.ps1
└── .github/workflows/
```

关键不是目录名，而是四种生命周期必须分离：

```text
长期硬规则 != 当前状态 != 可执行门禁 != 历史证据
```

## 10. 建议实施顺序

### 第 1 周：停止继续恶化

1. 给 `CURRENT_TASK.md` 增加 120 行/12k 字符预算门禁。
2. 修复两个乱码文件，并给 `agent_eval.py` 加 UTF-8/元数据验证。
3. 在 PR workflow 中运行现有 62 个目录用例和 17 个单元测试。
4. 删除 `.codex/config.toml` 的绝对 `writable_roots` 和模型窗口硬编码。

### 第 2–3 周：缩短默认上下文

1. 把 `AGENTS.md` 收缩到 200–250 行。
2. 将 `CURRENT_TASK`、架构 current contract、路线图放入 `docs/current`。
3. 让 Level 3 从“读完整六大文档”改为“读 current contract + 精确 ADR/历史片段”。
4. 缩短 `CLAUDE.md` 和 harness，删除无调用模板。

### 第 4–6 周：脚本和历史治理

1. 创建 QA manifest，记录 owner/status/environment/last_verified。
2. 合并质量、压力、原生探针脚本族。
3. 把完成实验迁移到 dated archive，保留结论索引。
4. 为第三方 Actions 建立完整 SHA 固定与自动更新。

### 后续衡量指标

```text
Level 3 默认上下文目标：< 45k tokens
CURRENT_TASK 目标：< 120 行，最近三项
根级 Agent 规则目标：< 250 行
Agent 零成本门禁：每个 PR 必跑
乱码/无 frontmatter Skill 元数据：0
QA 脚本绝对本机路径：0
无状态实验资产：0
```

## 11. 对抗式复核

```text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved
prompt impact: 报告主张缩短默认上下文，不增加新的运行时强制提示
protected behaviors: preserved
unauthorized feature removal: none
mount and reachability: 不适用；本轮仅新增审计文档
validation:
  - Agent 目录验证 62/62 通过
  - agent_eval 工具单测 17/17 通过
  - 依赖过时检查已完成
  - 业务代码、schema、UI 未修改，因此未运行 Flutter build/真实点击
```

反方检验：

- “规则越多越安全”不成立：当前最严重的 `CURRENT_TASK` 回归发生在已有明确瘦身规则之后，说明缺少的是自动门禁。
- “文件无人直接调用就应删除”不成立：人工 QA/动态发现资产可能没有静态字符串 caller，因此实验脚本只先归档和建 manifest。
- “长上下文窗口足以容纳全部材料”不成立：固定材料已占本机配置窗口 66.9%，且权威研究显示位置和信号密度仍影响利用效果。
- “应直接重置架构”不成立：领域 Skill、评测、发布和平台边界都有可验证价值；治理层可以渐进重构。

## 12. 下一步计划

下一项最小、收益最高且可独立交付的任务应是：

> 建立“治理预算门禁”补丁：修复乱码，给 `CURRENT_TASK.md`、`AGENTS.md` 和 Skill 元数据增加零成本验证，并把现有 Agent eval 接入 PR workflow；暂不移动历史文件、不修改业务代码。

该补丁完成并验证后，再进行文档分层和 QA runner 合并，避免一次大搬迁同时改变路径、规则和执行行为。
