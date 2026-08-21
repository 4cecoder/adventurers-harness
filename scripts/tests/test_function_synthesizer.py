"""
Unit tests for the Function-by-Function Synthesis Engine (C-Programmer architecture).
"""

from adventurers_py.function_synthesizer import FunctionSynthesizer, FunctionSpec


def test_single_function_synthesis():
    synthesizer = FunctionSynthesizer()
    spec = FunctionSpec(
        name="clamp",
        signature="def clamp(val, min_val, max_val)",
        docstring="Clamps value",
        test_cases=["assert clamp(5, 0, 10) == 5", "assert clamp(-1, 0, 10) == 0"],
    )
    res = synthesizer.synthesize_function(spec)
    assert res.success is True
    assert res.function_name == "clamp"
    assert spec.verified_code is not None


def test_failed_assertion_recovery():
    synthesizer = FunctionSynthesizer(max_attempts_per_func=2)
    # Impossible assertion
    spec = FunctionSpec(
        name="clamp",
        signature="def clamp(val, min_val, max_val)",
        docstring="Clamps value",
        test_cases=["assert clamp(5, 0, 10) == 9999"],
    )
    res = synthesizer.synthesize_function(spec)
    assert res.success is False
    assert "Assertion failed" in res.test_summary


def test_program_assembly():
    synthesizer = FunctionSynthesizer()
    spec1 = FunctionSpec(
        name="str_trim",
        signature="def str_trim(s)",
        docstring="Trims string",
        test_cases=["assert str_trim(' a ') == 'a'"],
    )
    spec2 = FunctionSpec(
        name="calc_checksum",
        signature="def calc_checksum(s)",
        docstring="Checksum",
        test_cases=["assert calc_checksum('A') == 65"],
    )
    synthesizer.register_function(spec1)
    synthesizer.register_function(spec2)
    synthesizer.synthesize_function(spec1)
    synthesizer.synthesize_function(spec2)

    program = synthesizer.assemble_program()
    assert "def str_trim(s):" in program
    assert "def calc_checksum(s):" in program
