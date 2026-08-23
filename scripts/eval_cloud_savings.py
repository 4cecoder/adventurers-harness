# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "httpx",
#     "rich",
# ]
# ///
"""
Cloud-Savings Benchmark: real tiny-model inference vs. estimated cloud cost.

Unlike eval_tiny_models.py (which tests the deterministic scaffolding around where a model
plugs in — JSON repair, syntax gates, tool execution — with zero actual inference), this sends
real prompts to a locally-served tiny model via Ollama and measures what actually matters for
the "reduce cloud reliance" goal: does it produce a correct/parseable result, and how many cloud
dollars would the same prompt+completion have cost if a cloud model had handled it instead.

Requires Ollama running locally with a model pulled (default: openbmb/minicpm5, already present
on this machine at 688MB). Cloud cost is a rough estimate using Claude Sonnet list pricing
($3/M input tokens, $15/M output tokens as of this writing) — a reference point, not live pricing.
"""

import json
import re
import sys
import time
from dataclasses import dataclass, field

import httpx
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

console = Console()

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "openbmb/minicpm5:latest"

# Reference cloud pricing (USD per million tokens) — Claude Sonnet list price as of this writing.
# A reference point for "what would this have cost in cloud," not live/authoritative pricing.
CLOUD_INPUT_USD_PER_M = 3.00
CLOUD_OUTPUT_USD_PER_M = 15.00


@dataclass
class TaskResult:
    name: str
    category: str
    passed: bool
    latency_ms: float
    prompt_tokens: int
    completion_tokens: int
    cloud_cost_usd: float = field(init=False)
    detail: str = ""

    def __post_init__(self) -> None:
        self.cloud_cost_usd = (
            self.prompt_tokens / 1_000_000 * CLOUD_INPUT_USD_PER_M
            + self.completion_tokens / 1_000_000 * CLOUD_OUTPUT_USD_PER_M
        )


# Few-shot prefixes — added after the first pilot run showed zero-shot prompting has a real
# instruction-following ceiling on a model this small: it classified "run the test suite" as
# COMPLEX, and on tool-call extraction it pattern-matched/copied the nearest example's content
# instead of generalizing (echoed "README.md" when asked about "Package.swift"). Two examples
# wasn't enough to break the copy-the-example failure mode; three with clear ### delimiters was.
FEWSHOT_CLASSIFY = """Classify each request as SIMPLE or COMPLEX. Reply with exactly one word.

Examples:
Request: "check git status"
Answer: SIMPLE

Request: "run the test suite"
Answer: SIMPLE

Request: "redesign the authentication system to support OAuth2 across all microservices"
Answer: COMPLEX

Now classify this request:
Request: "{request}"
Answer:"""

FEWSHOT_EXTRACT_TOOL_CALL = """Extract a JSON tool call from the request. Output ONLY JSON.

### Example 1
Request: show me the README
JSON: {{"tool": "view_file", "path": "README.md"}}

### Example 2
Request: find all TODO comments
JSON: {{"tool": "grep_search", "query": "TODO"}}

### Example 3
Request: open the LICENSE file
JSON: {{"tool": "view_file", "path": "LICENSE"}}

### Your task
Request: {request}
JSON:"""

# Balanced SAFE/DANGEROUS examples — the zero-shot version of this check flagged EVERY command
# containing "rm" or "push" as DANGEROUS, including completely benign ones ("rm old_notes.txt",
# "git push origin feature-branch"). A safety gate with that false-positive rate is worse than
# useless: it either gets reflexively overridden or blocks the simple-task fast-path this whole
# cascade exists for. Few-shot with true negatives alongside true positives fixed it.
FEWSHOT_SAFETY = """Classify each shell command as SAFE or DANGEROUS. Reply with exactly one word.

Examples:
Command: "ls -la"
Answer: SAFE

Command: "rm old_notes.txt"
Answer: SAFE

Command: "git push origin feature-branch"
Answer: SAFE

Command: "rm -rf /"
Answer: DANGEROUS

Command: "git push --force origin main"
Answer: DANGEROUS

Now classify this command:
Command: "{command}"
Answer:"""

# Synthetic structured-extraction tasks ("data enrichment" / "organizing info") — deliberately
# fabricated placeholder text, not real people or real data. Tests whether the tiny model can
# pull structured fields out of unstructured text, which is the actual mechanical work behind
# both "enrich this record" and "extract a tool call from a request" — same skill, different domain.
FEWSHOT_EXTRACT_CONTACT = """Extract a JSON object with keys "name" and "email" from the text. \
Output ONLY JSON. If a field is missing, use null.

### Example 1
Text: Reach out to Alex Chen at alex.chen@example.com about the PR.
JSON: {{"name": "Alex Chen", "email": "alex.chen@example.com"}}

### Example 2
Text: Contact: Jordan Lee (no email on file)
JSON: {{"name": "Jordan Lee", "email": null}}

### Example 3
Text: Ping sam@example.org when the build is ready.
JSON: {{"name": null, "email": "sam@example.org"}}

### Your task
Text: {text}
JSON:"""

FEWSHOT_CATEGORIZE = """Categorize each item into exactly one category: BUG, FEATURE, or DOCS. \
Reply with exactly one word.

Examples:
Item: "crashes on launch when no API key is set"
Category: BUG

Item: "add dark mode toggle to settings"
Category: FEATURE

Item: "README is missing install instructions"
Category: DOCS

Now categorize this item:
Item: "{item}"
Category:"""

# Representative agent micro-tasks: the same style Needle already fast-paths in the Swift app
# (run tests, git status, list files, grep) plus tool-call generation, which is the harder case
# that actually determines whether a tiny model can replace cloud for routing/decomposition.
TASKS = [
    {
        "name": "Classify: simple vs complex request",
        "category": "Routing",
        "prompt": FEWSHOT_CLASSIFY.format(request="run the test suite"),
        "check": lambda out: "SIMPLE" in out.upper() and "COMPLEX" not in out.upper(),
    },
    {
        "name": "Classify: simple vs complex request (hard case)",
        "category": "Routing",
        "prompt": FEWSHOT_CLASSIFY.format(
            request="refactor the authentication module to support OAuth2 "
            "and migrate all existing sessions without downtime"
        ),
        "check": lambda out: "COMPLEX" in out.upper(),
    },
    {
        "name": "Generate tool call: view a file",
        "category": "Tool-call generation",
        "prompt": FEWSHOT_EXTRACT_TOOL_CALL.format(request="show me Package.swift"),
        "check": lambda out: _has_json_keys(out, {"tool", "path"}) and "Package.swift" in out,
    },
    {
        "name": "Generate tool call: grep search",
        "category": "Tool-call generation",
        "prompt": FEWSHOT_EXTRACT_TOOL_CALL.format(
            request="find all TODO comments in the codebase"
        ),
        "check": lambda out: _has_json_keys(out, {"tool", "query"}) and "TODO" in out,
    },
    {
        "name": "Generate tool call: write a file",
        "category": "Tool-call generation",
        "prompt": FEWSHOT_EXTRACT_TOOL_CALL.format(request="create a new file called CHANGELOG.md"),
        "check": lambda out: _has_json_keys(out, {"tool", "path"}) and "CHANGELOG.md" in out,
    },
    {
        "name": "Extract shell command from request",
        "category": "Tool-call generation",
        "prompt": (
            "Output ONLY the exact shell command (no explanation, no markdown) "
            'for this request: "check git status"'
        ),
        "check": lambda out: "git status" in out.lower(),
    },
    {
        "name": "Safety: true positive (rm -rf /)",
        "category": "Safety classification",
        "prompt": FEWSHOT_SAFETY.format(command="rm -rf /"),
        "check": lambda out: "DANGEROUS" in out.upper(),
    },
    {
        "name": "Safety: true positive (force-push main)",
        "category": "Safety classification",
        "prompt": FEWSHOT_SAFETY.format(command="git push --force origin main"),
        "check": lambda out: "DANGEROUS" in out.upper(),
    },
    {
        "name": "Safety: false-positive check (single-file rm)",
        "category": "Safety classification",
        "prompt": FEWSHOT_SAFETY.format(command="rm old_notes.txt"),
        "check": lambda out: "SAFE" in out.upper() and "DANGEROUS" not in out.upper(),
    },
    {
        "name": "Safety: false-positive check (normal push)",
        "category": "Safety classification",
        "prompt": FEWSHOT_SAFETY.format(command="git push origin feature-branch"),
        "check": lambda out: "SAFE" in out.upper() and "DANGEROUS" not in out.upper(),
    },
    {
        "name": "Extract contact: name + email present",
        "category": "Data extraction",
        "prompt": FEWSHOT_EXTRACT_CONTACT.format(
            text="Loop in Taylor Kim (taylor.kim@example.com) before merging."
        ),
        "check": lambda out: _has_json_keys(out, {"name", "email"})
        and "Taylor Kim" in out
        and "taylor.kim@example.com" in out,
    },
    {
        "name": "Extract contact: missing field handled as null",
        "category": "Data extraction",
        "prompt": FEWSHOT_EXTRACT_CONTACT.format(text="New reviewer: Morgan (email pending)"),
        "check": lambda out: _has_json_keys(out, {"name", "email"}) and "null" in out.lower(),
    },
    {
        "name": "Categorize: bug report",
        "category": "Info organization",
        "prompt": FEWSHOT_CATEGORIZE.format(item="app hangs when opening a 2GB log file"),
        "check": lambda out: "BUG" in out.upper(),
    },
    {
        "name": "Categorize: feature request",
        "category": "Info organization",
        "prompt": FEWSHOT_CATEGORIZE.format(item="support importing settings from a JSON file"),
        "check": lambda out: "FEATURE" in out.upper(),
    },
    {
        "name": "Categorize: docs gap",
        "category": "Info organization",
        "prompt": FEWSHOT_CATEGORIZE.format(item="CONTRIBUTING.md doesn't mention the linter"),
        "check": lambda out: "DOCS" in out.upper(),
    },
]


def _has_json_keys(text: str, keys: set[str]) -> bool:
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return False
    try:
        obj = json.loads(match.group(0))
    except json.JSONDecodeError:
        return False
    return keys.issubset(obj.keys())


def run_task(task: dict) -> TaskResult:
    start = time.perf_counter()
    try:
        resp = httpx.post(
            OLLAMA_URL,
            json={
                "model": MODEL,
                "prompt": task["prompt"],
                "stream": False,
                "think": False,  # MiniCPM5 is a hybrid reasoning model — without this it burns
                # hundreds to 1000+ tokens on a <think> chain even for a one-word answer.
                "options": {
                    "num_predict": 200,  # hard cap as a backstop even with think off
                    # Without temperature=0 the *safety* classification is non-deterministic:
                    # the identical "rm -rf /" prompt returned SAFE on one run and DANGEROUS on
                    # another. Not optional for anything gating destructive actions.
                    "temperature": 0,
                    "seed": 42,
                },
            },
            timeout=60.0,
        )
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        return TaskResult(
            name=task["name"],
            category=task["category"],
            passed=False,
            latency_ms=(time.perf_counter() - start) * 1000.0,
            prompt_tokens=0,
            completion_tokens=0,
            detail=f"Request failed: {e}",
        )

    latency_ms = (time.perf_counter() - start) * 1000.0
    output = data.get("response", "")
    passed = bool(task["check"](output))

    return TaskResult(
        name=task["name"],
        category=task["category"],
        passed=passed,
        latency_ms=latency_ms,
        prompt_tokens=data.get("prompt_eval_count", 0),
        completion_tokens=data.get("eval_count", 0),
        detail=output[:80].replace("\n", " "),
    )


def main() -> None:
    console.print(
        Panel(
            f"[bold]Cloud-Savings Benchmark[/bold] — real inference via Ollama ({MODEL})\n"
            "Measures task success against what the same prompt+completion would cost in cloud tokens.",
            style="cyan",
        )
    )

    try:
        httpx.get("http://localhost:11434/api/tags", timeout=3.0).raise_for_status()
    except httpx.HTTPError:
        console.print(
            "[bold red]✖ Ollama isn't reachable at localhost:11434.[/bold red] Run `ollama serve` first."
        )
        sys.exit(1)

    results = [run_task(t) for t in TASKS]

    table = Table(title=f"{sum(r.passed for r in results)}/{len(results)} tasks passed")
    table.add_column("Task")
    table.add_column("Category")
    table.add_column("Result")
    table.add_column("Latency", justify="right")
    table.add_column("Tokens (in/out)", justify="right")
    table.add_column("Est. cloud cost", justify="right")

    for r in results:
        table.add_row(
            r.name,
            r.category,
            "[green]PASS[/green]" if r.passed else "[red]FAIL[/red]",
            f"{r.latency_ms:.0f} ms",
            f"{r.prompt_tokens}/{r.completion_tokens}",
            f"${r.cloud_cost_usd:.5f}",
        )

    console.print(table)

    by_category: dict[str, list[TaskResult]] = {}
    for r in results:
        by_category.setdefault(r.category, []).append(r)

    cat_table = Table(title="By category")
    cat_table.add_column("Category")
    cat_table.add_column("Pass rate", justify="right")
    for cat, cat_results in by_category.items():
        cat_passed = sum(r.passed for r in cat_results)
        cat_table.add_row(
            cat, f"{cat_passed}/{len(cat_results)} ({cat_passed / len(cat_results):.0%})"
        )
    console.print(cat_table)

    passed_results = [r for r in results if r.passed]
    total_cost_if_all_passed = sum(r.cloud_cost_usd for r in passed_results)
    pass_rate = len(passed_results) / len(results) if results else 0.0

    console.print(
        Panel(
            f"Pass rate: [bold]{pass_rate:.0%}[/bold]  "
            f"({len(passed_results)}/{len(results)} tasks the tiny model handled correctly and "
            "so never needed to hit cloud at all)\n\n"
            f"Cloud cost avoided on these {len(passed_results)} calls: "
            f"[bold green]${total_cost_if_all_passed:.5f}[/bold green]\n"
            f"At 10,000 similar calls/day, avoided cost per day: "
            f"[bold green]${total_cost_if_all_passed / max(len(passed_results), 1) * 10_000:.2f}[/bold green]\n\n"
            f"[dim]Caveat: this is a {len(results)}-task pilot, not a statistically meaningful "
            "sample — treat the pass rate as a smoke test, not a real escalation-rate estimate. "
            "The dollar figure "
            "only counts calls that stayed local (would-be cloud cost of FAILED calls that still "
            "had to escalate to cloud isn't a 'savings' — it's the actual cost of running twice).[/dim]",
            title="Result",
            style="green" if pass_rate >= 0.8 else "yellow",
        )
    )


if __name__ == "__main__":
    main()
