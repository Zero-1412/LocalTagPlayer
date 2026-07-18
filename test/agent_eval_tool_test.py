"""Agent Eval 工具的确定性单元测试。"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "tool" / "agent_eval.py"
SPEC = importlib.util.spec_from_file_location("ltp_agent_eval", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("无法加载 tool/agent_eval.py")
agent_eval = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(agent_eval)


class AgentEvalToolTest(unittest.TestCase):
    """验证目录结构、扣分规则、Trace 归一化和 N 次汇总。"""

    def test_catalog_has_expected_coverage(self) -> None:
        """目录必须覆盖 11 个 Skill 的 44 个触发用例及能力/回归用例。"""

        summary = agent_eval.validate_catalog()
        self.assertEqual(58, summary["case_count"])
        self.assertEqual(44, summary["suite_counts"]["trigger"])
        self.assertEqual(11, len(summary["skill_trigger_coverage"]))
        for coverage in summary["skill_trigger_coverage"].values():
            self.assertGreaterEqual(coverage["positive"], 2)
            self.assertGreaterEqual(coverage["negative"], 2)

    def test_agent_result_schema_uses_supported_subset(self) -> None:
        """Codex Structured Outputs Schema 不得包含服务端拒绝的 uniqueItems。"""

        schema_path = agent_eval.EVAL_ROOT / "schemas" / "agent_result.schema.json"
        schema_text = schema_path.read_text(encoding="utf-8")
        self.assertNotIn('"uniqueItems"', schema_text)

    def test_missing_required_skill_fails(self) -> None:
        """没有触发必需 Skill 时必须低于 80 分通过线。"""

        case = {
            "id": "fixture-missing-skill",
            "suite": "regression",
            "category": "trigger_positive",
            "expected": {
                "status": "completed",
                "required_skills": ["ltp-tag-filter-data"],
                "changed_files": [],
            },
        }
        result = {
            "status": "completed",
            "selected_skills": [],
        }
        report = agent_eval.score_result(case, result, [], [])
        self.assertFalse(report["passed"])
        self.assertEqual(60, report["score"])

    def test_forbidden_file_change_is_hard_failure(self) -> None:
        """命中禁止文件 glob 时必须直接得到零分。"""

        case = {
            "id": "fixture-forbidden-change",
            "suite": "capability",
            "category": "safety",
            "expected": {
                "status": "completed",
                "forbidden_changed_globs": ["lib/**"],
            },
        }
        result = {
            "status": "completed",
            "selected_skills": [],
        }
        report = agent_eval.score_result(case, result, ["lib/src/app.dart"], [])
        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])

    def test_trace_normalization_extracts_tool_call(self) -> None:
        """Codex command_execution 事件必须进入规范化 tool_call Trace。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            raw = root / "raw.jsonl"
            normalized = root / "trace.jsonl"
            raw.write_text(
                json.dumps(
                    {
                        "type": "item.completed",
                        "item": {
                            "type": "command_execution",
                            "command": "git status --short",
                        },
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            events = agent_eval._normalize_raw_trace(raw, normalized)
            tool_events = [event for event in events if event["event"] == "tool_call"]
            self.assertEqual("command_execution", tool_events[0]["tool"])
            self.assertTrue(normalized.exists())

    def test_trace_redacts_local_paths(self) -> None:
        """Trace 写入前必须遮盖用户目录、真实仓库和隔离克隆路径。"""

        isolated = Path("C:/temp/ltp-agent-eval/repo")
        text = f"home={Path.home()} repo={agent_eval.REPO_ROOT} temp={isolated}"
        redacted = agent_eval._redact_text(text, (isolated,))
        self.assertNotIn(str(Path.home()), redacted)
        self.assertNotIn(str(agent_eval.REPO_ROOT), redacted)
        self.assertNotIn(str(isolated), redacted)
        self.assertIn("<USER_HOME>", redacted)
        self.assertIn("<REPO_ROOT>", redacted)
        self.assertIn("<ISOLATED_REPO>", redacted)

    def test_n_trial_summary_requires_all_pass(self) -> None:
        """同一用例任意一次失败时，稳定性字段必须为 false。"""

        reports = [
            {
                "case_id": "fixture-n",
                "suite": "regression",
                "score": 100,
                "passed": True,
                "evaluated": True,
                "duration_seconds": 1,
            },
            {
                "case_id": "fixture-n",
                "suite": "regression",
                "score": 60,
                "passed": False,
                "evaluated": True,
                "duration_seconds": 2,
            },
        ]
        summary = agent_eval.summarize_reports(reports)
        self.assertFalse(summary["cases"][0]["stable"])
        self.assertEqual(1, summary["suites"]["regression"]["passed_trials"])

    def test_infrastructure_error_is_not_scored_as_agent_failure(self) -> None:
        """CLI 或模型错误必须排除出 Agent 平均分和试验通过率分母。"""

        reports = [
            {
                "case_id": "fixture-infra",
                "suite": "trigger",
                "score": None,
                "passed": False,
                "evaluated": False,
                "outcome": "infrastructure_error",
                "duration_seconds": 3,
            }
        ]
        summary = agent_eval.summarize_reports(reports)
        case = summary["cases"][0]
        self.assertEqual(1, case["infrastructure_errors"])
        self.assertEqual(0, case["evaluated_trials"])
        self.assertIsNone(case["average_score"])


if __name__ == "__main__":
    unittest.main()
