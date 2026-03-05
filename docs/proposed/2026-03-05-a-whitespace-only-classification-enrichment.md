# Whitespace-Only Classification Enrichment

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

After the [classification model consolidation](2026-03-04-c-classification-model-consolidation.md), whitespace-only paired modifications (leading/trailing whitespace differences) are demoted to `.context` — completely invisible to all consumers. This was the simplest approach, but it raises questions:

1. **Should rules ever see whitespace-only changes?** Some rules might want to flag formatting inconsistencies. Currently they can't, because these lines are hidden.
2. **Should the UI distinguish whitespace-only from truly unchanged?** A `.context` line that was actually a whitespace modification looks identical to genuine context. There's no way to highlight or annotate it.
3. **Should stats count whitespace-only changes?** Currently `DiffStats` ignores them entirely — they don't appear in any count.

This plan explores options for enriching the classification of whitespace-only pairs rather than hiding them.

## Options

### Option A: Keep demoting to `.context` (status quo after consolidation)

Whitespace-only pairs become `.context` — invisible everywhere. Simplest model.

**Pros**: Clean, no noise in rule evaluation
**Cons**: No consumer can ever see or act on whitespace-only changes

### Option B: `.replaced`/`.replacement` with `isWhitespaceOnly` flag on `Counterpart`

All pairs (including whitespace-only) become `.replaced`/`.replacement`. Add a flag to `Counterpart`:

```swift
public struct Counterpart: Codable, Sendable, Equatable {
    public let filePath: String
    public let lineNumber: Int?
    public let isWhitespaceOnly: Bool
}
```

**Pros**: Single model for all pairs, consumers decide what to ignore
**Cons**: `changedLines` (filters `!= .context`) now includes whitespace-only noise — every consumer must check the flag to exclude them. This is the opposite default from what most consumers want.

### Option C: New `.whitespaceModified` ChangeKind case

Add a 6th case to `ChangeKind`:

```swift
case whitespaceModified(counterpart: Counterpart)
```

Consumers filter it out by default (it's not `.new`, not `.context`, and `changedLines` could exclude it). Rules can opt in.

**Pros**: Explicit, no ambiguity
**Cons**: 6th case adds complexity, every switch must handle it

### Option D: Keep `.context` but add `whitespaceModifiedCounterpart` to PRLine

Similar to `verbatimMoveCounterpart` — a separate property that marks `.context` lines that were actually whitespace-only modifications:

```swift
public struct PRLine {
    ...
    public let verbatimMoveCounterpart: Counterpart?
    public let whitespaceModifiedCounterpart: Counterpart?  // non-nil for demoted whitespace-only pairs
    ...
}
```

**Pros**: Default behavior unchanged (`.context` = hidden), but the info is available if consumers want it
**Cons**: Yet another optional counterpart property on PRLine — starts to feel like the model is accumulating special cases

## Decision

To be determined — choose an option and implement.

## Phases

### - [ ] Phase 1: Choose approach and implement

**Skills to read**: `/swift-app-architecture:swift-architecture`

Based on the chosen option, update the classification model. This depends on the [classification model consolidation](2026-03-04-c-classification-model-consolidation.md) being complete first.

### - [ ] Phase 2: Validation

**Skills to read**: `/swift-testing`

1. Run `swift test` — all tests must pass
2. Verify whitespace-only lines are classified per the chosen option
3. Verify rules with `newCodeLinesOnly: true` still exclude whitespace-only changes
4. Verify `changedLines` behavior matches expectations for the chosen option
