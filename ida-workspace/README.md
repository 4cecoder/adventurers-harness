# IDA Workspace

## Setup

1. Download Codex macOS binary:
   ```bash
   curl -L https://github.com/openai/codex/releases/latest/download/codex-aarch64-apple-darwin.tar.gz -o codex.tar.gz
   tar xzf codex.tar.gz
   mv codex-aarch64-apple-darwin codex
   ```

2. Open in IDA Pro:
   - File → Open → select `codex`
   - Processor: ARM64 (Apple Silicon)
   - FLIRT: Auto-detect Swift/Rust signatures

3. Run analysis scripts in `scripts/`

## Binary Analysis Log

| Date | Action | Result |
|------|--------|--------|
| | Import binary | |
| | Fast analysis | |
| | String analysis | |
| | Function mapping | |

## Key Findings

(To be filled during analysis)
