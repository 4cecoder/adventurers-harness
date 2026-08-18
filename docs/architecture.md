# Architecture

## Overview

Adventurers Harness is a native macOS application written in Swift 6 that serves as a coding agent harness. It manages multiple AI coding agents running in parallel, providing a unified interface for task management, code review, and agent orchestration.

## Core Philosophy

**The model proposes. The harness certifies.**

This is borrowed from the autoreverse project. The LLM never decides when a task is complete. Instead, a pipeline of deterministic gates (syntax checking, repeat detection, compilation, structural verification) certifies completion. This prevents hallucinated "I'm done" states.

## Module Architecture

### AdventurersCore

The heart of the harness. Contains:

- **Protocols**: `LLMProvider`, `Tool`, `Gate` — protocol-oriented abstractions
- **AgentLoop**: The propose → gate → certify execution cycle
- **TaskContract**: Immutable task boundaries with round budgets
- **StateEngine**: Finite state machine with enforced transitions
- **Gates**: Deterministic certification checks
- **FailChain**: Escalating capsule feedback for repeated failures
- **EventJournal**: Append-only JSONL event store

### GUI

Native macOS SwiftUI application with:

- Three-panel layout (sidebar, content, inspector)
- Thread-based multi-agent management
- Real-time gate progress visualization
- Diff review (side-by-side and unified)
- Skills library management
- Permission system for tool execution

### LLMProviders

Provider abstraction layer supporting OpenAI, Anthropic, local models, and CLI-wrapped agents.

### Tools

Built-in tools: bash execution, file operations, grep, glob, fetch.

## Data Flow

```
User Input
    ↓
AgentLoop.execute(task)
    ↓
┌─→ LLMProvider.send(messages) ──→ Response
│   ↓
│   Tool execution (if tool calls)
│   ↓
│   Gate evaluation (deterministic)
│   ├── SyntaxGate: balanced braces/parens
│   ├── RepeatGate: reject identical submissions
│   ├── CompilationGate: compile check
│   ├── MemoryGate: address validation
│   └── ObjectiveGate: structural verification
│   ↓
│   All gates passed? → YES → TaskResult.success
│   ↓ NO
│   FailChain.mitigate() → escalating feedback
│   ↓
└─── Loop back to LLMProvider
```

## State Machine

```
idle → taskingested → proposing → validatingSyntax → compiling → executingTest → verified
                ↓           ↓              ↓              ↓            ↓
              failed      failed        retrying       retrying     retrying
                ↓           ↓              ↓              ↓            ↓
              idle        idle          proposing      proposing    proposing
```

## Design Patterns

### Protocol-Oriented Abstraction

Both LLM providers and tools are defined as protocols. This allows:
- Multiple implementations per protocol
- Compile-time conformance checking
- Easy testing with mock implementations

### Factory / Registry

Providers are created from configuration via a registry pattern. The registry maps provider names to concrete types.

### Contract-Based Budget Control

`TaskContract` defines maximum rounds, required gates, and task metadata. It is immutable during execution. The `bumpRound()` method throws when budget is exhausted.

### Event Journal

Every phase transition, gate check, and model turn is logged as a structured JSONL event. This enables replay, debugging, and analytics.

### Escalating Capsule Feedback

When the same gate fails repeatedly, the feedback escalates in severity:
1. First failure: gentle hint
2. Second: stern directive
3. Third+: critical escalation with specific fix instructions

## UI Architecture

### Three-Panel Layout

```
┌─────────────┬──────────────────────┬─────────────┐
│             │                      │             │
│  Sidebar    │    Content Area      │  Inspector  │
│  (Threads)  │  (Chat / Diff /      │  (Gates /   │
│             │   Code Review)       │   Tools)    │
│             │                      │             │
└─────────────┴──────────────────────┴─────────────┘
```

### Thread Management

Each agent task runs in its own thread. Threads are organized by status (active/completed) and can be created, renamed, duplicated, and exported.

### Gate Progress Visualization

Real-time horizontal progress bar showing each gate's status:
- Pending (gray) → Running (orange pulse) → Passed (green glow) or Failed (red shake)
- All gates passed triggers a celebration animation

### Permission System

Tool execution requires permission based on risk level:
- **readOnly**: Auto-approved (grep, glob, ls)
- **network**: Prompt for approval (fetch, search)
- **write**: Prompt for approval (file edit, patch)
- **execute**: Prompt with countdown (bash, shell)
- **destructive**: Always prompt (force push, rm -rf)
