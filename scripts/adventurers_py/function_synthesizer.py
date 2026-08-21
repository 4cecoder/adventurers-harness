"""
Adventurers Function-by-Function Synthesis Engine (C-Programmer Style)
Builds large, robust software systems by breaking programs into discrete, isolated function units:
  1. Scope Isolation: Small models see ONLY 1 function signature + unit test assertions (< 200 tokens).
  2. Iterative Patch Loop: Small model iterates at 450+ TPS until test assertions pass.
  3. Invariant Freezing: Verified functions are frozen and linked into the master module.
  4. Compositional Assembly: 1,000 individually verified functions assemble into an industrial program.
"""

import time
from typing import List, Dict, Optional, Callable
from pydantic import BaseModel
from rich.console import Console

from .gates import SyntaxGate

console = Console()


class FunctionSpec(BaseModel):
    name: str
    signature: str
    docstring: str
    test_cases: List[str]  # e.g. ["assert add(2, 3) == 5", "assert add(-1, 1) == 0"]
    dependencies: List[str] = []
    verified_code: Optional[str] = None
    iteration_attempts: int = 0
    latency_ms: float = 0.0


class UnitSynthesisResult(BaseModel):
    function_name: str
    success: bool
    iterations: int
    total_latency_ms: float
    code: str
    test_summary: str


class FunctionSynthesizer:
    def __init__(self, max_attempts_per_func: int = 4):
        self.max_attempts = max_attempts_per_func
        self.registry: Dict[str, FunctionSpec] = {}

    def register_function(self, spec: FunctionSpec):
        self.registry[spec.name] = spec

    def synthesize_function(
        self,
        spec: FunctionSpec,
        generator_fn: Optional[Callable[[FunctionSpec, Optional[str]], str]] = None,
    ) -> UnitSynthesisResult:
        """Iteratively synthesizes and verifies a single function in strict isolation."""
        start_time = time.perf_counter()
        feedback = None
        attempt = 0

        while attempt < self.max_attempts:
            attempt += 1
            spec.iteration_attempts = attempt

            # Generate candidate code
            if generator_fn:
                candidate_code = generator_fn(spec, feedback)
            else:
                # Default clean mock generator for unit tests
                candidate_code = self._default_mock_generator(spec, attempt)

            # Gate 1: AST / Syntax Check
            syn_ok, syn_err = SyntaxGate.verify(candidate_code)
            if not syn_ok:
                feedback = f"Syntax Gate Error: {syn_err}"
                continue

            # Gate 2: Execute Unit Test Assertions
            test_passed, test_err = self._execute_unit_tests(candidate_code, spec.test_cases)
            if not test_passed:
                feedback = f"Test Assertion Failed: {test_err}"
                continue

            # Success: Function is verified!
            latency = (time.perf_counter() - start_time) * 1000.0
            spec.verified_code = candidate_code
            spec.latency_ms = latency

            return UnitSynthesisResult(
                function_name=spec.name,
                success=True,
                iterations=attempt,
                total_latency_ms=latency,
                code=candidate_code,
                test_summary=f"All {len(spec.test_cases)} assertions passed",
            )

        # Reached attempt limit
        latency = (time.perf_counter() - start_time) * 1000.0
        return UnitSynthesisResult(
            function_name=spec.name,
            success=False,
            iterations=attempt,
            total_latency_ms=latency,
            code="",
            test_summary=f"Failed after {attempt} attempts. Last error: {feedback}",
        )

    def assemble_program(self) -> str:
        """Assembles all verified functions into a complete compilation unit."""
        blocks = []
        for name, spec in self.registry.items():
            if spec.verified_code:
                blocks.append(
                    f"# --- Function: {name} [Verified in {spec.iteration_attempts} turn(s)] ---\n{spec.verified_code}\n"
                )
            else:
                blocks.append(f"# [WARNING]: Function {name} not yet synthesized\n")
        return "\n".join(blocks)

    def _execute_unit_tests(self, code: str, test_cases: List[str]) -> (bool, Optional[str]):
        """Executes test cases in a fresh isolated namespace."""
        namespace = {}
        try:
            # Execute function definition
            exec(code, namespace)
            # Execute assertions
            for tc in test_cases:
                exec(tc, namespace)
            return True, None
        except AssertionError:
            return False, f"Assertion failed in '{tc}'"
        except Exception as e:
            return False, str(e)

    def _default_mock_generator(self, spec: FunctionSpec, attempt: int) -> str:
        """Simulates tiny model generating implementation."""
        if spec.name == "clamp":
            return "def clamp(val, min_val, max_val):\n    return max(min_val, min(val, max_val))"
        elif spec.name == "str_trim":
            return "def str_trim(s):\n    return s.strip()"
        elif spec.name == "str_split_words":
            return "def str_split_words(s):\n    return s.split()"
        elif spec.name == "calc_checksum":
            return "def calc_checksum(s):\n    return sum(ord(c) for c in s) % 256"
        else:
            return f"def {spec.name}():\n    return True"
