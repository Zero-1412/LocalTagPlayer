#!/usr/bin/env python3
"""Local Tag Player Agent/Skill Eval 的隔离运行、评分与汇总工具。"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
EVAL_ROOT = REPO_ROOT / "evals" / "agent"
RESULT_SCHEMA = EVAL_ROOT / "schemas" / "agent_result.schema.json"
JUDGE_SCHEMA = EVAL_ROOT / "schemas" / "judge_result.schema.json"
PASS_THRESHOLD = 80


class EvalError(RuntimeError):
    """表示用例、运行环境或被测结果不满足 Eval 前置条件。"""


def _read_json(path: Path) -> dict[str, Any]:
    """读取一个 UTF-8 JSON 对象，并在结构错误时给出明确文件位置。"""

    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvalError(f"无法读取 JSON：{path}: {error}") from error
    if not isinstance(value, dict):
        raise EvalError(f"JSON 顶层必须是对象：{path}")
    return value


def _write_json(path: Path, value: Any) -> None:
    """以稳定格式写入 JSON，便于代码审查和基线比较。"""

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _redact_text(text: str, extra_paths: Iterable[Path] = ()) -> str:
    """遮盖用户目录、真实仓库和临时克隆绝对路径，避免 Trace 泄露本地位置。"""

    replacements = [
        (Path.home(), "<USER_HOME>"),
        (REPO_ROOT, "<REPO_ROOT>"),
        *((path, "<ISOLATED_REPO>") for path in extra_paths),
    ]
    redacted = text
    for path, placeholder in replacements:
        for candidate in {str(path), str(path).replace("\\", "/")}:
            redacted = redacted.replace(candidate, placeholder)
    return redacted


def _redact_value(value: Any, extra_paths: Iterable[Path] = ()) -> Any:
    """递归遮盖结构化结果中的绝对路径，同时保持 JSON 类型不变。"""

    if isinstance(value, str):
        return _redact_text(value, extra_paths)
    if isinstance(value, list):
        return [_redact_value(item, extra_paths) for item in value]
    if isinstance(value, dict):
        return {key: _redact_value(item, extra_paths) for key, item in value.items()}
    return value


def _append_jsonl(path: Path, event: dict[str, Any]) -> None:
    """向规范化 Trace 追加单个事件，保持一行一个 JSON 对象。"""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")


def load_cases(eval_root: Path = EVAL_ROOT) -> dict[str, dict[str, Any]]:
    """加载 trigger、capability 和 regression 三类逻辑用例。"""

    cases: dict[str, dict[str, Any]] = {}
    trigger_document = _read_json(eval_root / "trigger_cases.json")
    for skill in trigger_document.get("skills", []):
        skill_name = skill.get("name")
        if not isinstance(skill_name, str) or not skill_name:
            raise EvalError("trigger_cases.json 存在没有 name 的 skill")
        for polarity in ("positive", "negative"):
            for raw_case in skill.get(polarity, []):
                case = {
                    **raw_case,
                    "suite": "trigger",
                    "category": f"trigger_{polarity}",
                    "trials": 1,
                    "expected": {
                        "status": "completed",
                        "changed_files": [],
                        (
                            "required_skills"
                            if polarity == "positive"
                            else "forbidden_skills"
                        ): [skill_name],
                    },
                }
                _register_case(cases, case)

    for filename in ("capability_cases.json", "regression_cases.json"):
        document = _read_json(eval_root / filename)
        suite = document.get("suite")
        for raw_case in document.get("cases", []):
            _register_case(cases, {**raw_case, "suite": suite})
    return cases


def _register_case(
    cases: dict[str, dict[str, Any]], case: dict[str, Any]
) -> None:
    """注册单个用例，并拒绝重复或缺少必要字段的定义。"""

    case_id = case.get("id")
    if not isinstance(case_id, str) or not case_id:
        raise EvalError("Eval 用例必须包含非空 id")
    if case_id in cases:
        raise EvalError(f"Eval 用例 id 重复：{case_id}")
    if not isinstance(case.get("prompt"), str) or not case["prompt"].strip():
        raise EvalError(f"Eval 用例缺少 prompt：{case_id}")
    if not isinstance(case.get("expected"), dict):
        raise EvalError(f"Eval 用例缺少 expected：{case_id}")
    trials = case.get("trials", 1)
    if not isinstance(trials, int) or trials < 1:
        raise EvalError(f"Eval 用例 trials 必须是正整数：{case_id}")
    cases[case_id] = case


def validate_catalog(eval_root: Path = EVAL_ROOT) -> dict[str, Any]:
    """验证用例、Skill 覆盖、Schema 和 Rubric 的确定性结构。"""

    cases = load_cases(eval_root)
    trigger_document = _read_json(eval_root / "trigger_cases.json")
    skill_counts: dict[str, dict[str, int]] = {}
    for skill in trigger_document.get("skills", []):
        name = skill["name"]
        positives = len(skill.get("positive", []))
        negatives = len(skill.get("negative", []))
        if positives < 2 or negatives < 2:
            raise EvalError(f"{name} 至少需要 2 个正触发和 2 个负触发用例")
        skill_counts[name] = {"positive": positives, "negative": negatives}

    for schema_path in (
        eval_root / "schemas" / "agent_result.schema.json",
        eval_root / "schemas" / "judge_result.schema.json",
    ):
        _read_json(schema_path)

    rubrics: list[str] = []
    for rubric_path in sorted((eval_root / "rubrics").glob("*.json")):
        rubric = _read_json(rubric_path)
        weights = [item.get("weight") for item in rubric.get("criteria", [])]
        if not weights or any(not isinstance(weight, int) for weight in weights):
            raise EvalError(f"Rubric 权重必须是整数：{rubric_path}")
        if sum(weights) != 100:
            raise EvalError(f"Rubric 权重总和必须为 100：{rubric_path}")
        rubrics.append(rubric.get("name", rubric_path.stem))

    suite_counts: dict[str, int] = {}
    for case in cases.values():
        suite = str(case["suite"])
        suite_counts[suite] = suite_counts.get(suite, 0) + 1
    return {
        "case_count": len(cases),
        "suite_counts": suite_counts,
        "skill_trigger_coverage": skill_counts,
        "rubrics": rubrics,
    }


def _matches_any(path: str, patterns: Iterable[str]) -> bool:
    """使用统一的正斜杠路径判断 glob，避免 Windows 分隔符影响评分。"""

    normalized = path.replace("\\", "/")
    return any(fnmatch.fnmatch(normalized, pattern) for pattern in patterns)


def score_result(
    case: dict[str, Any],
    result: dict[str, Any],
    observed_changed_files: list[str],
    trace_events: list[dict[str, Any]],
    judge_result: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """按 100 分扣分制评价单次运行，返回可机器汇总的报告。"""

    expected = case["expected"]
    deductions: list[dict[str, Any]] = []

    def deduct(points: int, code: str, message: str) -> None:
        """记录一次可解释扣分；分数最终钳制在 0 到 100。"""

        deductions.append({"points": points, "code": code, "message": message})

    if result.get("status") != expected.get("status", "completed"):
        deduct(100, "status_mismatch", "任务完成状态与期望不一致")

    expected_level = expected.get("task_level")
    if expected_level is not None and result.get("task_level") != expected_level:
        deduct(20, "task_level_mismatch", f"期望 Level {expected_level}")

    selected = set(result.get("selected_skills", []))
    for skill in expected.get("required_skills", []):
        if skill not in selected:
            deduct(40, "missing_skill", f"缺少应触发 Skill：{skill}")
    for skill in expected.get("forbidden_skills", []):
        if skill in selected:
            deduct(40, "forbidden_skill", f"错误触发 Skill：{skill}")

    expected_changed = expected.get("changed_files")
    if expected_changed is not None and sorted(observed_changed_files) != sorted(
        expected_changed
    ):
        deduct(100, "changed_files_mismatch", "实际文件变化与期望不一致")
    forbidden_globs = expected.get("forbidden_changed_globs", [])
    forbidden_changes = [
        path for path in observed_changed_files if _matches_any(path, forbidden_globs)
    ]
    if forbidden_changes:
        deduct(
            100,
            "forbidden_file_change",
            "修改了禁止文件：" + ", ".join(forbidden_changes),
        )

    tool_names = [
        str(event.get("tool"))
        for event in trace_events
        if event.get("event") == "tool_call"
    ]
    for required_tool in expected.get("required_tools", []):
        if required_tool not in tool_names:
            deduct(15, "missing_tool", f"缺少工具调用：{required_tool}")
    for forbidden_tool in expected.get("forbidden_tools", []):
        if forbidden_tool in tool_names:
            deduct(30, "forbidden_tool", f"调用了禁止工具：{forbidden_tool}")
    required_order = expected.get("required_tool_order", [])
    if required_order and not _is_subsequence(required_order, tool_names):
        deduct(15, "tool_order", "工具调用顺序不满足用例要求")

    rubric_name = expected.get("rubric")
    if rubric_name:
        if judge_result is None:
            deduct(20, "missing_rubric_judge", "缺少 Rubric judge 结果")
        else:
            if judge_result.get("hard_failures"):
                deduct(100, "rubric_hard_failure", "Rubric judge 发现硬失败")
            judge_score = judge_result.get("total_score")
            if not isinstance(judge_score, (int, float)) or judge_score < PASS_THRESHOLD:
                deduct(30, "rubric_score", "Rubric judge 分数低于 80")

    score = max(0, 100 - sum(item["points"] for item in deductions))
    return {
        "case_id": case["id"],
        "suite": case["suite"],
        "category": case["category"],
        "score": score,
        "passed": score >= PASS_THRESHOLD,
        "evaluated": True,
        "outcome": "passed" if score >= PASS_THRESHOLD else "agent_failure",
        "threshold": PASS_THRESHOLD,
        "deductions": deductions,
        "observed": {
            "selected_skills": sorted(selected),
            "changed_files": observed_changed_files,
            "tool_calls": tool_names,
            "rubric_score": None if judge_result is None else judge_result.get("total_score"),
        },
    }


def _is_subsequence(expected: list[str], actual: list[str]) -> bool:
    """判断期望工具顺序是否为实际调用序列的子序列。"""

    iterator = iter(actual)
    return all(any(value == expected_value for value in iterator) for expected_value in expected)


def _extract_usage(value: Any) -> dict[str, int]:
    """递归汇总 Codex JSONL 中常见的 token 计数字段。"""

    totals = {"input_tokens": 0, "cached_input_tokens": 0, "output_tokens": 0}
    if isinstance(value, dict):
        for key in totals:
            candidate = value.get(key)
            if isinstance(candidate, int):
                totals[key] += candidate
        for child in value.values():
            child_totals = _extract_usage(child)
            for key in totals:
                totals[key] += child_totals[key]
    elif isinstance(value, list):
        for child in value:
            child_totals = _extract_usage(child)
            for key in totals:
                totals[key] += child_totals[key]
    return totals


def _normalize_raw_trace(raw_path: Path, trace_path: Path) -> list[dict[str, Any]]:
    """保留原始事件并抽取工具调用和 token，用稳定事件结构支持评分。"""

    normalized: list[dict[str, Any]] = []
    for index, line in enumerate(raw_path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            raw_event = json.loads(line)
        except json.JSONDecodeError:
            normalized.append(
                {"event": "invalid_raw_event", "sequence": index, "text": line}
            )
            continue
        normalized.append(
            {"event": "raw_event", "sequence": index, "payload": raw_event}
        )
        item = raw_event.get("item") if isinstance(raw_event, dict) else None
        if isinstance(item, dict):
            item_type = item.get("type")
            if item_type in {"command_execution", "mcp_tool_call", "tool_call"}:
                tool = item.get("name") or item.get("tool") or item_type
                normalized.append(
                    {
                        "event": "tool_call",
                        "sequence": index,
                        "tool": tool,
                        "arguments": item.get("arguments") or item.get("command"),
                    }
                )
    usage = _extract_usage([event.get("payload") for event in normalized])
    normalized.append({"event": "usage", **usage})
    trace_path.write_text(
        "".join(
            json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n"
            for event in normalized
        ),
        encoding="utf-8",
    )
    return normalized


def _codex_executable() -> str:
    """解析跨平台 Codex CLI 路径，Windows 优先使用不受脚本策略影响的 cmd。"""

    candidates = ["codex.cmd", "codex"] if os.name == "nt" else ["codex", "codex.cmd"]
    for candidate in candidates:
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
    raise EvalError("未找到 Codex CLI，无法执行运行时 Eval")


def _codex_version() -> str:
    """读取被测 Codex CLI 版本，便于定位模型兼容和基线漂移。"""

    completed = subprocess.run(
        [_codex_executable(), "--version"],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return completed.stdout.strip() or completed.stderr.strip() or "unknown"


def _git_changed_files(repo: Path) -> list[str]:
    """读取隔离仓库的实际文件变化，避免信任 Agent 自报的 changed_files。"""

    completed = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    paths: list[str] = []
    for line in completed.stdout.splitlines():
        if len(line) >= 4:
            paths.append(line[3:].replace("\\", "/"))
    return sorted(paths)


def _overlay_workspace_snapshot(source: Path, target: Path) -> None:
    """把当前非忽略改动覆盖到隔离克隆，并提交为被测 challenger 基线。"""

    listed = subprocess.run(
        ["git", "ls-files", "--modified", "--deleted", "--others", "--exclude-standard", "-z"],
        cwd=source,
        check=True,
        capture_output=True,
    ).stdout
    for raw_path in listed.split(b"\0"):
        if not raw_path:
            continue
        relative = raw_path.decode("utf-8")
        source_path = source / relative
        target_path = target / relative
        if source_path.is_file():
            target_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, target_path)
        elif target_path.exists():
            if target_path.is_dir():
                shutil.rmtree(target_path)
            else:
                target_path.unlink()
    subprocess.run(["git", "add", "-A"], cwd=target, check=True, capture_output=True)
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Local Tag Player Eval",
            "-c",
            "user.email=agent-eval@local.invalid",
            "commit",
            "--allow-empty",
            "-m",
            "建立隔离 challenger 快照",
        ],
        cwd=target,
        check=True,
        capture_output=True,
    )


def _build_agent_prompt(case: dict[str, Any]) -> str:
    """包装被测任务，要求输出可评分字段但不泄漏期望答案。"""

    return (
        "你正在接受 Local Tag Player Agent Eval。按仓库 AGENTS.md 和 repo skills 正常处理下列任务。"
        "不要猜测评分标准，不要读取 evals/agent 中的期望结果。最终必须按 output schema 返回；"
        "selected_skills 填写本次实际采用的 repo skill，task_level 填写实际等级。\n\n"
        f"用户任务：\n{case['prompt']}"
    )


def _run_codex(
    repo: Path,
    prompt: str,
    output_schema: Path,
    result_path: Path,
    raw_trace_path: Path,
    model: str | None,
) -> tuple[int, float, str]:
    """在隔离仓库以只读 sandbox 执行一次 Codex，并捕获完整 JSONL。"""

    command = [
        _codex_executable(),
        "exec",
        "--config",
        'service_tier="fast"',
        "--ephemeral",
        "--json",
        "--color",
        "never",
        "--sandbox",
        "read-only",
        "--output-schema",
        str(output_schema),
        "--output-last-message",
        str(result_path),
        "--cd",
        str(repo),
    ]
    if model:
        command.extend(["--model", model])
    command.append(prompt)
    started = time.monotonic()
    completed = subprocess.run(
        command,
        cwd=repo,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    elapsed = time.monotonic() - started
    raw_trace_path.write_text(
        _redact_text(completed.stdout, (repo,)), encoding="utf-8"
    )
    return completed.returncode, elapsed, _redact_text(completed.stderr, (repo,))


def _run_rubric_judge(
    repo: Path,
    rubric_name: str,
    candidate_result: dict[str, Any],
    artifact_dir: Path,
    model: str | None,
) -> dict[str, Any]:
    """用独立 Codex 回合按指定 Rubric 评价候选结果。"""

    rubric = _read_json(EVAL_ROOT / "rubrics" / f"{rubric_name}.json")
    judge_result_path = artifact_dir / "judge_result.json"
    judge_raw_trace = artifact_dir / "judge_raw_trace.jsonl"
    prompt = (
        "你是独立 Rubric judge。只根据给定 Rubric 评价候选输出，不修改文件；"
        "每个 criteria 给 0-100，total_score 必须按 weight 加权。\n\n"
        f"Rubric:\n{json.dumps(rubric, ensure_ascii=False)}\n\n"
        f"候选输出:\n{json.dumps(candidate_result, ensure_ascii=False)}"
    )
    return_code, _, stderr = _run_codex(
        repo, prompt, JUDGE_SCHEMA, judge_result_path, judge_raw_trace, model
    )
    if return_code != 0 or not judge_result_path.exists():
        raise EvalError(f"Rubric judge 失败：{stderr.strip()}")
    _normalize_raw_trace(judge_raw_trace, artifact_dir / "judge_trace.jsonl")
    judge_result = _redact_value(_read_json(judge_result_path), (repo,))
    _write_json(judge_result_path, judge_result)
    return judge_result


def run_case(
    case: dict[str, Any],
    artifact_root: Path,
    trials: int,
    model: str | None,
    with_judge: bool,
    workspace_snapshot: bool,
) -> list[dict[str, Any]]:
    """在每次独立临时克隆中运行用例，归档 Trace、结果、变化和评分。"""

    reports: list[dict[str, Any]] = []
    for trial in range(1, trials + 1):
        artifact_dir = artifact_root / case["id"] / f"trial-{trial}"
        artifact_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="ltp-agent-eval-") as temp_dir:
            isolated_repo = Path(temp_dir) / "repo"
            subprocess.run(
                ["git", "clone", "--local", "--no-hardlinks", str(REPO_ROOT), str(isolated_repo)],
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            if workspace_snapshot:
                _overlay_workspace_snapshot(REPO_ROOT, isolated_repo)
            raw_trace = artifact_dir / "raw_trace.jsonl"
            result_path = artifact_dir / "result.json"
            return_code, elapsed, stderr = _run_codex(
                isolated_repo,
                _build_agent_prompt(case),
                RESULT_SCHEMA,
                result_path,
                raw_trace,
                model,
            )
            trace_events = _normalize_raw_trace(raw_trace, artifact_dir / "trace.jsonl")
            observed_changes = _git_changed_files(isolated_repo)
            if return_code != 0 or not result_path.exists():
                result = {
                    "status": "failed",
                    "task_level": "none",
                    "selected_skills": [],
                    "summary": stderr.strip() or "Codex exec 未生成结果",
                    "changed_files": [],
                    "validation": [],
                    "safety": {
                        "schema": "unknown",
                        "filter_query": "unknown",
                        "filtered_queue": "unknown",
                        "cache_queue": "unknown",
                        "user_data": "unknown",
                    },
                }
                _write_json(result_path, result)
            else:
                result = _redact_value(_read_json(result_path), (isolated_repo,))
                _write_json(result_path, result)

            judge_result = None
            if return_code != 0:
                report = {
                    "case_id": case["id"],
                    "suite": case["suite"],
                    "category": case["category"],
                    "score": None,
                    "passed": False,
                    "evaluated": False,
                    "outcome": "infrastructure_error",
                    "threshold": PASS_THRESHOLD,
                    "deductions": [],
                    "infrastructure_error": result["summary"],
                    "observed": {
                        "selected_skills": [],
                        "changed_files": observed_changes,
                        "tool_calls": [],
                        "rubric_score": None,
                    },
                }
            else:
                rubric_name = case["expected"].get("rubric")
                if rubric_name and with_judge:
                    judge_result = _run_rubric_judge(
                        isolated_repo, rubric_name, result, artifact_dir, model
                    )
                report = score_result(
                    case, result, observed_changes, trace_events, judge_result
                )
            report.update(
                {
                    "trial": trial,
                    "duration_seconds": round(elapsed, 3),
                    "return_code": return_code,
                    "model": model or "default-config",
                    "codex_version": _codex_version(),
                    "usage": next(
                        (
                            {
                                "input_tokens": event.get("input_tokens", 0),
                                "cached_input_tokens": event.get("cached_input_tokens", 0),
                                "output_tokens": event.get("output_tokens", 0),
                            }
                            for event in reversed(trace_events)
                            if event.get("event") == "usage"
                        ),
                        {
                            "input_tokens": 0,
                            "cached_input_tokens": 0,
                            "output_tokens": 0,
                        },
                    ),
                    "estimated_cost_usd": None,
                }
            )
            _write_json(artifact_dir / "changed_files.json", observed_changes)
            _write_json(artifact_dir / "report.json", report)
            reports.append(report)
    return reports


def summarize_reports(reports: list[dict[str, Any]]) -> dict[str, Any]:
    """按用例和 suite 汇总分数、通过率、N 次稳定性、延迟与 token。"""

    by_case: dict[str, list[dict[str, Any]]] = {}
    for report in reports:
        by_case.setdefault(report["case_id"], []).append(report)
    case_summaries: list[dict[str, Any]] = []
    for case_id, trials in sorted(by_case.items()):
        evaluated = [report for report in trials if report.get("evaluated", True)]
        passed_count = sum(1 for report in evaluated if report["passed"])
        infrastructure_errors = sum(
            1 for report in trials if report.get("outcome") == "infrastructure_error"
        )
        case_summaries.append(
            {
                "case_id": case_id,
                "suite": trials[0]["suite"],
                "trials": len(trials),
                "evaluated_trials": len(evaluated),
                "infrastructure_errors": infrastructure_errors,
                "passed_trials": passed_count,
                "stable": len(evaluated) == len(trials) and passed_count == len(trials),
                "average_score": (
                    None
                    if not evaluated
                    else round(
                        sum(report["score"] for report in evaluated) / len(evaluated), 2
                    )
                ),
                "average_duration_seconds": round(
                    sum(report.get("duration_seconds", 0) for report in trials)
                    / len(trials),
                    3,
                ),
                "token_totals": {
                    key: sum(
                        int(report.get("usage", {}).get(key, 0)) for report in trials
                    )
                    for key in ("input_tokens", "cached_input_tokens", "output_tokens")
                },
            }
        )
    suite_summary: dict[str, dict[str, Any]] = {}
    for summary in case_summaries:
        suite = summary["suite"]
        bucket = suite_summary.setdefault(
            suite,
            {
                "cases": 0,
                "stable_cases": 0,
                "passed_trials": 0,
                "evaluated_trials": 0,
                "infrastructure_errors": 0,
                "trials": 0,
                "token_totals": {
                    "input_tokens": 0,
                    "cached_input_tokens": 0,
                    "output_tokens": 0,
                },
            },
        )
        bucket["cases"] += 1
        bucket["stable_cases"] += int(summary["stable"])
        bucket["passed_trials"] += summary["passed_trials"]
        bucket["evaluated_trials"] += summary["evaluated_trials"]
        bucket["infrastructure_errors"] += summary["infrastructure_errors"]
        bucket["trials"] += summary["trials"]
        for key, value in summary["token_totals"].items():
            bucket["token_totals"][key] += value
    for bucket in suite_summary.values():
        bucket["trial_pass_rate"] = round(
            bucket["passed_trials"] / max(bucket["evaluated_trials"], 1), 4
        )
    return {"cases": case_summaries, "suites": suite_summary}


def _collect_reports(root: Path) -> list[dict[str, Any]]:
    """递归读取运行目录中的单次 report.json。"""

    return [_read_json(path) for path in sorted(root.glob("**/report.json"))]


def _select_cases(
    cases: dict[str, dict[str, Any]], case_id: str | None, suite: str | None
) -> list[dict[str, Any]]:
    """按 case id 或 suite 选择运行范围，拒绝默认执行全部高成本用例。"""

    if case_id:
        if case_id not in cases:
            raise EvalError(f"未知用例：{case_id}")
        return [cases[case_id]]
    if suite:
        selected = [case for case in cases.values() if case["suite"] == suite]
        if not selected:
            raise EvalError(f"suite 没有用例：{suite}")
        return selected
    raise EvalError("run 必须显式提供 --case-id 或 --suite，避免意外产生大量模型调用")


def _default_artifact_root() -> Path:
    """生成被 .gitignore 排除的时间戳归档目录。"""

    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    return REPO_ROOT / "artifacts" / "agent_eval" / timestamp


def _build_parser() -> argparse.ArgumentParser:
    """创建命令行解析器。"""

    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="验证用例、Schema、Rubric 和触发覆盖")

    run_parser = subparsers.add_parser("run", help="在隔离临时克隆中执行 Agent Eval")
    run_parser.add_argument("--case-id")
    run_parser.add_argument("--suite", choices=["trigger", "capability", "regression"])
    run_parser.add_argument("--trials", type=int)
    run_parser.add_argument("--model")
    run_parser.add_argument("--judge", action="store_true")
    run_parser.add_argument(
        "--workspace-snapshot",
        action="store_true",
        help="显式把当前非忽略改动提交到隔离克隆后再测试",
    )
    run_parser.add_argument("--artifact-root", type=Path)

    summarize_parser = subparsers.add_parser("summarize", help="汇总既有运行报告")
    summarize_parser.add_argument("artifact_root", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    """执行命令并把机器可读结果写到标准输出。"""

    args = _build_parser().parse_args(argv)
    try:
        if args.command == "validate":
            print(json.dumps(validate_catalog(), ensure_ascii=False, indent=2))
            return 0
        if args.command == "summarize":
            reports = _collect_reports(args.artifact_root)
            if not reports:
                raise EvalError(f"没有找到 report.json：{args.artifact_root}")
            summary = summarize_reports(reports)
            _write_json(args.artifact_root / "summary.json", summary)
            print(json.dumps(summary, ensure_ascii=False, indent=2))
            return 0

        cases = load_cases()
        selected = _select_cases(cases, args.case_id, args.suite)
        artifact_root = (args.artifact_root or _default_artifact_root()).resolve()
        all_reports: list[dict[str, Any]] = []
        for case in selected:
            trials = args.trials or int(case.get("trials", 1))
            if trials < 1:
                raise EvalError("--trials 必须是正整数")
            all_reports.extend(
                run_case(
                    case,
                    artifact_root,
                    trials,
                    args.model,
                    args.judge,
                    args.workspace_snapshot,
                )
            )
        summary = summarize_reports(all_reports)
        _write_json(artifact_root / "summary.json", summary)
        print(json.dumps({"artifact_root": str(artifact_root), **summary}, ensure_ascii=False, indent=2))
        if any(report.get("outcome") == "infrastructure_error" for report in all_reports):
            return 2
        return 0 if all(report["passed"] for report in all_reports) else 1
    except (EvalError, OSError, subprocess.SubprocessError) as error:
        print(f"agent-eval error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
