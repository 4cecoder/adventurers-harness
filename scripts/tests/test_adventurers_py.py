"""
Unit tests for adventurers_py tools, safety gates, and models.
"""

import os
from adventurers_py.tools import (
    view_file,
    replace_file_content,
    write_to_file,
    is_dangerous_command,
)
from adventurers_py.gates import SyntaxGate, RepeatGate, DiffGate
from adventurers_py.models import SMALL_MODELS_REGISTRY


def test_dangerous_command_blocker():
    assert is_dangerous_command("rm -rf /") is not None
    assert is_dangerous_command("chmod -R 777 /var") is not None
    assert is_dangerous_command("git status") is None
    assert is_dangerous_command("swift test") is None


def test_syntax_gate():
    ok, err = SyntaxGate.verify("func test() { return [1, 2, (3 + 4)] }")
    assert ok is True
    assert err is None

    bad_ok, bad_err = SyntaxGate.verify("func test() { return [1, 2 }")
    assert bad_ok is False
    assert "Mismatched" in bad_err or "Unclosed" in bad_err


def test_repeat_gate():
    gate = RepeatGate(max_repeats=3)
    ok1, _ = gate.record_and_check("view_file", {"path": "test.swift"})
    ok2, _ = gate.record_and_check("view_file", {"path": "test.swift"})
    ok3, err = gate.record_and_check("view_file", {"path": "test.swift"})
    assert ok1 is True
    assert ok2 is True
    assert ok3 is False
    assert "Repeat Gate Tripped" in err


def test_diff_gate():
    ok, _ = DiffGate.verify("let a = 1", "let a = 2")
    assert ok is True

    bad_ok, _ = DiffGate.verify("", "let a = 2")
    assert bad_ok is False

    noop_ok, _ = DiffGate.verify("let a = 1", "let a = 1")
    assert noop_ok is False


def test_file_tools_lifecycle(tmp_path):
    fpath = os.path.join(tmp_path, "sample.txt")

    # 1. Write file
    w_res = write_to_file(fpath, "Hello World\nLine 2\nLine 3\n")
    assert w_res["success"] is True

    # 2. View file
    v_res = view_file(fpath, start_line=1, end_line=2)
    assert v_res["success"] is True
    assert "Hello World" in v_res["content"]

    # 3. Replace content
    r_res = replace_file_content(fpath, "Line 2", "Line 2 Replaced")
    assert r_res["success"] is True

    # 4. Verify replacement
    v2_res = view_file(fpath)
    assert "Line 2 Replaced" in v2_res["content"]


def test_model_roster_data():
    assert "needle2" in SMALL_MODELS_REGISTRY
    assert "minicpm-1b" in SMALL_MODELS_REGISTRY
    assert "qwen-0.5b" in SMALL_MODELS_REGISTRY
    assert SMALL_MODELS_REGISTRY["needle2"].expected_tps >= 900.0
    assert SMALL_MODELS_REGISTRY["minicpm-1b"].context_window == 131072


def test_json_repair_engine():
    from adventurers_py.repair_engine import repair_json_string, normalize_tool_arguments

    # 1. Single quotes & trailing commas
    malformed = "{'path': 'test.swift', 'start_line': '1',}"
    repaired, err = repair_json_string(malformed)
    assert repaired is not None
    assert repaired["path"] == "test.swift"

    # 2. Type normalization
    norm = normalize_tool_arguments("view_file", repaired)
    assert norm["start_line"] == 1


def test_context_optimizer():
    from adventurers_py.context_optimizer import ContextOptimizer

    opt = ContextOptimizer(max_token_budget=50, tail_turns_preserved=1)

    msgs = [
        {"role": "system", "content": "You are a coding agent."},
        {"role": "user", "content": "Task A"},
        {"role": "assistant", "content": "Executing long output " * 50},
        {"role": "user", "content": "Next step"},
    ]

    optimized = opt.optimize_messages(msgs)
    assert len(optimized) == 4
    assert "[COMPACTED]" in optimized[2]["content"]
