## Description
Provide a brief summary of the changes introduced by this pull request.

## Subsystems Affected
- [ ] `AdventurersCore` (Gates, FSM State Engine, Darwin Sandbox, FailChain, Telemetry)
- [ ] `GUI` (SwiftUI 3-panel workspace, Terminal, Diff Viewer, Settings)
- [ ] `LLMProviders` (OpenCode, Anthropic, Gemini, OpenAI, GLM)
- [ ] `Tools` (Bash, File, Glob, Grep)
- [ ] `MetaHarness` (CLI Subprocess Dispatch, Registry, Keyrings)
- [ ] `CI/CD & Packaging` (GitHub Actions, Homebrew, DMG scripts)

## Microtest Verification
- [ ] All unit tests pass via `swift test` (0 errors, 0 warnings)
- [ ] Added new test cases in `Tests/AdventurersCoreTests/` covering edge conditions
- [ ] Verified on macOS Apple Silicon (arm64)
