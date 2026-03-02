## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

When the AI evaluates a focus area against a rule, it may find multiple violations within the same code region. Currently, the structured output schema is a single flat object with one `violates_rule`, one `score`, one `comment`, and one `line_number`. This means only one violation can be reported per evaluation call — if the AI identifies two or more issues, only the one it picks for the structured output gets turned into a pending comment.

This was observed in practice: the AI's text output clearly identified 2 violations (line 21 and line 48) for the `nullability-m-objc` rule in `MessagesBriefingNavlogCell.m`, but the structured output JSON contained only the line 21 violation. The line 48 violation was silently lost.

**No backward compatibility needed** — old evaluation data will be deleted.

## Phases

## - [x] Phase 1: Change Structured Output Schema to Array

**Skills to read**: `swift-app-architecture:swift-architecture`

Modify the structured output schema in `AnalysisService` to wrap violations in an array.

**File**: `Sources/services/PRRadarCLIService/AnalysisService.swift`

**Changes to `evaluationOutputSchema`**:
```swift
private static let evaluationOutputSchema: [String: Any] = [
    "type": "object",
    "properties": [
        "violations": [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "score": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 10,
                        "description": "Severity score: 1-4 minor, 5-7 moderate, 8-10 severe",
                    ],
                    "comment": [
                        "type": "string",
                        "description": "The GitHub comment to post...",
                    ],
                    "file_path": [
                        "type": "string",
                        "description": "Path to the file containing the code",
                    ],
                    "line_number": [
                        "type": ["integer", "null"],
                        "description": "Specific line number of the violation",
                    ],
                ],
                "required": ["score", "comment"],
            ],
            "description": "List of violations found. Empty array if no violations.",
        ],
    ],
    "required": ["violations"],
]
```

The `violates_rule` boolean is removed — an empty `violations` array means no violation; a non-empty array means violations were found.

**Changes to `evaluationPromptTemplate`**: Update the instructions section to tell the AI to report all violations it finds, not just one. Replace the "Consider" section ending with something like:

```
Report ALL violations you find — each as a separate entry with its own score, comment, file path, and line number.
If the code does not violate the rule, return an empty violations array.
```

## - [x] Phase 2: Change `RuleResult` to Support Multiple Violations

**Skills to read**: `swift-app-architecture:swift-architecture`

Currently `RuleResult` holds a single violation's data. Change it to hold an array of individual findings.

**New model** in `Sources/services/PRRadarModels/Evaluations/`:

Add a `Violation` struct (in `RuleResult.swift` or a new `Violation.swift`):
```swift
public struct Violation: Codable, Sendable {
    public let score: Int
    public let comment: String
    public let filePath: String
    public let lineNumber: Int?
}
```

**Changes to `RuleResult`**:
- Remove: `violatesRule`, `score`, `comment`, `lineNumber`
- Add: `violations: [Violation]`
- Add computed property: `var violatesRule: Bool { !violations.isEmpty }`

```swift
public struct RuleResult: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String        // focus area file path (default for violations missing file_path)
    public let modelUsed: String
    public let durationMs: Int
    public let costUsd: Double?
    public let violations: [Violation]

    public var violatesRule: Bool { !violations.isEmpty }
}
```

## - [x] Phase 3: Update `AnalysisService.analyzeTask()` Parsing

**Skills to read**: `swift-app-architecture:swift-architecture`

**File**: `Sources/services/PRRadarCLIService/AnalysisService.swift`

Change the parsing in `analyzeTask()` (lines 177-209) to extract the `violations` array from the structured output and build a `RuleResult` with multiple violations:

```swift
if let dict = agentResult.outputAsDictionary(),
   let violationsArray = dict["violations"] as? [[String: Any]] {
    let violations = violationsArray.map { v in
        let aiFilePath = v["file_path"] as? String
        let filePath = (aiFilePath?.isEmpty == false) ? aiFilePath! : task.focusArea.filePath
        let lineNumber = v["line_number"] as? Int ?? task.focusArea.startLine
        return Violation(
            score: v["score"] as? Int ?? 1,
            comment: v["comment"] as? String ?? "Evaluation completed",
            filePath: filePath,
            lineNumber: lineNumber
        )
    }
    ruleResult = RuleResult(
        taskId: task.taskId,
        ruleName: task.rule.name,
        filePath: task.focusArea.filePath,
        modelUsed: model,
        durationMs: agentResult.durationMs,
        costUsd: agentResult.costUsd,
        violations: violations
    )
}
```

The return type stays `RuleOutcome` (still one outcome per task) — but the `RuleResult` inside now contains N violations.

## - [x] Phase 4: Update `RuleOutcome` Violation Accessors

**File**: `Sources/services/PRRadarModels/Evaluations/RuleOutcome.swift`

**Changes**:
- `violation` (singular `RuleResult?`) → keep as-is (returns the `RuleResult` if it has violations)
- `isViolation` → keep as-is (uses `violation != nil` which checks `violatesRule`)
- Change `violationComment(task:)` → `violationComments(task:)` returning `[PRComment]`:

```swift
public func violationComments(task: RuleRequest?) -> [PRComment] {
    guard let violation else { return [] }
    return violation.violations.enumerated().map { index, v in
        PRComment.from(violation: v, result: violation, task: task, index: index)
    }
}
```

## - [x] Phase 5: Update `PRComment.from()` Factory

**File**: `Sources/services/PRRadarModels/PRComment.swift`

Add a new factory method that creates a `PRComment` from a `Violation` + `RuleResult` metadata:

```swift
public static func from(
    violation: Violation,
    result: RuleResult,
    task: RuleRequest?,
    index: Int
) -> PRComment {
    PRComment(
        id: "\(result.taskId)_\(index)",
        ruleName: result.ruleName,
        score: violation.score,
        comment: violation.comment,
        filePath: violation.filePath,
        lineNumber: violation.lineNumber,
        documentationLink: task?.rule.documentationLink,
        relevantClaudeSkill: task?.rule.relevantClaudeSkill,
        ruleUrl: task?.rule.ruleUrl,
        costUsd: result.costUsd,
        modelUsed: result.modelUsed
    )
}
```

The `id` uses `taskId_index` to make each comment unique. Remove or deprecate the old `from(result:task:)` method.

## - [x] Phase 6: Update `TaskEvaluation` and Collection Extensions

**File**: `Sources/services/PRRadarModels/Evaluations/TaskEvaluation.swift`

- Change `violationComment: PRComment?` → `violationComments: [PRComment]`:
```swift
public var violationComments: [PRComment] {
    outcome?.violationComments(task: request) ?? []
}
```

- Update the `[TaskEvaluation]` extension:
```swift
public var violationComments: [PRComment] {
    flatMap(\.violationComments)
}
```

## - [x] Phase 7: Update `ViolationService`

**File**: `Sources/services/PRRadarCLIService/ViolationService.swift`

**Changes to `filterByScore`**:
```swift
public static func filterByScore(
    results: [RuleOutcome],
    tasks: [RuleRequest],
    minScore: Int
) -> [PRComment] {
    let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
    var comments: [PRComment] = []
    for result in results {
        comments.append(contentsOf: result.violationComments(task: taskMap[result.taskId])
            .filter { $0.score >= minScore })
    }
    return comments
}
```

**Changes to `loadViolations`**: Same pattern — use `violationComments(task:)` and filter by score.

## - [x] Phase 8: Update `PRReviewResult.appendResult()`

**File**: `Sources/features/PRReviewFeature/models/PRReviewResult.swift`

The `appendResult` method counts violations via `outcomes.filter(\.isViolation).count`. This still works since `isViolation` returns true when there's at least one violation. However, `violationsFound` in the summary should reflect the total number of individual violations, not just tasks-with-violations:

```swift
let violationCount = taskEvaluations.violationComments.count
```

Apply the same change everywhere `violationsFound` is computed (in `AnalyzeUseCase` full run, filtered run, `buildMergedOutput`, `cumulative`).

## - [x] Phase 9: Validation

**Skills to read**: `swift-testing`

- `swift build` — verify no compilation errors
- `swift test` — verify all existing tests pass
- Update existing tests that create `RuleResult` to use the new `violations` array
- Add a test that verifies an AI response with 2 violations in the `violations` array produces 2 `PRComment` objects
- Add a test that an empty `violations` array produces 0 comments and `violatesRule == false`
- Manual test: run `swift run PRRadarMacCLI analyze 1 --config test-repo` and verify multi-violation evaluations produce multiple pending comments
