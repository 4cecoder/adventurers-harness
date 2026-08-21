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
Adventurers Harness - Real Cactus Needle 2 Engine into Bonsai 27B LM Studio Pipeline
Demonstrates:
  1. Real `cactus-needle` 14MB on-device Simple Attention Network inference (600+ TPS prefill, 120+ TPS decode)
  2. Confidence-Gated Tool Calling:
     - High Confidence (>= 0.75): Resolved on-device in ~15ms (0 cloud tokens)
     - Low Confidence (< 0.75) / Complex Reasoning: Escalated to Bonsai 27B on LM Studio (/v1/responses)
  3. OpenAI Responses API extraction: Reasoning trace (CoT), function calls, and execution loop
"""

import sys
import json
import time
import httpx
import needle
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.syntax import Syntax
from rich.progress import Progress, SpinnerColumn, TextColumn

console = Console()

# MARK: - Real Cactus Needle 2 On-Device Tool Registry


@needle.tool
def get_current_weather(location: str, unit: str = "fahrenheit"):
    """Get the current weather for a specified location and temperature unit."""
    temp = 68 if unit.lower().startswith("f") else 20
    return {
        "location": location,
        "temperature": f"{temp}°{unit[0].upper()}",
        "condition": "Partly Cloudy",
        "humidity": "54%",
        "wind": "8 mph NE",
    }


@needle.tool
def search_codebase(query: str, path: str = "."):
    """Search codebase repository files for a regex pattern or symbol name."""
    return {
        "query": query,
        "path": path,
        "matches": [
            {"file": "Sources/AdventurersCore/LMStudioBridge.swift", "line": 42},
            {"file": "Sources/AdventurersCore/LocalInferenceManager.swift", "line": 15},
        ],
    }


TOOLS_SCHEMA = [
    {
        "type": "function",
        "name": "get_current_weather",
        "description": "Get the current weather in a given location",
        "parameters": {
            "type": "object",
            "properties": {
                "location": {
                    "type": "string",
                    "description": "The city and state, e.g. Boston, MA",
                },
                "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]},
            },
            "required": ["location", "unit"],
        },
    },
    {
        "type": "function",
        "name": "search_codebase",
        "description": "Search repository files for matching symbol or keyword regex",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The regex pattern to search for",
                },
                "path": {"type": "string", "description": "Search directory path"},
            },
            "required": ["query"],
        },
    },
]


def run_pipeline(
    user_prompt: str,
    confidence_threshold: float = 0.70,
    base_url: str = "http://localhost:1234",
):
    console.print(
        Panel(
            f"[bold white]{user_prompt}[/bold white]",
            title="[bold cyan]1. User Request[/bold cyan]",
            border_style="cyan",
        )
    )

    # --- Phase 1: Real Needle 2 On-Device Inference ---
    start_needle = time.perf_counter()
    needle_agent = needle.Needle(tools=[get_current_weather, search_codebase])

    with Progress(
        SpinnerColumn(),
        TextColumn("[bold yellow]Cactus Needle 2: On-device Simple Attention Network inference..."),
        transient=True,
    ) as progress:
        progress.add_task("Needle 2 Inference", total=None)
        needle_res = needle_agent.run(user_prompt)

    needle_latency_ms = (time.perf_counter() - start_needle) * 1000.0

    confidence = float(needle_res.get("confidence") or 0.0)
    prefill_tps = float(needle_res.get("prefill_tps") or 0.0)
    decode_tps = float(needle_res.get("decode_tps") or 0.0)
    peak_ram = float(needle_res.get("peak_ram_mb") or 0.0)
    results = needle_res.get("results") or []

    needle_table = Table(show_header=True, header_style="bold yellow")
    needle_table.add_column("Cactus Needle 2 Metric")
    needle_table.add_column("Value")
    needle_table.add_row("Model Size", "14 MB (45M CQ2-bit Simple Attention Network)")
    needle_table.add_row("Inference Latency", f"{needle_latency_ms:.1f} ms")
    needle_table.add_row("Prefill Velocity", f"[green]{prefill_tps:.1f} tok/s[/green]")
    needle_table.add_row("Decode Velocity", f"[green]{decode_tps:.1f} tok/s[/green]")
    needle_table.add_row("Peak RAM Memory", f"{peak_ram:.1f} MB")
    needle_table.add_row(
        "Calibrated Confidence",
        f"[{'green' if confidence >= confidence_threshold else 'red'}]{confidence * 100:.1f}%[/]",
    )

    decision_text = (
        "[bold green]FAST_PATH_LOCAL_SUCCESS[/bold green]"
        if confidence >= confidence_threshold
        else "[bold magenta]ESCALATE_TO_BONSAI_27B[/bold magenta]"
    )
    needle_table.add_row("Execution Decision", decision_text)

    console.print(
        Panel(
            needle_table,
            title="[bold yellow]2. Cactus Needle 2 On-Device Telemetry[/bold yellow]",
            border_style="yellow",
        )
    )

    # --- Phase 2: If High Confidence, Return Instant Result ---
    if confidence >= confidence_threshold and results:
        console.print(
            Panel(
                Syntax(json.dumps(results, indent=2), "json", theme="monokai"),
                title="[bold green]3. On-Device Instant Tool Execution Result[/bold green]",
                border_style="green",
            )
        )
        console.print(
            "[bold green]✔ Fully resolved on-device by Cactus Needle 2 in 0 tokens![/bold green]\n"
        )
        return

    # --- Phase 3: Escalation to Bonsai 27B via LM Studio /v1/responses ---
    console.print(
        f"[bold magenta]⚡ Escalating to Bonsai 27B (LM Studio @ {base_url}/v1/responses) for full multi-step reasoning & tool calling...[/bold magenta]"
    )

    endpoint = f"{base_url}/v1/responses"
    payload = {
        "model": "prism-ml/bonsai-27b",
        "input": user_prompt,
        "tools": TOOLS_SCHEMA,
        "tool_choice": "auto",
    }

    start_bonsai = time.perf_counter()
    response_data = {}

    with Progress(
        SpinnerColumn(),
        TextColumn(
            "[bold magenta]Bonsai 27B: Generating Chain-of-Thought & structured tool payload..."
        ),
        transient=True,
    ) as progress:
        progress.add_task("Bonsai Inference", total=None)
        try:
            with httpx.Client(timeout=300.0) as client:
                resp = client.post(endpoint, json=payload)
                resp.raise_for_status()
                response_data = resp.json()
        except Exception as e:
            console.print(f"[bold red]❌ Connection to {endpoint} failed: {e}[/bold red]")
            sys.exit(1)

    bonsai_latency_ms = (time.perf_counter() - start_bonsai) * 1000.0

    # Extract CoT reasoning and tool calls
    reasoning_texts = []
    tool_calls = []

    if "output" in response_data:
        for item in response_data.get("output", []):
            if item.get("type") == "reasoning":
                for c in item.get("content", []):
                    if c.get("type") == "reasoning_text":
                        reasoning_texts.append(c.get("text", "").strip())
            elif item.get("type") == "function_call":
                tool_calls.append(
                    {
                        "id": item.get("call_id") or item.get("id", "call_0"),
                        "name": item.get("name"),
                        "arguments": item.get("arguments", "{}"),
                    }
                )

    if not tool_calls and "choices" in response_data:
        for ch in response_data.get("choices", []):
            for tc in ch.get("message", {}).get("tool_calls", []):
                fn = tc.get("function", {})
                tool_calls.append(
                    {
                        "id": tc.get("id", "call_0"),
                        "name": fn.get("name"),
                        "arguments": fn.get("arguments", "{}"),
                    }
                )

    if reasoning_texts:
        console.print(
            Panel(
                "\n".join(reasoning_texts),
                title="[bold yellow]🧠 Bonsai 27B Chain-of-Thought Reasoning Trace[/bold yellow]",
                border_style="yellow",
            )
        )

    if tool_calls:
        tool_table = Table(show_header=True, header_style="bold cyan")
        tool_table.add_column("Tool Call ID")
        tool_table.add_column("Function Name")
        tool_table.add_column("Arguments")
        tool_table.add_column("Execution Result")

        for tc in tool_calls:
            name = tc["name"]
            raw_args = tc["arguments"]
            args = json.loads(raw_args) if isinstance(raw_args, str) else raw_args

            if name == "get_current_weather":
                res_obj = {
                    "location": args.get("location", "Boston, MA"),
                    "temperature": "68°F",
                    "condition": "Partly Cloudy",
                }
                res_str = json.dumps(res_obj)
            elif name == "search_codebase":
                res_obj = {
                    "matches": [
                        {
                            "file": "Sources/AdventurersCore/LMStudioBridge.swift",
                            "line": 42,
                        }
                    ]
                }
                res_str = json.dumps(res_obj)
            else:
                res_str = json.dumps({"error": f"Unknown tool: {name}"})

            tool_table.add_row(
                str(tc["id"]),
                f"[bold yellow]{name}[/bold yellow]",
                json.dumps(args),
                f"[green]{res_str}[/green]",
            )

        console.print(
            Panel(
                tool_table,
                title=f"[bold cyan]4. Bonsai 27B Tool Execution Resolution ({bonsai_latency_ms:.1f}ms)[/bold cyan]",
                border_style="cyan",
            )
        )

    usage = response_data.get("usage", {})
    if usage:
        in_tok = usage.get("input_tokens", usage.get("prompt_tokens", 0))
        out_tok = usage.get("output_tokens", usage.get("completion_tokens", 0))
        tot_tok = usage.get("total_tokens", 0)
        reason_tok = usage.get("output_tokens_details", {}).get("reasoning_tokens", 0)

        console.print(
            f"[bold cyan]Token Accounting:[/bold cyan] "
            f"Input: [bold]{in_tok}[/bold] | "
            f"Output: [bold]{out_tok}[/bold] (Reasoning CoT: [bold yellow]{reason_tok}[/bold yellow]) | "
            f"Total: [bold]{tot_tok}[/bold] tokens"
        )

    console.print(
        "\n[bold green]✔ Complete Needle 2 Edge -> Bonsai 27B pipeline executed successfully![/bold green]\n"
    )


if __name__ == "__main__":
    prompt = sys.argv[1] if len(sys.argv) > 1 else "What is the weather like in Boston today?"
    threshold = float(sys.argv[2]) if len(sys.argv) > 2 else 0.70
    run_pipeline(prompt, confidence_threshold=threshold)
