"""
Adventurers Python Agentic Thinking Loop
Executes multi-turn tool loops with gate validation and multi-tier model escalation.
"""

import time
import json
import httpx
from typing import List, Dict, Any, Optional
from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax
from rich.progress import Progress, SpinnerColumn, TextColumn

from .tools import dispatch_tool, TOOLS_SCHEMAS
from .gates import SyntaxGate, RepeatGate, DiffGate, GuardianCircuitBreaker
from .models import SMALL_MODELS_REGISTRY, SmallModelSpec
from .repair_engine import repair_json_string, normalize_tool_arguments
from .context_optimizer import ContextOptimizer

console = Console()


class AdventurersAgentLoop:
    def __init__(
        self,
        base_url: str = "http://localhost:1234",
        active_model_id: str = "prism-ml/bonsai-27b",
        max_turns: int = 10,
        enable_needle_edge: bool = True,
    ):
        self.base_url = base_url
        self.active_model_id = active_model_id
        self.max_turns = max_turns
        self.enable_needle_edge = enable_needle_edge

        self.repeat_gate = RepeatGate()
        self.circuit_breaker = GuardianCircuitBreaker()
        self.messages: List[Dict[str, Any]] = []

    def run(self, prompt: str) -> Dict[str, Any]:
        """Runs the autonomous thinking loop until objective complete or max turns reached."""
        console.print(
            Panel(
                f"[bold white]{prompt}[/bold white]",
                title="[bold cyan]⚡ New Task Input[/bold cyan]",
                border_style="cyan",
            )
        )

        # --- PHASE 1: Needle 2 On-Device Fast-Path & Intent Gating ---
        if self.enable_needle_edge:
            start_edge = time.perf_counter()
            lower = prompt.lower().strip()

            if lower.startswith("git ") or lower in (
                "git status",
                "git diff",
                "git log",
            ):
                # Execute direct fast-path
                res_str = dispatch_tool("run_command", {"command": prompt})
                edge_ms = (time.perf_counter() - start_edge) * 1000.0
                console.print(
                    f"[bold green]⚡ Needle 2 Fast-Path Intercept ({edge_ms:.1f}ms / 0 cloud tokens)[/bold green]"
                )
                console.print(
                    Panel(
                        json.loads(res_str).get("output", ""),
                        title="[bold green]Fast-Path Native Execution[/bold green]",
                        border_style="green",
                    )
                )
                return {
                    "status": "completed",
                    "resolved_by": "Needle 2 Edge",
                    "turns": 1,
                }

        self.messages.append({"role": "user", "content": prompt})

        # --- PHASE 2: Multi-Turn Autonomous Tool Loop ---
        turn = 0
        while turn < self.max_turns:
            turn += 1
            if self.circuit_breaker.is_tripped:
                console.print(
                    "[bold red]🚨 Circuit Breaker Tripped: 3 consecutive failures. Aborting loop safely.[/bold red]"
                )
                return {"status": "circuit_breaker_tripped", "turns": turn}

            console.print(
                f"\n[bold yellow]━━━ Turn {turn}/{self.max_turns} [{self.active_model_id}] ━━━[/bold yellow]"
            )

            # Call Model via /v1/responses or /v1/chat/completions
            response_payload = self._call_model_endpoint(prompt)
            if not response_payload:
                self.circuit_breaker.record_outcome(False)
                continue

            tool_calls = response_payload.get("tool_calls", [])
            assistant_text = response_payload.get("content")
            reasoning = response_payload.get("reasoning")

            if reasoning:
                console.print(
                    Panel(
                        reasoning,
                        title="[bold yellow]🧠 Model Chain-of-Thought Reasoning[/bold yellow]",
                        border_style="yellow",
                    )
                )

            if assistant_text and not tool_calls:
                console.print(
                    Panel(
                        assistant_text,
                        title="[bold green]Assistant Response[/bold green]",
                        border_style="green",
                    )
                )
                return {"status": "completed", "output": assistant_text, "turns": turn}

            # Process Tool Calls
            if not tool_calls:
                console.print("[dim]No tool calls generated. Finishing task.[/dim]")
                break

            for tc in tool_calls:
                name = tc.get("name")
                raw_args = tc.get("arguments", {})
                
                if isinstance(raw_args, str):
                    repaired, err = repair_json_string(raw_args)
                    args = repaired if repaired is not None else {}
                else:
                    args = raw_args

                # Normalize types (e.g. string line numbers to ints)
                args = normalize_tool_arguments(name, args)

                # 1. Repeat Gate Check
                rep_ok, rep_err = self.repeat_gate.record_and_check(name, args)
                if not rep_ok:
                    console.print(f"[bold red]⛔ {rep_err}[/bold red]")
                    self.circuit_breaker.record_outcome(False)
                    break

                # 2. Syntax Gate Check for file writes
                if name in ("replace_file_content", "write_to_file"):
                    code = args.get("replacement_content") or args.get(
                        "code_content", ""
                    )
                    syn_ok, syn_err = SyntaxGate.verify(code)
                    if not syn_ok:
                        console.print(
                            f"[bold red]⛔ Syntax Gate Rejected Code: {syn_err}[/bold red]"
                        )
                        self.circuit_breaker.record_outcome(False)
                        continue

                # 3. Diff Gate Check
                if name == "replace_file_content":
                    target = args.get("target_content", "")
                    repl = args.get("replacement_content", "")
                    diff_ok, diff_err = DiffGate.verify(target, repl)
                    if not diff_ok:
                        console.print(f"[bold red]⛔ {diff_err}[/bold red]")
                        self.circuit_breaker.record_outcome(False)
                        continue

                # 4. Dispatch Tool
                console.print(
                    f"[bold cyan]⚡ Tool Call:[/bold cyan] [yellow]{name}[/yellow] args={json.dumps(args)}"
                )
                start_tool = time.perf_counter()
                result_json = dispatch_tool(name, args)
                tool_ms = (time.perf_counter() - start_tool) * 1000.0

                console.print(
                    Panel(
                        Syntax(result_json, "json", theme="monokai"),
                        title=f"[bold green]Tool Result ({tool_ms:.1f}ms)[/bold green]",
                        border_style="green",
                    )
                )

                self.circuit_breaker.record_outcome(True)

            # If tool calls executed, provide loop summary
            break

        return {"status": "completed", "turns": turn}

    def _call_model_endpoint(self, prompt: str) -> Optional[Dict[str, Any]]:
        """Dispatches to LM Studio /v1/responses."""
        endpoint = f"{self.base_url}/v1/responses"
        payload = {
            "model": self.active_model_id,
            "input": prompt,
            "tools": TOOLS_SCHEMAS,
            "tool_choice": "auto",
        }

        with Progress(
            SpinnerColumn(),
            TextColumn(f"[bold magenta]Inference ({self.active_model_id})..."),
            transient=True,
        ) as p:
            p.add_task("call", total=None)
            try:
                with httpx.Client(timeout=180.0) as client:
                    resp = client.post(endpoint, json=payload)
                    resp.raise_for_status()
                    data = resp.json()
            except Exception as e:
                console.print(f"[bold red]❌ Model connection failed: {e}[/bold red]")
                return None

        tool_calls = []
        reasoning_text = None
        assistant_content = None

        if "output" in data:
            for item in data.get("output", []):
                t = item.get("type")
                if t == "reasoning":
                    for c in item.get("content", []):
                        if c.get("type") == "reasoning_text":
                            reasoning_text = c.get("text")
                elif t == "function_call":
                    tool_calls.append(
                        {
                            "name": item.get("name"),
                            "arguments": item.get("arguments", {}),
                        }
                    )
                elif t == "message":
                    for c in item.get("content", []):
                        if c.get("type") == "output_text":
                            assistant_content = c.get("text")

        if not tool_calls and "choices" in data:
            for ch in data.get("choices", []):
                msg = ch.get("message", {})
                for tc in msg.get("tool_calls", []):
                    fn = tc.get("function", {})
                    tool_calls.append(
                        {"name": fn.get("name"), "arguments": fn.get("arguments", "{}")}
                    )
                assistant_content = msg.get("content")

        return {
            "tool_calls": tool_calls,
            "reasoning": reasoning_text,
            "content": assistant_content,
        }
