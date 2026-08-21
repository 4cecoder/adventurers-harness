"""
Unit tests for Deterministic Research Loop and Knowledge Capsule Compactor.
"""

from adventurers_py.research_loop import (
    compact_to_knowledge_capsule,
    DeterministicResearchLoop,
    KnowledgeCapsule,
    RESEARCH_CACHE
)

def test_markdown_to_knowledge_capsule_compaction():
    sample_md = """
    # Firecrawl Scraper API Reference
    Firecrawl turns websites into clean markdown. It handles dynamic javascript rendering.

    ## Function Signatures
    func scrapeUrl(endpoint: String) -> Markdown
    def extract_tables(html: str) -> list

    ## Example Usage
    ```python
    import firecrawl
    app = firecrawl.App(api_key="fc-123")
    res = app.scrape_url("https://example.com")
    ```
    """
    
    capsule = compact_to_knowledge_capsule("https://docs.firecrawl.dev", "Web Scraping", sample_md)
    assert capsule.source_url == "https://docs.firecrawl.dev"
    assert len(capsule.code_examples) > 0
    assert "firecrawl" in capsule.code_examples[0]
    assert capsule.token_count < 300
    assert "https://docs.firecrawl.dev" in RESEARCH_CACHE

def test_research_loop_context_enrichment():
    loop = DeterministicResearchLoop()
    # Mock cache entry
    RESEARCH_CACHE["https://example.com/api"] = KnowledgeCapsule(
        source_url="https://example.com/api",
        topic="Mock API",
        token_count=50,
        signatures=["func execute() -> Bool"],
        code_examples=["let ok = execute()"],
        summary="Mock API reference summary",
        timestamp=100.0
    )

    enriched = loop.enrich_context_for_task("Call execute API", ["https://example.com/api"])
    assert "### 📚 Distilled Research Context:" in enriched
    assert "func execute() -> Bool" in enriched
    assert "let ok = execute()" in enriched
