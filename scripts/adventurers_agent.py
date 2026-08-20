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
Adventurers Python Autonomous Agent CLI
Run:
  uv run scripts/adventurers_agent.py "Check git status and find all Swift files"
  uv run scripts/adventurers_agent.py --models
"""

import sys
import os
import argparse
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

# Add current scripts directory to path for package imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from adventurers_py.models import SMALL_MODELS_REGISTRY
from adventurers_py.loop import AdventurersAgentLoop

console = Console()

def print_model_roster():
    """Prints the registry of ultra-small, high-TPS on-device models."""
    table = Table(show_header=True, header_style="bold cyan")
    table.add_column("Model Name")
    table.add_column("Parameters")
    table.add_column("INT4 Size")
    table.add_column("Context Window")
    table.add_column("Expected TPS")
    table.add_column("On-Device Role")

    for key, m in SMALL_MODELS_REGISTRY.items():
        table.add_row(
            f"[bold yellow]{m.name}[/bold yellow]",
            m.params,
            f"{m.quantized_size_mb} MB" if m.quantized_size_mb < 1024 else f"{m.quantized_size_mb/1024:.1f} GB",
            f"{m.context_window/1024:.0f}K" if m.context_window >= 1024 else str(m.context_window),
            f"[green]{m.expected_tps:.0f} tok/s[/green]",
            m.description
        )

    console.print(Panel(table, title="[bold cyan]🚀 Ultra-Small High-TPS On-Device Models (< 1B to 27B)[/bold cyan]", border_style="cyan"))

def main():
    parser = argparse.ArgumentParser(description="Adventurers Python Autonomous Agent")
    parser.add_argument("prompt", nargs="?", help="Task prompt for the agent to execute")
    parser.add_argument("--models", action="store_true", help="List ultra-small on-device models and TPS benchmarks")
    parser.add_argument("--model-id", default="prism-ml/bonsai-27b", help="Model identifier to use")
    parser.add_argument("--url", default="http://localhost:1234", help="LM Studio or local engine base URL")
    parser.add_argument("--max-turns", type=int, default=8, help="Maximum execution turns")

    args = parser.parse_args()

    if args.models:
        print_model_roster()
        return

    if not args.prompt:
        console.print("[bold yellow]Adventurers Python Autonomous Agent[/bold yellow]")
        console.print("Usage: [green]uv run scripts/adventurers_agent.py \"<prompt>\"[/green]")
        console.print("       [green]uv run scripts/adventurers_agent.py --models[/green]\n")
        args.prompt = "Find all Swift test files in the codebase and check git status"

    loop = AdventurersAgentLoop(
        base_url=args.url,
        active_model_id=args.model_id,
        max_turns=args.max_turns
    )

    loop.run(args.prompt)

if __name__ == "__main__":
    main()
