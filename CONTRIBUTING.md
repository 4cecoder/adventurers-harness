# Contributing to Adventurers Harness

Thank you for your interest in contributing to **Adventurers Harness**! We welcome bug fixes, documentation improvements, new deterministic gates, LLM provider integrations, and Meta-Harness targets.

---

## 🛠️ Development Environment

- **OS**: macOS Sequoia (15.0+) on Apple Silicon (`arm64`)
- **Language**: Swift 6.0+ with Strict Concurrency Checking
- **IDE**: Xcode 16.0+ or Visual Studio Code / Cursor with Swift Extension
- **Package Manager**: Swift Package Manager (`SPM`)

---

## 🚀 Quickstart for Developers

```bash
# 1. Clone the repository
git clone https://github.com/4cecoder/adventurers-harness.git
cd adventurers-harness

# 2. Run the full unit and microtest suite
swift test

# 3. Build and launch the native GUI app
swift run Adventurers
```

---

## 🧩 Implementing a Custom Gate

All gates conform to the `Gate` protocol defined in `Sources/AdventurersCore/Protocols.swift`:

```swift
public protocol Gate: Sendable {
    var name: String { get }
    var required: Bool { get }
    func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult
}
```

### Steps to Add a Gate:
1. Create or open your gate struct in `Sources/AdventurersCore/Gates.swift`.
2. Implement the `evaluate` function returning `GateResult(passed: Bool, gateName: String, output: String, error: String?)`.
3. Add a corresponding test in `Tests/AdventurersCoreTests/AdventurersCoreTests.swift`.
4. Register the gate in `SettingsView.swift` if user-configurable.

---

## 🔀 Adding a Meta-Harness Target

To add a new sub-agent CLI target:
1. Open `Sources/AdventurersCore/MetaHarness.swift`.
2. Add a new case to `enum MetaHarnessType`:
   ```swift
   case myAgent = "My Agent CLI"
   ```
3. Configure `defaultBinaryName`, `defaultEnvKeyName`, `icon`, and `description`.
4. Ensure `executeHarness` constructs the appropriate non-interactive flags.
5. Add test coverage in `AdventurersCoreTests.swift`.

---

## 📦 Building & Testing Release Packages

Before opening a pull request, verify that local release packaging builds cleanly:

```bash
# Verify test suite passes with 0 warnings
swift test

# Build and package app bundle, DMG installer, and tarballs
./scripts/package_app.sh 1.0.0
```

---

## 📋 Pull Request Guidelines

1. **Keep it atomic**: One feature, gate, or bugfix per PR.
2. **Include microtests**: Every new gate or model parser must have accompanying unit tests.
3. **Strict Concurrency**: Zero concurrency warnings under Swift 6.
4. **Clean Commits**: Write clear, imperative commit messages (e.g. `feat(gates): add OWASP SQL injection security gate`).

---

## 📜 License

By contributing to Adventurers Harness, you agree that your contributions will be licensed under the project's **MIT License**.
