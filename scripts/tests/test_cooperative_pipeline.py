"""
Unit tests for CooperativeSmallModelSwarm pipeline.
"""

from adventurers_py.cooperative_pipeline import CooperativeSmallModelSwarm


def test_fast_path_swarm_execution():
    swarm = CooperativeSmallModelSwarm()
    report = swarm.execute_swarm("git status")

    assert report.overall_status == "RESOLVED_ON_DEVICE"
    assert len(report.micro_tasks) >= 1
    assert report.micro_tasks[0].target_tool == "run_command"
    assert report.escalated_to_bonsai is False
    assert report.total_latency_ms < 500.0


def test_decomposed_swarm_execution():
    swarm = CooperativeSmallModelSwarm()
    report = swarm.execute_swarm("Find all python test files and check git status")

    assert report.overall_status == "SUCCESS_SMALL_MODELS_ONLY"
    assert len(report.micro_tasks) >= 2
    assert report.micro_tasks[0].status == "VERIFIED"
    assert report.micro_tasks[1].status == "VERIFIED"
    assert report.escalated_to_bonsai is False


def test_internet_connectivity_check():
    from adventurers_py.cooperative_pipeline import is_internet_available

    # Socket probe returns boolean cleanly without crashing
    res = is_internet_available(timeout_sec=1.0)
    assert isinstance(res, bool)


def test_hindsight_docker_guard():
    from adventurers_py.memory_guard import (
        is_hindsight_docker_running,
        HindsightMemoryManager,
    )

    # Random unused port should return False safely without hanging
    assert is_hindsight_docker_running(port=59999, timeout_sec=0.05) is False

    mgr = HindsightMemoryManager(docker_port=59999)
    assert mgr.should_use_hindsight() is False
    assert mgr.query_or_fallback("test") is None
