# IDA Pro Reverse Engineering — Codex Binary

## Objective

Reverse engineer the OpenAI Codex macOS desktop app binary to understand:
- Internal architecture and module organization
- LLM communication protocols
- Tool execution patterns
- Permission system implementation
- UI framework choices and integration

## Setup

### Prerequisites

- IDA Pro 8.3+ with FLIRT signatures for Swift/Rust
- macOS binary: `codex-aarch64-apple-darwin` (download from GitHub Releases)
- IDA Python 3.x

### Binary Location

Download the Codex macOS binary from:
```
https://github.com/openai/codex/releases/latest
```

File: `codex-aarch64-apple-darwin.tar.gz`

### IDA Analysis Steps

1. **Import**: File → Open → select the binary
2. **Processor**: ARM64 (Apple Silicon)
3. **FLIRT**: Auto-detect → Swift runtime + Apple frameworks
4. **Fast scan**: Analyze → Fast → Full
5. **Function scan**: Analyze → Functions → Armscan

### Key Areas to Investigate

#### 1. LLM Communication

Search for:
- String references containing `api.openai.com`
- HTTP/HTTPS client initialization
- JSON serialization for API requests
- Streaming response parsing (SSE/NDJSON)

#### 2. Agent Loop

Look for:
- Main execution loop (likely in `main` or `agent` module)
- Tool dispatch table
- Message history management
- Token counting logic

#### 3. Sandbox/Permissions

Search for:
- `sandbox_init` calls
- `exec` / `posix_spawn` wrappers
- File system access control
- Network permission checks

#### 4. Configuration

Look for:
- `AGENTS.md` parsing
- Environment variable reads
- Config file loading
- Model selection logic

### IDA Python Scripts

Create scripts in `ida-workspace/scripts/`:

```python
# ida-workspace/scripts/find_api_calls.py
# Find all OpenAI API endpoint references

import idautils
import idc

def find_string_refs(search_str):
    refs = []
    for head in idautils.Heads():
        if idc.get_operand_type(head) == idc.o_mem:
            addr = idc.get_operand_value(head)
            s = idc.get_strlit_contents(addr)
            if s and search_str in s.decode('utf-8', errors='ignore'):
                refs.append(head)
    return refs

# Find API endpoints
for ref in find_string_refs("api.openai.com"):
    print(f"API reference at 0x{ref:x}")
```

```python
# ida-workspace/scripts/find_tool_dispatch.py
# Find tool dispatch patterns (function calls to tool handlers)

import idautils

for func_ea in idautils.Functions():
    name = idc.get_func_name(func_ea)
    if any(tool in name.lower() for tool in ['bash', 'file', 'grep', 'glob', 'execute']):
        print(f"Tool handler: {name} at 0x{func_ea:x}")
```

### Notes

- Codex is written in **Rust** (codex-rs directory in repo)
- Look for Rust-specific patterns: panic handlers, allocator wrappers
- Swift interop may be minimal (pure Rust binary)
- Check for bundled assets or embedded resources

## Progress Tracking

| Area | Status | Notes |
|------|--------|-------|
| Import | Pending | |
| Fast Analysis | Pending | |
| API Endpoints | Pending | |
| Agent Loop | Pending | |
| Sandbox | Pending | |
| Config | Pending | |
