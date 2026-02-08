# CLAUDE.md

## Project Overview

PRRadar is a **Python application** for AI-powered pull request reviews. The Python CLI (`prradar/`) is the core of the project — it contains all business logic, pipeline orchestration, and Claude Agent SDK integration. All new features and foundational work should be implemented in the Python app first.

There is also a **Swift Mac app** (`pr-radar-mac/`) that provides a native macOS interface. The Mac app is a **thin client** — it invokes the Python CLI under the hood and presents results visually. It contains minimal business logic of its own; instead it passes data to and makes requests of the Python app. The Mac app has two targets:

- **MacApp (GUI)** — SwiftUI application for browsing diffs, reports, and evaluation outputs
- **MacApp (CLI)** — Command-line target that mirrors the Python CLI, useful for Claude to run and debug the Mac app without needing a GUI

## Architecture Skills

Both apps follow structured architecture patterns defined in Claude Code plugins:

- **Python app**: follows [python-architecture](https://github.com/gestrich/python-architecture) (Service Layer pattern, domain models, dependency injection)
- **Mac app**: follows [swift-app-architecture](https://github.com/gestrich/swift-app-architecture) (4-layer architecture: SDKs → Services → Features → Apps)

## Python App

### Setup

```bash
pip install -r requirements.txt
# Or editable install:
pip install -e .
```

### Running

```bash
# Convenience script (outputs to ~/Desktop/code-reviews/)
./agent.sh analyze 123 --rules-dir ./my-rules
./agent.sh diff 123
./agent.sh rules 123 --rules-dir ./rules
./agent.sh evaluate 123
./agent.sh report 123
./agent.sh status 123

# Direct invocation (outputs to tmp/)
python -m prradar agent diff 123
python -m prradar agent analyze 123 --rules-dir ./code-review-rules
```

### Testing

```bash
python -m pytest tests/ -v
python -m pytest tests/test_diff_parser.py -v     # Specific file
python -m pytest tests/ -k "focus" -v              # By keyword
```

### Structure

```
prradar/
├── __main__.py           # CLI entry point
├── commands/agent/       # Agent mode commands (diff, rules, evaluate, report, analyze, comment, status)
├── domain/               # Data models (diff, rule, report, focus_area, etc.)
├── infrastructure/       # External integrations (git, github, claude, effective_diff)
├── services/             # Business logic (evaluation, focus generation, rule loading, reporting)
└── utils/                # Helpers
```

### Key Technical Details

- Pipeline phases: DIFF → FOCUS_AREAS → RULES → TASKS → EVALUATIONS → REPORT
- Uses Claude Agent SDK `query()` with structured outputs (`output_format` with JSON schema)
- Default model: `claude-sonnet-4-20250514`
- Do NOT use `max_turns=1` — it prevents structured output generation
- Requires `ANTHROPIC_API_KEY` (via env var or `.env` file)
- Uses `gh` CLI for GitHub API calls

## Mac App

The Mac app is a thin Swift wrapper around the Python CLI. It should contain no review logic, rule evaluation, or pipeline orchestration — all of that lives in the Python app. The Mac app's role is to invoke `prradar` CLI commands, parse their JSON output, and present results in a native UI. When adding new capabilities, implement them in the Python app first, then add the corresponding Swift UI/CLI surface.

### Requirements

- macOS 15+
- Swift 6.2+
- Python app installed (the Mac app invokes the `prradar` CLI)

### Building

```bash
cd pr-radar-mac
swift build
swift build -c release
```

### Running

```bash
# GUI app
cd pr-radar-mac
swift run MacApp

# Or run the built executable directly
./pr-radar-mac/.build/debug/MacApp
```

### Structure

```
pr-radar-mac/
├── Package.swift
└── Sources/
    ├── sdks/PRRadarMacSDK/          # CLI command definitions (mirrors Python CLI)
    ├── services/
    │   ├── PRRadarConfigService/    # Config, paths, environment
    │   └── PRRadarCLIService/       # Executes prradar Python CLI commands
    ├── features/PRReviewFeature/    # Use cases (FetchDiffUseCase)
    └── apps/MacApp/                 # SwiftUI app entry point, models, views
```

### Layer Dependency Rules

- **SDKs**: No internal dependencies
- **Services**: Can depend on SDKs only
- **Features**: Can depend on Services and SDKs
- **Apps**: Can depend on all layers

### External Dependencies

- [SwiftCLI](https://github.com/gestrich/SwiftCLI) — CLI command definition and execution framework
