# CLAUDE.md

## Project Overview

PRRadar is a **Swift application** for AI-powered pull request reviews. It fetches PR diffs, applies rule-based filtering, evaluates code with the Claude Agent SDK (via a minimal Python bridge), and generates structured reports.

The Swift package (`pr-radar-mac/`) contains all business logic, pipeline orchestration, and native integrations. It has two executable targets:

- **MacApp** — SwiftUI application for browsing diffs, reports, and evaluation outputs
- **PRRadarMacCLI** — Command-line target for running the pipeline from the terminal

## Architecture

The app follows the [swift-app-architecture](https://github.com/gestrich/swift-app-architecture) conventions (4-layer architecture: SDKs → Services → Features → Apps).

### Layer Dependency Rules

- **SDKs**: No internal dependencies
- **Services**: Can depend on SDKs only
- **Features**: Can depend on Services and SDKs
- **Apps**: Can depend on all layers

### Structure

```
pr-radar-mac/
├── Package.swift
├── bridge/                              # Minimal Python bridge for Claude Agent SDK
│   ├── claude_bridge.py
│   └── requirements.txt
├── Sources/
│   ├── sdks/PRRadarMacSDK/             # CLI command definitions (git, gh, claude bridge)
│   ├── services/
│   │   ├── PRRadarModels/              # Domain models (diff, rule, focus area, report, etc.)
│   │   ├── PRRadarConfigService/       # Config, paths, environment
│   │   └── PRRadarCLIService/          # Business logic services (evaluation, rules, reports, etc.)
│   ├── features/PRReviewFeature/       # Use cases (FetchDiffUseCase, EvaluateUseCase, etc.)
│   └── apps/
│       ├── MacApp/                     # SwiftUI app entry point, models, views
│       └── MacCLI/                     # CLI commands (diff, rules, evaluate, report, analyze, etc.)
└── Tests/
    └── PRRadarModelsTests/             # Unit tests
```

### External Dependencies

- [SwiftCLI](https://github.com/gestrich/SwiftCLI) — CLI command definition and execution framework
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing (PRRadarMacCLI)

### Python Bridge

The only Python code is a minimal bridge script (`pr-radar-mac/bridge/claude_bridge.py`) that wraps the Claude Agent SDK `query()` call. This is necessary because the Claude Agent SDK is Python-only. The bridge:
- Reads a JSON request from stdin
- Calls `claude_agent_sdk.query()`
- Streams JSON-lines to stdout

Setup: `pip install -r pr-radar-mac/bridge/requirements.txt`

## Building

```bash
cd pr-radar-mac
swift build
swift build -c release
```

## Running

```bash
cd pr-radar-mac

# CLI commands
swift run PRRadarMacCLI diff 1 --config test-repo
swift run PRRadarMacCLI rules 1 --config test-repo
swift run PRRadarMacCLI evaluate 1 --config test-repo
swift run PRRadarMacCLI report 1 --config test-repo
swift run PRRadarMacCLI analyze 1 --config test-repo
swift run PRRadarMacCLI comment 1 --config test-repo
swift run PRRadarMacCLI status 1 --config test-repo

# GUI app
swift run MacApp
```

The `--config` flag selects a saved configuration (repo path, output directory, rules directory). Use `swift run PRRadarMacCLI config list` to see available configurations.

## Testing

```bash
cd pr-radar-mac
swift test
```

## Key Technical Details

- Pipeline phases: DIFF → FOCUS_AREAS → RULES → TASKS → EVALUATIONS → REPORT
- Claude Agent SDK calls go through the Python bridge (`claude_bridge.py`)
- Focus generation uses Haiku; rule evaluation uses Sonnet
- Uses `gh` CLI for GitHub API calls, `git` CLI for git operations (both via SwiftCLI)
- Requires `ANTHROPIC_API_KEY` (via env var or `.env` file)
- macOS 15+, Swift 6.2+

## Skills

Proactively use these skills when writing or modifying Swift code in this project:

- `/swift-app-architecture:swift-architecture` — 4-layer architecture rules (layer responsibilities, dependency rules, placement guidance, feature creation, configuration, code style). Use when adding code, creating features, or reviewing architectural compliance.
- `/swift-app-architecture:swift-swiftui` — SwiftUI Model-View patterns (enum-based state, model composition, dependency injection, view identity, observable model conventions). Use when building SwiftUI views, creating observable models, or implementing state management.
- `/swift-testing` — Test style guide. Use when writing or modifying tests.
- `/xcode-sim-automation:interactive-xcuitest` — Interactively control the PRRadar MacApp through XCUITest. Use for dynamic UI exploration, navigation flows, taking screenshots, or testing UI interactions.
- `/xcode-sim-automation:creating-automated-screenshots` — Create automated screenshot tests for PRRadar MacApp views. Use when capturing UI images, testing view rendering, or generating visual documentation.

## Plugin Mode

PRRadar also works as a Claude Code plugin. The plugin is in `plugin/` and provides the `/pr-review` skill.
