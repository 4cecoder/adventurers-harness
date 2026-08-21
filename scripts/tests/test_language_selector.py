"""
Unit tests for the Polyglot Language Selector & Decision Matrix.
"""

from adventurers_py.language_selector import (
    Language,
    WorkloadDomain,
    recommend_language_for_task,
    classify_prompt_domain,
)


def test_language_matrix_coverage():
    for domain in WorkloadDomain:
        rec = recommend_language_for_task(domain)
        assert rec is not None
        assert rec.selected_language in Language
        assert len(rec.strengths) > 0
        assert len(rec.verification_methodology) > 0


def test_intent_classification():
    assert (
        classify_prompt_domain("Write a SIMD token parser in C")
        == WorkloadDomain.LOW_LATENCY_COMPUTE
    )
    assert (
        classify_prompt_domain("Build a macOS PTY terminal in Swift")
        == WorkloadDomain.MACOS_NATIVE_SYSTEM
    )
    assert (
        classify_prompt_domain("Write a docker-compose bash startup script")
        == WorkloadDomain.DEVOPS_ORCHESTRATION
    )
    assert (
        classify_prompt_domain("Build a memory-safe TLS proxy daemon")
        == WorkloadDomain.NETWORK_SECURITY
    )
    assert (
        classify_prompt_domain("Create an automated pytest eval harness")
        == WorkloadDomain.AGENT_HARNESS_GLUE
    )
