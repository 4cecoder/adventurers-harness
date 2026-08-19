# Getting Started with Adventurers Harness

Welcome to **Adventurers Harness**! This quickstart guide walks you through installation, first launch, setting up API keys or Meta-Harness CLIs, and running your first gate-certified task.

---

## ⚡ Installation Options

### Option 1: Homebrew Tap (Recommended)
```bash
# Add the Adventurers repository tap
brew tap 4cecoder/adventurers https://github.com/4cecoder/adventurers-harness

# Install the harness app & CLI
brew install adventurers

# Launch from terminal
adventurers
```

### Option 2: Standalone Disk Image (DMG)
1. Download **[Adventurers-macOS-arm64.dmg](https://github.com/4cecoder/adventurers-harness/releases/download/latest/Adventurers-macOS-arm64.dmg)** from GitHub Releases.
2. Open the `.dmg` disk image.
3. Drag `Adventurers.app` to your `/Applications` folder.
4. Launch `Adventurers` from Spotlight or Launchpad.

---

## ⚙️ Choosing Your Execution Mode

Adventurers Harness offers two execution paradigms in the top bar:

### 1. 🛡️ Coding Plan (Direct LLM Streaming)
- Direct streaming connection with **OpenCode Go Cloud**, **Anthropic Claude 3.7**, **Google Gemini**, **OpenAI**, or **GLM-4**.
- Every synthesized diff passes through the **6-Gate Deterministic Certification Pipeline** (`SyntaxGate`, `RepeatGate`, `CompilationGate`, `DiffGate`, `MemoryGate`, `ObjectiveGate`).
- Code changes are protected by **Darwin Seatbelt kernel sandboxing**.

### 2. 🔀 Meta-Harness (External Sub-Agent CLIs)
- Delegates execution to specialized external CLI agents installed on your Mac:
  - **Google Antigravity (`agy`)**
  - **Anthropic Claude Code (`claude`)**
  - **OpenAI Codex (`codex`)**
  - **Nous Hermes (`hermes`)**
  - **OpenCode CLI (`opencode`)**
  - **DeepSeek Harness (`dsh`)**
- Credentials are isolated in separate keyrings.

---

## 🔑 Setting Up Credentials

1. Click the **⚙️ Settings** icon in the sidebar or press `⌘,`.
2. Select your active provider (e.g. *OpenCode Go Cloud*, *Anthropic*, *Google Gemini*).
3. Paste your API key or click **"Load from ~/.local/share/opencode/auth.json"** to auto-import existing keys.
4. Click **"Sync All Keys to Meta-Harnesses"** to populate background CLI profiles.

---

## 🚀 Running Your First Task

1. Type your goal into the prompt composer (e.g. `Implement thread-safe event queue with Swift 6 actors`).
2. Press `Enter` or click **Run**.
3. Watch real-time streaming:
   - **Token Velocity**: 1.2s rolling TPS gauge in the status bar.
   - **Gate Inspector**: Real-time pass/fail checks for syntax and diff risk.
   - **Diff Reviewer**: Side-by-side inspection of proposed modifications before writing.

---

## 📚 Next Steps & Deep Dives

- [Architecture & Deterministic Gates](harness-engineering-guide.md)
- [Meta-Harness CLI Dispatch](meta-harness-dispatch.md)
- [Microtasks Roadmap](../ROADMAP.md)
- [Contributing Guide](../CONTRIBUTING.md)
