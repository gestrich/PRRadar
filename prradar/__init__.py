"""PRRadar GitHub Actions CLI tools.

A well-structured CLI package following:
- CLI Architecture: Single entry point dispatcher with explicit parameters
- Domain Modeling: Parse-once pattern with type-safe models
- Services Pattern: Core services with dependency injection
- Python Code Style: Organized methods, section headers, modern annotations

Usage:
    python -m prradar <command> [options]
    prradar <command> [options]

Structure:
    prradar/
    ├── __main__.py          # Entry point dispatcher
    ├── domain/              # Domain models (parse-once pattern)
    │   ├── review.py        # ReviewOutput, Feedback, etc.
    │   └── mention.py       # MentionAction
    ├── services/            # Business logic services
    │   └── github_comment.py
    ├── infrastructure/      # External system interactions
    │   ├── execution_parser.py
    │   ├── github_output.py
    │   └── gh_runner.py
    └── commands/            # Thin command orchestrators
        ├── post_review.py
        └── handle_mention.py
"""
