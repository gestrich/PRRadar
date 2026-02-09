import Foundation
import PRRadarConfigService
import PRRadarModels

public struct EvaluationService: Sendable {
    private let bridgeClient: ClaudeBridgeClient

    private static let defaultModel = "claude-sonnet-4-20250514"

    private static let evaluationPromptTemplate = """
    You are a code reviewer evaluating whether code violates a specific rule.

    ## Rule: {rule_name}

    {rule_description}

    ### Rule Details

    {rule_content}

    ## Focus Area: {focus_area_description}

    File: {file_path}
    Lines: {start_line}-{end_line}

    **Important:** Only evaluate the code within the focus area boundaries shown below.
    Ignore any surrounding code in the diff hunk.

    **Code to review:**

    ```diff
    {diff_content}
    ```

    ## Codebase Context

    The PR branch is checked out locally at: {repo_path}
    You have full access to the codebase for additional context.

    - For rules that evaluate isolated patterns (naming conventions, signature
      format), the focus area content above is typically sufficient.
    - For rules that evaluate broader concerns (architecture, client usage,
      integration patterns), explore the codebase as needed. For example,
      search for callers of a method, check how similar patterns are used
      elsewhere, or read surrounding code for context.

    Use your judgment: explore when it would improve the quality of your
    review, but don't explore unnecessarily for simple pattern checks.

    ## Instructions

    Analyze the code changes shown in the diff and determine if they violate the rule.

    Focus ONLY on the added/changed lines (lines starting with `+`). Context lines \
    (no prefix or starting with `-`) are provided for understanding but should not be \
    evaluated for violations.

    Consider:
    1. Does the new or modified code violate the rule?
    2. How severe is the violation (1-10 scale)?

    For the comment field: If the rule includes a "GitHub Comment" section, use that \
    exact text as your comment unless there is critical context-specific information \
    that must be added. Keep comments concise.

    Be precise about the file path and line number where any violation occurs.
    """

    // Schema stored as nonisolated(unsafe) to avoid [String: Any] Sendable issues
    nonisolated(unsafe) private static let evaluationOutputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "violates_rule": [
                "type": "boolean",
                "description": "Whether the code violates the rule",
            ],
            "score": [
                "type": "integer",
                "minimum": 1,
                "maximum": 10,
                "description": "Severity score: 1-4 minor, 5-7 moderate, 8-10 severe",
            ],
            "comment": [
                "type": "string",
                "description": "The GitHub comment to post. If the rule includes a 'GitHub Comment' section, use that exact format unless there is critical context-specific information to add. Keep it concise.",
            ],
            "file_path": [
                "type": "string",
                "description": "Path to the file containing the code",
            ],
            "line_number": [
                "type": ["integer", "null"],
                "description": "Specific line number of the violation, if applicable",
            ],
        ] as [String: Any],
        "required": ["violates_rule", "score", "comment"],
    ]

    public init(bridgeClient: ClaudeBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    /// Evaluate a single task using Claude via the bridge.
    public func evaluateTask(_ task: EvaluationTaskOutput, repoPath: String) async throws -> RuleEvaluationResult {
        let model = task.rule.model ?? Self.defaultModel
        let focusedContent = task.focusArea.getFocusedContent()

        let prompt = Self.evaluationPromptTemplate
            .replacingOccurrences(of: "{rule_name}", with: task.rule.name)
            .replacingOccurrences(of: "{rule_description}", with: task.rule.description)
            .replacingOccurrences(of: "{rule_content}", with: task.rule.content)
            .replacingOccurrences(of: "{focus_area_description}", with: task.focusArea.description)
            .replacingOccurrences(of: "{file_path}", with: task.focusArea.filePath)
            .replacingOccurrences(of: "{start_line}", with: String(task.focusArea.startLine))
            .replacingOccurrences(of: "{end_line}", with: String(task.focusArea.endLine))
            .replacingOccurrences(of: "{diff_content}", with: focusedContent)
            .replacingOccurrences(of: "{repo_path}", with: repoPath)

        let request = BridgeRequest(
            prompt: prompt,
            model: model,
            tools: ["Read", "Grep", "Glob"],
            cwd: repoPath,
            outputSchema: Self.evaluationOutputSchema
        )

        var bridgeResult: BridgeResult?
        for try await event in bridgeClient.stream(request) {
            switch event {
            case .text(let content):
                for textLine in content.components(separatedBy: "\n") {
                    print("      \(textLine)", terminator: "\n")
                }
            case .toolUse:
                break
            case .result(let result):
                bridgeResult = result
            }
        }

        guard let bridgeResult else {
            throw ClaudeBridgeError.noResult
        }

        let evaluation: RuleEvaluation
        if let dict = bridgeResult.outputAsDictionary() {
            let filePath = dict["file_path"] as? String ?? task.focusArea.filePath
            let lineNumber = dict["line_number"] as? Int ?? task.focusArea.startLine
            evaluation = RuleEvaluation(
                violatesRule: dict["violates_rule"] as? Bool ?? false,
                score: dict["score"] as? Int ?? 1,
                comment: dict["comment"] as? String ?? "Evaluation completed",
                filePath: filePath,
                lineNumber: lineNumber
            )
        } else {
            evaluation = RuleEvaluation(
                violatesRule: false,
                score: 1,
                comment: "Evaluation failed - no structured output returned",
                filePath: task.focusArea.filePath,
                lineNumber: task.focusArea.startLine
            )
        }

        return RuleEvaluationResult(
            taskId: task.taskId,
            ruleName: task.rule.name,
            ruleFilePath: "",
            filePath: task.focusArea.filePath,
            evaluation: evaluation,
            modelUsed: model,
            durationMs: bridgeResult.durationMs,
            costUsd: bridgeResult.costUsd
        )
    }

    /// Run evaluations for all tasks, writing results to the evaluations directory.
    public func runBatchEvaluation(
        tasks: [EvaluationTaskOutput],
        outputDir: String,
        repoPath: String,
        onStart: ((Int, Int, EvaluationTaskOutput) -> Void)? = nil,
        onResult: ((Int, Int, RuleEvaluationResult) -> Void)? = nil
    ) async throws -> [RuleEvaluationResult] {
        let evalsDir = "\(outputDir)/\(PRRadarPhase.evaluations.rawValue)"
        try FileManager.default.createDirectory(atPath: evalsDir, withIntermediateDirectories: true)

        var results: [RuleEvaluationResult] = []
        let total = tasks.count

        for (i, task) in tasks.enumerated() {
            let index = i + 1
            onStart?(index, total, task)

            let result = try await evaluateTask(task, repoPath: repoPath)
            results.append(result)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            let resultPath = "\(evalsDir)/\(DataPathsService.dataFilePrefix)\(task.taskId).json"
            try data.write(to: URL(fileURLWithPath: resultPath))

            onResult?(index, total, result)
        }

        return results
    }
}
