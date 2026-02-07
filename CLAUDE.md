# CLAUDE.md

## Project Overview

PRRadar is an AI-powered pull request review system with **two applications**:

1. **Python App** (`prradar/`) — CLI tool that runs the review pipeline using the Claude Agent SDK. Fetches PR diffs, applies rule-based filtering, evaluates code with Claude, and generates reports.

2. **Mac App** (`pr-radar-mac/`) — Native macOS SwiftUI application with both a GUI and CLI target. The Mac UI is useful for visualizing the results of the Python app (viewing diffs, reports, and evaluation outputs). The Mac CLI is important because it allows Claude to run and debug the Mac app via the command line, which is difficult to do through a GUI.

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
