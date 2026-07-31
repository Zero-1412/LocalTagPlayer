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


def _structured_result(
    *,
    selected_skills: list[str] | None = None,
    validation_mode: str = "structured",
    validation_status: str = "passed",
    validation_method: str = "deterministic",
    evidence: str = "fixture evidence",
    promotion_decision: str = "promoted",
) -> dict:
    """构造满足结构合同的最小结果，避免评分测试被无关字段干扰。"""

    return {
        "status": "completed",
        "task_level": "2",
        "selected_skills": selected_skills or [],
        "task_contract": {
            "goal": "验证 scorer",
            "scope": "测试 fixture",
            "non_goals": [],
            "done_when": [
                {
                    "id": "req-1",
                    "assertion": "fixture 完成项被覆盖",
                    "required": True,
                }
            ],
            "deliverable": "结构化测试结果",
        },
        "validation_mode": validation_mode,
        "summary": "fixture summary",
        "changed_files": [],
        "validation": [
            {
                "requirement_id": "req-1",
                "status": validation_status,
                "method": validation_method,
                "evidence": evidence,
            }
        ],
        "promotion_decision": promotion_decision,
        "safety": {
            "schema": "unchanged",
            "filter_query": "unchanged",
            "filtered_queue": "unchanged",
            "cache_queue": "unchanged",
            "user_data": "preserved",
        },
    }


class AgentEvalToolTest(unittest.TestCase):
    """验证目录结构、扣分规则、Trace 归一化和 N 次汇总。"""

    def _write_governance_fixture(
        self,
        root: Path,
        *,
        skill_text: str = (
            "---\n"
            "name: ltp-fixture\n"
            "description: 测试用 Skill。\n"
            "---\n"
        ),
        metadata_text: str | None = None,
        max_lines: int = 10,
    ) -> tuple[Path, Path]:
        """构造最小治理目录，便于确定性验证编码、元数据和预算。"""

        skill_dir = root / ".agents" / "skills" / "ltp-fixture"
        skill_dir.mkdir(parents=True)
        (skill_dir / "SKILL.md").write_text(skill_text, encoding="utf-8")
        if metadata_text is not None:
            metadata_dir = skill_dir / "agents"
            metadata_dir.mkdir()
            (metadata_dir / "openai.yaml").write_text(
                metadata_text,
                encoding="utf-8",
            )
        (root / "AGENTS.md").write_text("# fixture\n", encoding="utf-8")
        eval_root = root / "evals" / "agent"
        eval_root.mkdir(parents=True)
        (eval_root / "governance_budget.json").write_text(
            json.dumps(
                {
                    "files": {
                        "AGENTS.md": {
                            "max_lines": max_lines,
                            "max_chars": 100,
                        }
                    }
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        manifest_dir = root / "tool" / "qa"
        manifest_dir.mkdir(parents=True)
        (manifest_dir / "manifest.json").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "entries": [],
                }
            ),
            encoding="utf-8",
        )
        return skill_dir, eval_root

    def test_catalog_has_expected_coverage(self) -> None:
        """目录必须覆盖 11 个 Skill 的 44 个触发用例及能力/回归用例。"""

        summary = agent_eval.validate_catalog()
        self.assertEqual(63, summary["case_count"])
        self.assertEqual(44, summary["suite_counts"]["trigger"])
        self.assertEqual(13, summary["suite_counts"]["regression"])
        self.assertEqual(11, len(summary["skill_trigger_coverage"]))
        self.assertEqual(11, len(summary["governance"]["skills"]))
        self.assertLessEqual(
            summary["governance"]["budgets"]["CURRENT_TASK.md"]["lines"],
            120,
        )
        for coverage in summary["skill_trigger_coverage"].values():
            self.assertGreaterEqual(coverage["positive"], 2)
            self.assertGreaterEqual(coverage["negative"], 2)

    def test_governance_rejects_non_utf8_skill(self) -> None:
        """Skill 文本无法按 UTF-8 解码时必须给出确定性失败。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            skill_dir, eval_root = self._write_governance_fixture(root)
            (skill_dir / "SKILL.md").write_bytes(b"\xff\xfe\x00")
            with self.assertRaisesRegex(agent_eval.EvalError, "UTF-8"):
                agent_eval.validate_repository_governance(root, eval_root)

    def test_governance_rejects_mojibake_metadata(self) -> None:
        """Agent UI 元数据包含典型乱码标记时不得通过目录验证。"""

        metadata = (
            "interface:\n"
            '  display_name: "Fixture"\n'
            '  short_description: "ä¸º测试提供能力"\n'
            '  default_prompt: "使用 $ltp-fixture。"\n'
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            _, eval_root = self._write_governance_fixture(
                root,
                metadata_text=metadata,
            )
            with self.assertRaisesRegex(agent_eval.EvalError, "疑似乱码"):
                agent_eval.validate_repository_governance(root, eval_root)

    def test_governance_rejects_loose_skill_markdown(self) -> None:
        """Skill 根目录的松散 Markdown 不得绕过渐进披露和 frontmatter。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            _, eval_root = self._write_governance_fixture(root)
            (root / ".agents" / "skills" / "prompt.md").write_text(
                "loose",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(agent_eval.EvalError, "松散 Markdown"):
                agent_eval.validate_repository_governance(root, eval_root)

    def test_governance_rejects_context_budget_growth(self) -> None:
        """默认上下文文件超过预算时必须阻断验证。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            _, eval_root = self._write_governance_fixture(root, max_lines=1)
            (root / "AGENTS.md").write_text(
                "# fixture\nsecond line\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(agent_eval.EvalError, "超过预算"):
                agent_eval.validate_repository_governance(root, eval_root)

    def test_governance_rejects_uncatalogued_qa_script(self) -> None:
        """新增 QA 脚本没有生命周期条目时必须阻断治理验证。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            _, eval_root = self._write_governance_fixture(root)
            tool_dir = root / "tool"
            (tool_dir / "uncatalogued.ps1").write_text(
                "Write-Output 'fixture'\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(agent_eval.EvalError, "漏登记脚本"):
                agent_eval.validate_repository_governance(root, eval_root)

    def test_governance_rejects_missing_qa_evidence(self) -> None:
        """QA 条目的证据文件缺失时不得留下表面有效的清单记录。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            _, eval_root = self._write_governance_fixture(root)
            script_path = root / "tool" / "fixture.ps1"
            script_path.write_text(
                "Write-Output 'fixture'\n",
                encoding="utf-8",
            )
            manifest_path = root / "tool" / "qa" / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "entries": [
                            {
                                "id": "fixture",
                                "path": "tool/fixture.ps1",
                                "status": "active",
                                "kind": "fixture",
                                "last_verified": "2026-07-31",
                                "evidence": "docs/missing.md",
                                "replacement": None,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(agent_eval.EvalError, "证据路径不存在"):
                agent_eval.validate_repository_governance(root, eval_root)

    def test_governance_rejects_floating_action_reference(self) -> None:
        """第三方 GitHub Action 使用浮动标签时必须阻断供应链治理。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            _, eval_root = self._write_governance_fixture(root)
            workflow_dir = root / ".github" / "workflows"
            workflow_dir.mkdir(parents=True)
            (workflow_dir / "fixture.yml").write_text(
                "steps:\n  - uses: actions/checkout@v7\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(agent_eval.EvalError, "完整提交"):
                agent_eval.validate_repository_governance(root, eval_root)

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
        result = _structured_result()
        report = agent_eval.score_result(case, result, [], [])
        self.assertFalse(report["passed"])
        self.assertEqual(60, report["score"])

    def test_required_validation_record_is_a_hard_gate(self) -> None:
        """生产事故用例必须按指定完成项、状态和验证方法收口。"""

        case = {
            "id": "fixture-required-validation-record",
            "suite": "regression",
            "category": "safety",
            "expected": {
                "status": "completed",
                "required_validation_records": {
                    "req-1": {
                        "status": "failed",
                        "method": "deterministic",
                    }
                },
            },
        }

        mismatched = _structured_result()
        failed_report = agent_eval.score_result(case, mismatched, [], [])
        self.assertFalse(failed_report["passed"])
        self.assertEqual(0, failed_report["score"])
        self.assertEqual(
            "required_validation_record_mismatch",
            failed_report["deductions"][0]["code"],
        )

        matched = _structured_result(
            validation_status="failed",
            promotion_decision="not_promoted",
        )
        passed_report = agent_eval.score_result(case, matched, [], [])
        self.assertTrue(passed_report["passed"])
        self.assertEqual(100, passed_report["score"])

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
        result = _structured_result()
        report = agent_eval.score_result(case, result, ["lib/src/app.dart"], [])
        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])

    def test_tool_call_budget_is_a_hard_gate(self) -> None:
        """工具调用超过单用例预算时必须直接失败并记录实际使用量。"""

        case = {
            "id": "fixture-tool-budget",
            "suite": "regression",
            "category": "efficiency",
            "budgets": {"max_tool_calls": 2},
            "expected": {"status": "completed"},
        }
        result = _structured_result()
        trace = [
            {"event": "tool_call", "tool": "command_execution"},
            {"event": "tool_call", "tool": "command_execution"},
            {"event": "tool_call", "tool": "command_execution"},
            {
                "event": "usage",
                "input_tokens": 100,
                "cached_input_tokens": 40,
                "output_tokens": 20,
            },
        ]

        report = agent_eval.score_result(case, result, [], trace)

        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])
        self.assertEqual(
            "tool_call_budget_exceeded",
            report["deductions"][0]["code"],
        )
        self.assertEqual(3, len(report["observed"]["tool_calls"]))

    def test_token_budget_is_a_hard_gate(self) -> None:
        """累计输入或输出 token 超限时必须成为可比较的确定性失败。"""

        case = {
            "id": "fixture-token-budget",
            "suite": "regression",
            "category": "efficiency",
            "budgets": {
                "max_input_tokens": 100,
                "max_output_tokens": 50,
            },
            "expected": {"status": "completed"},
        }
        result = _structured_result()
        trace = [
            {
                "event": "usage",
                "input_tokens": 101,
                "cached_input_tokens": 80,
                "output_tokens": 51,
            }
        ]

        report = agent_eval.score_result(case, result, [], trace)
        codes = {item["code"] for item in report["deductions"]}

        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])
        self.assertEqual(
            {"input_token_budget_exceeded", "output_token_budget_exceeded"},
            codes,
        )
        self.assertEqual(101, report["observed"]["usage"]["input_tokens"])

    def test_validation_must_cover_every_done_when_item(self) -> None:
        """完成项没有一一映射到验证记录时必须硬失败。"""

        case = {
            "id": "fixture-validation-coverage",
            "suite": "regression",
            "category": "safety",
            "expected": {"status": "completed"},
        }
        result = _structured_result()
        result["task_contract"]["done_when"].append(
            {
                "id": "req-2",
                "assertion": "第二个完成项也被覆盖",
                "required": True,
            }
        )

        report = agent_eval.score_result(case, result, [], [])

        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])
        self.assertEqual(
            "structured_validation_invalid",
            report["deductions"][0]["code"],
        )

    def test_passed_validation_requires_evidence(self) -> None:
        """passed 记录没有具体证据时不得通过。"""

        case = {
            "id": "fixture-validation-evidence",
            "suite": "regression",
            "category": "safety",
            "expected": {"status": "completed"},
        }
        result = _structured_result(evidence="")

        report = agent_eval.score_result(case, result, [], [])

        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])

    def test_failed_requirement_rejects_promotion(self) -> None:
        """必选完成项失败时不得把 challenger 晋级。"""

        case = {
            "id": "fixture-promotion-conflict",
            "suite": "regression",
            "category": "safety",
            "expected": {"status": "completed"},
        }
        result = _structured_result(
            validation_status="failed",
            evidence="fixture failure",
            promotion_decision="promoted",
        )

        report = agent_eval.score_result(case, result, [], [])

        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])

    def test_single_agent_cannot_claim_independent_validation(self) -> None:
        """Level 1 单 Agent 模式不得伪装成独立验证。"""

        case = {
            "id": "fixture-single-agent",
            "suite": "regression",
            "category": "safety",
            "expected": {
                "status": "completed",
                "validation_mode": "single_agent",
            },
        }
        result = _structured_result(
            validation_mode="single_agent",
            validation_method="independent",
        )

        report = agent_eval.score_result(case, result, [], [])

        self.assertFalse(report["passed"])
        self.assertEqual(0, report["score"])

    def test_independent_mode_requires_independent_record(self) -> None:
        """独立验证模式必须至少包含一条独立验证证据。"""

        case = {
            "id": "fixture-independent",
            "suite": "regression",
            "category": "safety",
            "expected": {
                "status": "completed",
                "validation_mode": "independent",
            },
        }
        result = _structured_result(validation_mode="independent")

        report = agent_eval.score_result(case, result, [], [])

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

    def test_trace_counts_started_and_completed_as_one_tool_call(self) -> None:
        """同一 Codex item 的 started/completed 事件不得重复消耗工具预算。"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            raw = root / "raw.jsonl"
            normalized = root / "trace.jsonl"
            events = [
                {
                    "type": "item.started",
                    "item": {
                        "id": "item-1",
                        "type": "command_execution",
                        "command": "rg sourcePlaylist lib/src",
                    },
                },
                {
                    "type": "item.completed",
                    "item": {
                        "id": "item-1",
                        "type": "command_execution",
                        "command": "rg sourcePlaylist lib/src",
                    },
                },
            ]
            raw.write_text(
                "".join(json.dumps(event) + "\n" for event in events),
                encoding="utf-8",
            )

            result = agent_eval._normalize_raw_trace(raw, normalized)
            tool_events = [event for event in result if event["event"] == "tool_call"]

            self.assertEqual(1, len(tool_events))
            self.assertEqual("item-1", tool_events[0]["call_id"])

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

    def test_trace_redacts_nested_paths_before_home(self) -> None:
        """CI 仓库位于用户目录下时仍必须保留 repo/隔离路径占位语义。"""

        original_repo_root = agent_eval.REPO_ROOT
        nested_repo = Path.home() / "work" / "LocalTagPlayer"
        isolated = nested_repo / ".local" / "isolated"
        try:
            agent_eval.REPO_ROOT = nested_repo
            redacted = agent_eval._redact_text(
                f"home={Path.home()} repo={nested_repo} temp={isolated}",
                (isolated,),
            )
        finally:
            agent_eval.REPO_ROOT = original_repo_root

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
