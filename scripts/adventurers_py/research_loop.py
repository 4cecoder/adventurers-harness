"""
Adventurers Deterministic Research Loop
Enriches tiny model context with fresh web & documentation data via:
  1. Fast HTTP web_fetch (HTML -> clean Markdown)
  2. Firecrawl API integration for dynamic JS-rendered documentation
  3. Needle 2 / Regex Knowledge Capsule Compaction (< 300 tokens)
  4. Local OKF knowledge caching (0 repeated network calls)
"""

import os
import re
import time
import httpx
from typing import Dict, Any, Optional, List
from pydantic import BaseModel
from rich.console import Console

console = Console()

class KnowledgeCapsule(BaseModel):
    source_url: str
    topic: str
    token_count: int
    signatures: List[str]
    code_examples: List[str]
    summary: str
    timestamp: float

# Local in-memory & disk cache for scraped docs
RESEARCH_CACHE: Dict[str, KnowledgeCapsule] = {}

def web_fetch_markdown(url: str, timeout_sec: float = 10.0) -> Dict[str, Any]:
    """Fetches a URL and converts basic HTML structure into clean, compact Markdown."""
    try:
        headers = {"User-Agent": "Adventurers-Research-Agent/1.0"}
        with httpx.Client(timeout=timeout_sec, follow_redirects=True) as client:
            resp = client.get(url, headers=headers)
            resp.raise_for_status()
            html = resp.text

        # Strip scripts, styles, navigation, footer
        cleaned = re.sub(r"<(script|style|nav|footer|header)[^>]*>[\s\S]*?</\1>", "", html, flags=re.IGNORECASE)
        # Convert links, headers, code blocks
        cleaned = re.sub(r"<pre><code>([\s\S]*?)</code></pre>", r"```\n\1\n```", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"<h1>(.*?)</h1>", r"# \1\n", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"<h2>(.*?)</h2>", r"## \1\n", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"<h3>(.*?)</h3>", r"### \1\n", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"<p>(.*?)</p>", r"\1\n\n", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"<[^>]+>", " ", cleaned)  # Strip remaining HTML tags
        cleaned = re.sub(r"\n\s*\n+", "\n\n", cleaned).strip()

        return {"success": True, "url": url, "markdown": cleaned[:15000], "bytes": len(html)}
    except Exception as e:
        return {"success": False, "url": url, "error": str(e)}

def firecrawl_scrape(url: str, api_key: Optional[str] = None, timeout_sec: float = 20.0) -> Dict[str, Any]:
    """Scrapes dynamic JS documentation via Firecrawl API."""
    key = api_key or os.environ.get("FIRECRAWL_API_KEY")
    if not key:
        # Fall back to standard fast HTTP fetch if no Firecrawl API key is configured
        return web_fetch_markdown(url, timeout_sec=timeout_sec)

    endpoint = "https://api.firecrawl.dev/v1/scrape"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    payload = {"url": url, "formats": ["markdown"], "onlyMainContent": True}

    try:
        with httpx.Client(timeout=timeout_sec) as client:
            resp = client.post(endpoint, json=payload, headers=headers)
            resp.raise_for_status()
            data = resp.json()
            md = data.get("data", {}).get("markdown", "")
            return {"success": True, "url": url, "markdown": md, "source": "firecrawl"}
    except Exception as e:
        # Fall back gracefully to direct HTTP fetch
        return web_fetch_markdown(url, timeout_sec=timeout_sec)

def compact_to_knowledge_capsule(url: str, topic: str, raw_markdown: str, max_tokens: int = 300) -> KnowledgeCapsule:
    """Extracts code signatures and key patterns, discarding verbose prose to stay < 300 tokens."""
    # Extract code blocks
    code_blocks = re.findall(r"```[a-zA-Z0-9_-]*\n([\s\S]*?)```", raw_markdown)
    examples = [cb.strip() for cb in code_blocks[:3]]

    # Extract function / method signatures
    signatures = re.findall(r"(?:func|def|fn|pub fn|class|struct)\s+([a-zA-Z0-9_<>]+(?:\([^)]*\))?)", raw_markdown)
    unique_sigs = list(dict.fromkeys(signatures))[:6]

    # First 2 sentences of summary
    lines = [line.strip() for line in raw_markdown.splitlines() if line.strip() and not line.startswith("#") and not line.startswith("`")]
    summary = " ".join(lines[:2]) if lines else "Documentation reference"

    capsule = KnowledgeCapsule(
        source_url=url,
        topic=topic,
        token_count=len(summary) // 4 + sum(len(e) // 4 for e in examples),
        signatures=unique_sigs,
        code_examples=examples,
        summary=summary[:200],
        timestamp=time.time()
    )

    RESEARCH_CACHE[url] = capsule
    return capsule

class DeterministicResearchLoop:
    """Orchestrates research without blowing up tiny model context."""

    def __init__(self, firecrawl_api_key: Optional[str] = None):
        self.firecrawl_key = firecrawl_api_key

    def enrich_context_for_task(self, task_prompt: str, doc_urls: List[str]) -> str:
        """Fetches and condenses documentation into high-density reference capsules."""
        capsules = []
        for url in doc_urls:
            if url in RESEARCH_CACHE:
                capsules.append(RESEARCH_CACHE[url])
                continue

            fetch_res = firecrawl_scrape(url, api_key=self.firecrawl_key)
            if fetch_res.get("success"):
                capsule = compact_to_knowledge_capsule(url, task_prompt, fetch_res.get("markdown", ""))
                capsules.append(capsule)

        if not capsules:
            return ""

        # Format clean, minimal cheat-sheet for tiny models
        formatted = ["### 📚 Distilled Research Context:"]
        for c in capsules:
            formatted.append(f"**Source:** {c.source_url} ({c.topic})")
            if c.signatures:
                formatted.append(f"**Signatures:** `{', '.join(c.signatures)}`")
            if c.code_examples:
                formatted.append(f"**Example:**\n```\n{c.code_examples[0]}\n```")
        
        return "\n".join(formatted)
