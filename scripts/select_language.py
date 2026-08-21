# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "rich",
#     "pydantic",
#     "httpx",
# ]
# ///
"""
Adventurers Language Decision Matrix CLI
Displays hardcoded language selection rules and methodology for CLI-first verification.
"""

import sys
import os
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from adventurers_py.language_selector import LANGUAGE_DECISION_MATRIX, classify_prompt_domain

console = Console()


def main():
    console.print(
        Panel(
            "[bold cyan]🧭 Hardcoded Polyglot Language Decision Matrix[/bold cyan]\n"
            "[dim]Main Directive: Choose the optimal language per subsystem, test headlessly via CLI first, verify functionality, and integrate GUI later.[/dim]",
            border_style="cyan",
        )
    )

    table = Table(show_header=True, header_style="bold yellow")
    table.add_column("Workload Domain")
    table.add_column("Optimal Language")
    table.add_column("Primary Architectural Rationale")
    table.add_column("CLI Verification Methodology")

    for domain, rec in LANGUAGE_DECISION_MATRIX.items():
        table.add_row(
            f"[bold green]{domain.value}[/bold green]",
            f"[bold cyan]{rec.selected_language.value}[/bold cyan]",
            rec.rationale,
            f"[yellow]{rec.verification_methodology}[/yellow]",
        )

    console.print(
        Panel(
            table,
            title="[bold green]Polyglot Language Selection Strategy[/bold green]",
            border_style="green",
        )
    )

    # If prompt passed, demonstrate classification
    if len(sys.argv) > 1:
        query = " ".join(sys.argv[1:])
        classified = classify_prompt_domain(query)
        rec = LANGUAGE_DECISION_MATRIX[classified]
        console.print(f'\n[bold]Query:[/bold] [italic]"{query}"[/italic]')
        console.print(f"[bold]Selected Domain:[/bold] [green]{classified.value}[/green]")
        console.print(
            f"[bold]Recommended Language:[/bold] [bold cyan]{rec.selected_language.value}[/bold cyan]"
        )
        console.print(
            f"[bold]Verification Step:[/bold] [yellow]{rec.verification_methodology}[/yellow]\n"
        )


if __name__ == "__main__":
    main()
