import Foundation
import PRRadarModels

public struct ScriptAnalysisService: Sendable {

    public init() {}

    /// Run a script against a focus area and post-filter violations against changed lines.
    ///
    /// The script receives three arguments: file path, start line, end line.
    /// It outputs tab-delimited violations to stdout (LINE\tCHAR\tSCORE[\tCOMMENT]).
    public func analyzeTask(
        _ task: RuleRequest,
        scriptPath: String,
        repoPath: String,
        classifiedHunks: [ClassifiedHunk]
    ) -> RuleOutcome {
        let startTime = Date().timeIntervalSinceReferenceDate
        let analysisMethod = AnalysisMethod.script(path: scriptPath)

        let resolvedPath = repoPath + "/" + scriptPath

        // Verify script exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resolvedPath) else {
            return .error(RuleError(
                taskId: task.taskId,
                ruleName: task.rule.name,
                filePath: task.focusArea.filePath,
                errorMessage: "Script not found: \(scriptPath)",
                analysisMethod: analysisMethod
            ))
        }

        // Verify script is executable
        guard fileManager.isExecutableFile(atPath: resolvedPath) else {
            return .error(RuleError(
                taskId: task.taskId,
                ruleName: task.rule.name,
                filePath: task.focusArea.filePath,
                errorMessage: "Script is not executable: \(scriptPath)",
                analysisMethod: analysisMethod
            ))
        }

        // Launch script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = [
            task.focusArea.filePath,
            "\(task.focusArea.startLine)",
            "\(task.focusArea.endLine)"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .error(RuleError(
                taskId: task.taskId,
                ruleName: task.rule.name,
                filePath: task.focusArea.filePath,
                errorMessage: "Failed to launch script '\(scriptPath)': \(error.localizedDescription)",
                analysisMethod: analysisMethod
            ))
        }

        // Read pipe data before waitUntilExit to avoid deadlock when pipe buffer fills
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        // Non-zero exit = error
        guard process.terminationStatus == 0 else {
            let message = stderr.isEmpty ? "Script exited with code \(process.terminationStatus)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .error(RuleError(
                taskId: task.taskId,
                ruleName: task.rule.name,
                filePath: task.focusArea.filePath,
                errorMessage: message,
                analysisMethod: analysisMethod
            ))
        }

        // Parse TSV output (strict mode)
        let rawViolations: [Violation]
        do {
            rawViolations = try parseScriptOutput(stdout, filePath: task.focusArea.filePath, rule: task.rule)
        } catch {
            return .error(RuleError(
                taskId: task.taskId,
                ruleName: task.rule.name,
                filePath: task.focusArea.filePath,
                errorMessage: error.localizedDescription,
                analysisMethod: analysisMethod
            ))
        }

        // Post-filter against changed lines
        let relevantLineNumbers = Set(classifiedHunks.flatMap {
            $0.relevantLineNumbers(newCodeLinesOnly: task.rule.newCodeLinesOnly)
        })

        let violations = rawViolations.filter { violation in
            guard let lineNumber = violation.lineNumber else { return false }
            return relevantLineNumbers.contains(lineNumber)
        }

        let durationMs = Int((Date().timeIntervalSinceReferenceDate - startTime) * 1000)

        let result = RuleResult(
            taskId: task.taskId,
            ruleName: task.rule.name,
            filePath: task.focusArea.filePath,
            analysisMethod: analysisMethod,
            durationMs: durationMs,
            violations: violations
        )

        return .success(result)
    }

    // MARK: - TSV Parsing

    /// Parse script stdout as tab-delimited violations.
    ///
    /// Format: `LINE_NUMBER<TAB>CHARACTER_POSITION<TAB>SCORE[<TAB>COMMENT]`
    /// Every non-empty line must conform. If any line fails, the entire result is an error.
    func parseScriptOutput(
        _ output: String,
        filePath: String,
        rule: TaskRule
    ) throws -> [Violation] {
        let lines = output.components(separatedBy: .newlines)
        var violations: [Violation] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let columns = trimmed.components(separatedBy: "\t")
            let lineNum = index + 1

            guard columns.count == 3 || columns.count == 4 else {
                throw ScriptParsingError.invalidColumnCount(line: lineNum, expected: "3 or 4", got: columns.count)
            }

            guard let violationLine = Int(columns[0]), violationLine > 0 else {
                throw ScriptParsingError.invalidLineNumber(line: lineNum, value: columns[0])
            }

            guard Int(columns[1]) != nil, let charPos = Int(columns[1]), charPos >= 0 else {
                throw ScriptParsingError.invalidCharacterPosition(line: lineNum, value: columns[1])
            }

            guard let score = Int(columns[2]), score >= 1, score <= 10 else {
                throw ScriptParsingError.invalidScore(line: lineNum, value: columns[2])
            }

            let comment: String
            if columns.count == 4 {
                comment = columns[3]
            } else {
                comment = rule.violationMessage ?? rule.description
            }

            violations.append(Violation(
                score: score,
                comment: comment,
                filePath: filePath,
                lineNumber: violationLine
            ))
        }

        return violations
    }
}

enum ScriptParsingError: LocalizedError {
    case invalidColumnCount(line: Int, expected: String, got: Int)
    case invalidLineNumber(line: Int, value: String)
    case invalidCharacterPosition(line: Int, value: String)
    case invalidScore(line: Int, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidColumnCount(let line, let expected, let got):
            return "Line \(line): expected \(expected) tab-delimited columns, got \(got)"
        case .invalidLineNumber(let line, let value):
            return "Line \(line): invalid line number '\(value)' (must be a positive integer)"
        case .invalidCharacterPosition(let line, let value):
            return "Line \(line): invalid character position '\(value)' (must be a non-negative integer)"
        case .invalidScore(let line, let value):
            return "Line \(line): invalid score '\(value)' (must be an integer 1-10)"
        }
    }
}
