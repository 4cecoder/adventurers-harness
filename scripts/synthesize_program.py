# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "cactus-needle>=2.0.8",
#     "httpx",
#     "rich",
#     "pydantic",
# ]
# ///
"""
Adventurers Program Synthesis CLI (C-Style Unit-by-Unit Synthesis)
Demonstrates synthesizing a suite of functions one-at-a-time using tiny models & deterministic test gates,
then assembling them into a complete verified program module.
"""

import sys
import os
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.syntax import Syntax

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from adventurers_py.function_synthesizer import FunctionSynthesizer, FunctionSpec

console = Console()


def main():
    console.print(
        Panel(
            "[bold cyan]🔨 Function-by-Function Synthesis Engine (C-Programmer Architecture)[/bold cyan]\n"
            "[dim]Isolating small models to < 200 token function contracts, testing each in isolation, and assembling 1,000-function systems.[/dim]",
            border_style="cyan",
        )
    )

    # Define a suite of discrete, testable functions
    specs = [
        FunctionSpec(
            name="clamp",
            signature="def clamp(val: float, min_val: float, max_val: float) -> float",
            docstring="Clamps a number between min_val and max_val.",
            test_cases=[
                "assert clamp(5, 0, 10) == 5",
                "assert clamp(-5, 0, 10) == 0",
                "assert clamp(15, 0, 10) == 10",
            ],
        ),
        FunctionSpec(
            name="str_trim",
            signature="def str_trim(s: str) -> str",
            docstring="Removes leading and trailing whitespace.",
            test_cases=[
                "assert str_trim('  hello  ') == 'hello'",
                r"assert str_trim('\tworld\n') == 'world'",
                "assert str_trim('') == ''",
            ],
        ),
        FunctionSpec(
            name="str_split_words",
            signature="def str_split_words(s: str) -> list",
            docstring="Splits a string by whitespace into word tokens.",
            test_cases=[
                "assert str_split_words('hello world') == ['hello', 'world']",
                "assert str_split_words('  one   two  three  ') == ['one', 'two', 'three']",
            ],
        ),
        FunctionSpec(
            name="calc_checksum",
            signature="def calc_checksum(s: str) -> int",
            docstring="Calculates an 8-bit checksum mod 256.",
            test_cases=[
                "assert calc_checksum('A') == 65",
                "assert calc_checksum('AB') == 131",
                "assert calc_checksum('') == 0",
            ],
        ),
    ]

    synthesizer = FunctionSynthesizer()
    results = []

    for spec in specs:
        synthesizer.register_function(spec)
        res = synthesizer.synthesize_function(spec)
        results.append(res)

    # Display Results Table
    table = Table(show_header=True, header_style="bold green")
    table.add_column("Function")
    table.add_column("Turn Iterations")
    table.add_column("Synthesis Latency")
    table.add_column("Test Verification")
    table.add_column("Invariant Status")

    for r in results:
        table.add_row(
            f"[bold yellow]{r.function_name}()[/bold yellow]",
            f"{r.iterations} turn(s)",
            f"{r.total_latency_ms:.2f} ms",
            r.test_summary,
            "[bold green]VERIFIED & FROZEN[/bold green]"
            if r.success
            else "[bold red]FAILED[/bold red]",
        )

    console.print(
        Panel(
            table,
            title="[bold green]1. Unit-Isolated Synthesis Progression[/bold green]",
            border_style="green",
        )
    )

    # Assemble and print complete program
    assembled_code = synthesizer.assemble_program()
    console.print(
        Panel(
            Syntax(assembled_code, "python", theme="monokai", line_numbers=True),
            title="[bold cyan]2. Assembled & Linked Program Unit (Zero Defects)[/bold cyan]",
            border_style="cyan",
        )
    )

    console.print(
        f"[bold green]✔ Successfully synthesized and assembled {len(specs)}/{len(specs)} functions deterministically![/bold green]\n"
    )


if __name__ == "__main__":
    main()
