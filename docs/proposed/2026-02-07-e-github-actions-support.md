# CI/CD Integration

## Background

This document covers integrating PRRadar into CI/CD pipelines so that PR reviews run automatically on new pull requests. This repo should include example CI/CD configurations that teams can adapt.

**Reference:** The tool architecture and vision are documented in the main README.md. Related planning documents:
- **Diff Source Abstraction:** [diff-source-abstraction.md](diff-source-abstraction.md)
- **Focus Areas:** [focus-areas.md](focus-areas.md)

## Features

- GitHub Actions workflow that runs on new PRs
- Automatic rule checking without manual intervention
- Configurable: can run all rules or subset
- Posts results as PR comments or check results
- Supports different modes:
  - Advisory (comments only, doesn't block)
  - Blocking (requires fixes before merge)
  - Silent (logs only, for observation)
- Cost controls (limit max rules/chunks per PR)

## Example CI/CD Configurations

This repo should include ready-to-use example workflows under an `examples/` directory (or similar) that demonstrate:

- GitHub Actions workflow for running PRRadar on PR open/update events
- Configuration for different modes (advisory, blocking, silent)
- Secrets management for API keys
- Cost control configuration

## Expected Outcomes

- Automated reviews on all new PRs
- Consistent feedback across all code changes
- Scales review process beyond individual reviewers
- Frees senior engineers to focus on architectural review

---

## Open Questions

None at this time. Focus area-related questions have been moved to [focus-areas.md](focus-areas.md).
