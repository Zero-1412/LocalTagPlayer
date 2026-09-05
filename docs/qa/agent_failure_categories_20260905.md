# 2026-09-05 · Agent 失败诊断分类

## 本次范围

在现有 summary 增加 failure_diagnostics，不替换评分或晋级逻辑。
false_completion 只比较用例明确预期与实际状态：completed 对 blocked/failed 才计入。
missing_validation 只检查用例必需验证记录的缺失，不声称记录中的命令已实际运行。
没有配置必需记录、字段未知及基础设施错误不算已评估的零失败。
错误恢复保持 not_determined，重复探索保持 requires_trace_review，仍有目标缺口。

## 验证证据

- 37项工具单测：包括scorer→summary接线、状态反方向不误判、缺记录、旧报告、
  基础设施失败、非法状态字段及零必需记录边界；原评分与稳定性结果保持。
- validate通过，日志 `.local/agent_failure_diagnostics_validate.log`。
- 五份真实历史报告只读汇总：两类均assessed=0、unassessed=5，未把缺少证据算零失败。
  新汇总位于 `.local/agent_failures_historical_summary.json`，未改历史原始报告。
- 独立只读复核通过；额外AST探针覆盖3×3状态、非法计数/列表、空报告及正文不导出，
  非阻塞建议已补为持久测试。真实新旧N=5尚未运行，不声明改善或晋级。

## 边界

schema、过滤、来源播放队列、缩略图/媒体队列及用户数据不变。未扩大prompt、Skill
或读取预算。新字段是诊断而非新的确定性评分规则；现场执行真伪和错误恢复仍需额外证据。
