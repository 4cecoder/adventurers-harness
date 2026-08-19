# Real-Time Telemetry, Throughput & Metering

> High-precision performance observability, token accounting, and cost tracking for autonomous coding agents.

---

## Overview

Unlike standard chat interfaces that only report token counts upon turn completion, research-grade coding harnesses require live telemetry to evaluate agent execution speed, latency bottlenecks, and context memory saturation.

---

## Telemetry Architecture

The telemetry engine consists of two interconnected layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    AdventurersCore Target                   │
│                                                             │
│  ModelSpec & ModelPricingRegistry ──► Cost Ledger ($ USD)   │
│  TurnMetrics Record               ──► Historical Analytics  │
│  ContextHealthStatus              ──► Headroom Categorizer  │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                          GUI Target                         │
│                                                             │
│  RollingTokenTracker              ──► 1.2s Rolling TPS      │
│  ThreadMeteringState (@Observable)──► SwiftUI Live State    │
│  WorkbenchStatusBar               ──► Docked Status Bar     │
│  TelemetryDetailPopover           ──► Interactive Inspector │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Metrics Computed

### 1. Rolling Tokens Per Second (TPS)
- Computed during active streaming generation via `RollingTokenTracker`.
- Uses a high-resolution sliding window ($1.2\text{s}$) to smooth network buffer jitter and accurately calculate instantaneous generation velocity:
  $$\text{TPS} = \frac{\sum \text{Tokens in Window}}{\Delta t_{\text{window}}}$$
- Records both **Current TPS** and **Peak Burst TPS** for every turn.

### 2. Time-to-First-Token (TTFT)
- Measures latency (in milliseconds) from the moment the HTTP request or CLI process is dispatched until the arrival of the first output token.
- Crucial for diagnosing provider routing delays and cold-start overhead.

### 3. Context Window Capacity Meter
- Tracks the total conversation token consumption (system prompt + user messages + assistant messages + tool calls + tool results) against the active model's maximum limit ($128\text{k}$ to $1\text{M}$).
- Automatically classifies context health:
  - `🟢 Optimal`: $<50\%$ context used.
  - `🔵 Moderate`: $50\% - 70\%$ context used.
  - `🟡 High Load`: $70\% - 85\%$ context used.
  - `🔴 Critical`: $>85\%$ context used (triggers trajectory compaction recommendation).

### 4. Dynamic Multi-Model Pricing Ledger
- Maps model families to their current pricing schedules:
  - **Claude 3.7 / 3.5 Sonnet**: $\$3.00$ / $\$15.00$ per 1M tokens
  - **Claude 3.5 Haiku**: $\$0.80$ / $\$4.00$ per 1M tokens
  - **GPT-4o**: $\$2.50$ / $\$10.00$ per 1M tokens
  - **GPT-4o mini**: $\$0.15$ / $\$0.60$ per 1M tokens
  - **DeepSeek V3 / Flash**: $\$0.14$ / $\$0.28$ per 1M tokens
  - **DeepSeek R1 (Reasoner)**: $\$0.55$ / $\$2.19$ per 1M tokens
  - **GLM-5.3**: $\$1.00$ / $\$2.00$ per 1M tokens
  - **MiniMax M2.7 / M3**: $\$0.15$ / $\$0.50$ per 1M tokens ($1\text{M}$ context)
  - **OpenCode MiMo-V2.5**: $\$0.10$ / $\$0.20$ per 1M tokens
