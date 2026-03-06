import Foundation
import Testing
@testable import PRRadarCLIService
@testable import PRRadarModels

// MARK: - Helpers

private func makePRLine(
    content: String,
    contentChange: ContentChange,
    pairing: Pairing? = nil,
    lineType: DiffLineType = .added,
    filePath: String = "Calculator.swift",
    newLineNumber: Int? = nil,
    oldLineNumber: Int? = nil
) -> PRLine {
    PRLine(
        content: content,
        rawLine: lineType == .added ? "+\(content)" : lineType == .removed ? "-\(content)" : " \(content)",
        diffType: lineType,
        contentChange: contentChange,
        pairing: pairing,
        oldLineNumber: oldLineNumber ?? (lineType == .removed ? 1 : nil),
        newLineNumber: newLineNumber ?? (lineType == .added ? 1 : nil),
        filePath: filePath
    )
}

private func makePRHunk(
    filePath: String = "Calculator.swift",
    lines: [PRLine]
) -> PRHunk {
    PRHunk(filePath: filePath, oldStart: 1, newStart: 1, lines: lines)
}

private func makeTaskRule(
    name: String = "test-rule",
    description: String = "Test rule description",
    violationRegex: String? = nil,
    violationMessage: String? = nil,
    violationScript: String? = nil,
    newCodeLinesOnly: Bool = false,
    rulesDir: String = ""
) -> TaskRule {
    TaskRule(
        name: name,
        description: description,
        category: "safety",
        content: "Rule body",
        newCodeLinesOnly: newCodeLinesOnly,
        violationRegex: violationRegex,
        violationMessage: violationMessage,
        violationScript: violationScript,
        rulesDir: rulesDir
    )
}

private func makeRuleRequest(
    rule: TaskRule,
    filePath: String = "Calculator.swift",
    startLine: Int = 1,
    endLine: Int = 100
) -> RuleRequest {
    let focusArea = FocusArea(
        focusId: filePath,
        filePath: filePath,
        startLine: startLine,
        endLine: endLine,
        description: "test focus",
        hunkIndex: 0,
        hunkContent: ""
    )
    return RuleRequest(taskId: "\(rule.name)_\(filePath)", rule: rule, focusArea: focusArea, gitBlobHash: "abc123")
}

/// Create a temporary executable script that outputs the given content to stdout.
private func createTempScript(
    content: String,
    exitCode: Int = 0,
    stderr: String? = nil
) throws -> (scriptPath: String, repoPath: String, cleanup: () -> Void) {
    let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
    let scriptsDir = repoDir.appendingPathComponent("scripts")
    try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

    var scriptBody = "#!/bin/bash\n"
    if let stderr {
        scriptBody += "echo '\(stderr)' >&2\n"
    }
    if !content.isEmpty {
        scriptBody += "printf '%s' '\(content)'\n"
    }
    if exitCode != 0 {
        scriptBody += "exit \(exitCode)\n"
    }

    let scriptURL = scriptsDir.appendingPathComponent("check.sh")
    try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)

    // Make executable
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let cleanup: () -> Void = {
        try? FileManager.default.removeItem(at: repoDir)
    }

    return ("scripts/check.sh", repoDir.path, cleanup)
}

// MARK: - RuleAnalysisType Tests

@Suite("RuleAnalysisType")
struct RuleAnalysisTypeTests {

    @Test("Codable round-trip for .ai")
    func codableAi() throws {
        // Arrange
        let value = RuleAnalysisType.ai

        // Act
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RuleAnalysisType.self, from: data)

        // Assert
        #expect(decoded == .ai)
    }

    @Test("Codable round-trip for .regex")
    func codableRegex() throws {
        // Arrange
        let value = RuleAnalysisType.regex

        // Act
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RuleAnalysisType.self, from: data)

        // Assert
        #expect(decoded == .regex)
    }

    @Test("Codable round-trip for .script")
    func codableScript() throws {
        // Arrange
        let value = RuleAnalysisType.script

        // Act
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RuleAnalysisType.self, from: data)

        // Assert
        #expect(decoded == .script)
    }

    @Test("ReviewRule.analysisType returns .script when violationScript is set")
    func reviewRuleAnalysisTypeScript() {
        // Arrange
        let rule = ReviewRule(
            name: "test", filePath: "/test.md", description: "d", category: "c",
            content: "body", violationScript: "scripts/check.sh"
        )

        // Assert
        #expect(rule.analysisType == .script)
    }

    @Test("ReviewRule.analysisType returns .regex when violationRegex is set")
    func reviewRuleAnalysisTypeRegex() {
        // Arrange
        let rule = ReviewRule(
            name: "test", filePath: "/test.md", description: "d", category: "c",
            content: "body", violationRegex: "pattern"
        )

        // Assert
        #expect(rule.analysisType == .regex)
    }

    @Test("ReviewRule.analysisType returns .ai when neither is set")
    func reviewRuleAnalysisTypeAi() {
        // Arrange
        let rule = ReviewRule(
            name: "test", filePath: "/test.md", description: "d", category: "c",
            content: "body"
        )

        // Assert
        #expect(rule.analysisType == .ai)
    }

    @Test("TaskRule.analysisType returns .script when violationScript is set")
    func taskRuleAnalysisTypeScript() {
        // Arrange
        let rule = makeTaskRule(violationScript: "scripts/check.sh")

        // Assert
        #expect(rule.analysisType == .script)
    }

    @Test("script takes precedence over regex in analysisType")
    func scriptPrecedenceOverRegex() {
        // Arrange — both set (Phase 2 validation prevents this in YAML, but test the precedence)
        let rule = TaskRule(
            name: "test", description: "d", category: "c", content: "body",
            violationRegex: "pattern", violationScript: "scripts/check.sh",
            rulesDir: "/tmp/rules"
        )

        // Assert
        #expect(rule.analysisType == .script)
    }
}

// MARK: - PRHunk.relevantLines/relevantLineNumbers Tests

@Suite("PRHunk relevant lines helpers")
struct PRHunkRelevantLinesTests {

    @Test("relevantLines with newCodeLinesOnly: true returns only added lines")
    func relevantLinesNewCodeOnly() {
        // Arrange
        let hunk = makePRHunk(lines: [
            makePRLine(content: "added", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "changed", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "removed", contentChange: .deleted, lineType: .removed, oldLineNumber: 5),
            makePRLine(content: "unchanged", contentChange: .unchanged, lineType: .context, newLineNumber: 12),
        ])

        // Act
        let lines = hunk.relevantLines(newCodeLinesOnly: true)

        // Assert
        #expect(lines.count == 1)
        #expect(lines[0].content == "added")
    }

    @Test("relevantLines with newCodeLinesOnly: false returns all changed lines")
    func relevantLinesAllChanged() {
        // Arrange
        let hunk = makePRHunk(lines: [
            makePRLine(content: "added", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "changed", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "removed", contentChange: .deleted, lineType: .removed, oldLineNumber: 5),
            makePRLine(content: "unchanged", contentChange: .unchanged, lineType: .context, newLineNumber: 12),
        ])

        // Act
        let lines = hunk.relevantLines(newCodeLinesOnly: false)

        // Assert
        #expect(lines.count == 3)
        #expect(lines.map(\.content) == ["added", "changed", "removed"])
    }

    @Test("relevantLineNumbers with newCodeLinesOnly: true returns line numbers of added lines")
    func relevantLineNumbersNewCodeOnly() {
        // Arrange
        let hunk = makePRHunk(lines: [
            makePRLine(content: "added", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "changed", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "context", contentChange: .unchanged, lineType: .context, newLineNumber: 12),
        ])

        // Act
        let lineNums = hunk.relevantLineNumbers(newCodeLinesOnly: true)

        // Assert
        #expect(lineNums == Set([10]))
    }

    @Test("relevantLineNumbers with newCodeLinesOnly: false returns line numbers of all changed lines")
    func relevantLineNumbersAllChanged() {
        // Arrange
        let hunk = makePRHunk(lines: [
            makePRLine(content: "added", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "changed", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "removed", contentChange: .deleted, lineType: .removed, oldLineNumber: 5),
            makePRLine(content: "context", contentChange: .unchanged, lineType: .context, newLineNumber: 12),
        ])

        // Act
        let lineNums = hunk.relevantLineNumbers(newCodeLinesOnly: false)

        // Assert
        #expect(lineNums == Set([10, 11, 5]))
    }

    @Test("relevantLineNumbers falls back to oldLineNumber when newLineNumber is nil")
    func fallsBackToOldLineNumber() {
        // Arrange
        let hunk = makePRHunk(lines: [
            makePRLine(content: "removed", contentChange: .deleted, lineType: .removed, newLineNumber: nil, oldLineNumber: 42),
        ])

        // Act
        let lineNums = hunk.relevantLineNumbers(newCodeLinesOnly: false)

        // Assert
        #expect(lineNums == Set([42]))
    }
}

// MARK: - AnalysisMode Script Tests

@Suite("AnalysisMode script filtering")
struct AnalysisModeScriptTests {

    private func makeScriptTask() -> RuleRequest {
        makeRuleRequest(rule: makeTaskRule(violationScript: "scripts/check.sh"))
    }

    private func makeRegexTask() -> RuleRequest {
        makeRuleRequest(rule: makeTaskRule(violationRegex: "TODO"))
    }

    private func makeAiTask() -> RuleRequest {
        makeRuleRequest(rule: makeTaskRule())
    }

    @Test("scriptOnly matches task with violationScript")
    func scriptOnlyMatchesScriptTask() {
        // Arrange
        let task = makeScriptTask()

        // Act
        let result = AnalysisMode.scriptOnly.matches(task)

        // Assert
        #expect(result)
    }

    @Test("scriptOnly rejects regex task")
    func scriptOnlyRejectsRegexTask() {
        // Arrange
        let task = makeRegexTask()

        // Act
        let result = AnalysisMode.scriptOnly.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("scriptOnly rejects AI task")
    func scriptOnlyRejectsAiTask() {
        // Arrange
        let task = makeAiTask()

        // Act
        let result = AnalysisMode.scriptOnly.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("all matches script task")
    func allMatchesScriptTask() {
        // Arrange
        let task = makeScriptTask()

        // Act
        let result = AnalysisMode.all.matches(task)

        // Assert
        #expect(result)
    }

    @Test("regexOnly rejects script task")
    func regexOnlyRejectsScriptTask() {
        // Arrange
        let task = makeScriptTask()

        // Act
        let result = AnalysisMode.regexOnly.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("aiOnly rejects script task")
    func aiOnlyRejectsScriptTask() {
        // Arrange
        let task = makeScriptTask()

        // Act
        let result = AnalysisMode.aiOnly.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("scriptOnly filters mixed list to only script tasks")
    func scriptOnlyFiltersMixedList() {
        // Arrange
        let tasks = [makeScriptTask(), makeRegexTask(), makeAiTask()]

        // Act
        let filtered = tasks.filter { AnalysisMode.scriptOnly.matches($0) }

        // Assert
        #expect(filtered.count == 1)
        #expect(filtered[0].rule.analysisType == .script)
    }
}

// MARK: - YAML Parsing Tests

@Suite("ReviewRule violation_script YAML parsing")
struct ReviewRuleScriptParsingTests {

    @Test("fromFile parses violation_script from YAML frontmatter")
    func fromFileViolationScript() throws {
        // Arrange
        let content = """
        ---
        description: Import order check
        category: style
        violation_script: scripts/check-import-order.sh
        ---
        Body
        """
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("import-order.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        let rule = try ReviewRule.fromFile(fileURL)

        // Assert
        #expect(rule.violationScript == "scripts/check-import-order.sh")
        #expect(rule.analysisType == .script)
        #expect(rule.violationRegex == nil)

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("fromFile throws when both violation_script and violation_regex are set")
    func fromFileMutuallyExclusive() throws {
        // Arrange
        let content = """
        ---
        description: Bad rule
        category: style
        violation_script: scripts/check.sh
        violation_regex: "pattern"
        ---
        Body
        """
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("bad-rule.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Act & Assert
        #expect(throws: RuleParsingError.self) {
            try ReviewRule.fromFile(fileURL)
        }

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("ReviewRule violation_script round-trips through JSON")
    func roundTrip() throws {
        // Arrange
        let rule = ReviewRule(
            name: "test", filePath: "/test.md", description: "d", category: "c",
            content: "body", violationScript: "scripts/check.sh"
        )

        // Act
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ReviewRule.self, from: data)

        // Assert
        #expect(decoded.violationScript == "scripts/check.sh")
        #expect(decoded.analysisType == .script)
    }

    @Test("TaskRule violation_script round-trips through JSON")
    func taskRuleRoundTrip() throws {
        // Arrange
        let rule = TaskRule(
            name: "test", description: "d", category: "c", content: "body",
            violationScript: "scripts/check.sh",
            rulesDir: "/tmp/rules"
        )

        // Act
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(TaskRule.self, from: data)

        // Assert
        #expect(decoded.violationScript == "scripts/check.sh")
        #expect(decoded.analysisType == .script)
    }

    @Test("ReviewRule.analysisType propagates to TaskRule via RuleRequest.from()")
    func analysisTypePropagates() {
        // Arrange
        let reviewRule = ReviewRule(
            name: "test", filePath: "/test.md", description: "d", category: "c",
            content: "body", violationScript: "scripts/check.sh"
        )
        let focusArea = FocusArea(
            focusId: "file.swift", filePath: "file.swift",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let request = RuleRequest.from(rule: reviewRule, focusArea: focusArea, gitBlobHash: "abc", rulesDir: "/tmp/rules")

        // Assert
        #expect(request.rule.analysisType == .script)
        #expect(request.rule.violationScript == "scripts/check.sh")
    }
}

// MARK: - ScriptAnalysisService TSV Parsing Tests

@Suite("ScriptAnalysisService TSV parsing")
struct ScriptParsingTests {

    let service = ScriptAnalysisService()

    @Test("parses 3-column output using rule description as comment")
    func threeColumns() throws {
        // Arrange
        let output = "15\t8\t5\n23\t1\t3\n"
        let rule = makeTaskRule(description: "Rule description")

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations.count == 2)
        #expect(violations[0].lineNumber == 15)
        #expect(violations[0].score == 5)
        #expect(violations[0].comment == "Rule description")
        #expect(violations[1].lineNumber == 23)
        #expect(violations[1].score == 3)
    }

    @Test("parses 4-column output using script-provided comment")
    func fourColumns() throws {
        // Arrange
        let output = "15\t8\t5\tImport is out of order\n"
        let rule = makeTaskRule()

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations.count == 1)
        #expect(violations[0].comment == "Import is out of order")
    }

    @Test("parses mixed 3 and 4 column lines")
    func mixedColumns() throws {
        // Arrange
        let output = "10\t0\t5\tCustom comment\n20\t1\t3\n"
        let rule = makeTaskRule(description: "Fallback description")

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations.count == 2)
        #expect(violations[0].comment == "Custom comment")
        #expect(violations[1].comment == "Fallback description")
    }

    @Test("uses violationMessage over description when available")
    func violationMessageFallback() throws {
        // Arrange
        let output = "10\t0\t5\n"
        let rule = makeTaskRule(description: "Description", violationMessage: "Custom message")

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations[0].comment == "Custom message")
    }

    @Test("empty stdout returns no violations")
    func emptyOutput() throws {
        // Arrange
        let output = ""
        let rule = makeTaskRule()

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations.isEmpty)
    }

    @Test("blank lines are skipped")
    func blankLines() throws {
        // Arrange
        let output = "\n10\t0\t5\n\n\n"
        let rule = makeTaskRule()

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations.count == 1)
    }

    // MARK: - Strict Parsing Errors

    @Test("throws on wrong column count (1 column)")
    func wrongColumnCount1() {
        // Arrange
        let output = "15\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on wrong column count (2 columns)")
    func wrongColumnCount2() {
        // Arrange
        let output = "15\t8\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on wrong column count (5 columns)")
    func wrongColumnCount5() {
        // Arrange
        let output = "15\t8\t5\tcomment\textra\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on non-integer line number")
    func nonIntegerLineNumber() {
        // Arrange
        let output = "abc\t8\t5\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on zero line number")
    func zeroLineNumber() {
        // Arrange
        let output = "0\t8\t5\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on negative line number")
    func negativeLineNumber() {
        // Arrange
        let output = "-1\t8\t5\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on non-integer character position")
    func nonIntegerCharPosition() {
        // Arrange
        let output = "15\tabc\t5\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on negative character position")
    func negativeCharPosition() {
        // Arrange
        let output = "15\t-1\t5\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on non-integer score")
    func nonIntegerScore() {
        // Arrange
        let output = "15\t8\tabc\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on score of 0 (below range)")
    func scoreZero() {
        // Arrange
        let output = "15\t8\t0\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on score of 11 (above range)")
    func scoreEleven() {
        // Arrange
        let output = "15\t8\t11\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("throws on negative score")
    func negativeScore() {
        // Arrange
        let output = "15\t8\t-1\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("fails entire result when one line is malformed among valid lines")
    func failsEntireResultOnMalformedLine() {
        // Arrange
        let output = "15\t8\t5\tGood line\nabc\t8\t5\n"
        let rule = makeTaskRule()

        // Act & Assert
        #expect(throws: ScriptParsingError.self) {
            try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)
        }
    }

    @Test("accepts score at boundaries (1 and 10)")
    func scoreBoundaries() throws {
        // Arrange
        let output = "10\t0\t1\n20\t0\t10\n"
        let rule = makeTaskRule()

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations.count == 2)
        #expect(violations[0].score == 1)
        #expect(violations[1].score == 10)
    }

    @Test("accepts zero character position")
    func zeroCharPosition() throws {
        // Arrange
        let output = "10\t0\t5\n"
        let rule = makeTaskRule()

        // Act
        let violations = try service.parseScriptOutput(output, filePath: "file.swift", rule: rule)

        // Assert
        #expect(violations.count == 1)
    }
}

// MARK: - ScriptAnalysisService Integration Tests

@Suite("ScriptAnalysisService analyzeTask")
struct ScriptAnalysisServiceTests {

    @Test("happy path: script with violations returns success")
    func happyPathWithViolations() throws {
        // Arrange
        let scriptOutput = "15\t8\t5\tImport out of order\n23\t1\t3\n"
        let (scriptPath, repoPath, cleanup) = try createTempScript(content: scriptOutput)
        defer { cleanup() }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(description: "Default message", violationScript: scriptPath, rulesDir: repoPath)
        let task = makeRuleRequest(rule: rule, filePath: "Calculator.swift", startLine: 1, endLine: 100)
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "import A", contentChange: .added, newLineNumber: 15),
            makePRLine(content: "import B", contentChange: .added, newLineNumber: 23),
        ])]

        // Act
        let result = service.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.count == 2)
            #expect(r.violations[0].lineNumber == 15)
            #expect(r.violations[0].comment == "Import out of order")
            #expect(r.violations[1].lineNumber == 23)
            #expect(r.violations[1].comment == "Default message")
            if case .script(let path) = r.analysisMethod {
                #expect(path == scriptPath)
            } else {
                Issue.record("Expected .script analysis method")
            }
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("empty stdout returns success with no violations")
    func emptyStdout() throws {
        // Arrange
        let (scriptPath, repoPath, cleanup) = try createTempScript(content: "")
        defer { cleanup() }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: scriptPath, rulesDir: repoPath)
        let task = makeRuleRequest(rule: rule)

        // Act
        let result = service.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: [])

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.isEmpty)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("non-zero exit code returns error with stderr")
    func nonZeroExit() throws {
        // Arrange
        let (scriptPath, repoPath, cleanup) = try createTempScript(content: "", exitCode: 1, stderr: "Script failed")
        defer { cleanup() }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: scriptPath, rulesDir: repoPath)
        let task = makeRuleRequest(rule: rule)

        // Act
        let result = service.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: [])

        // Assert
        if case .error(let e) = result {
            #expect(e.errorMessage.contains("Script failed"))
        } else {
            Issue.record("Expected error, got \(result)")
        }
    }

    @Test("script not found returns error")
    func scriptNotFound() {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: "scripts/nonexistent.sh", rulesDir: repoDir.path)
        let task = makeRuleRequest(rule: rule)

        // Act
        let result = service.analyzeTask(task, scriptPath: "scripts/nonexistent.sh", repoPath: repoDir.path, hunks: [])

        // Assert
        if case .error(let e) = result {
            #expect(e.errorMessage.contains("not found"))
        } else {
            Issue.record("Expected error, got \(result)")
        }
    }

    @Test("script not executable returns error")
    func scriptNotExecutable() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptsDir = repoDir.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let scriptURL = scriptsDir.appendingPathComponent("check.sh")
        try "#!/bin/bash\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: repoDir) }

        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: "scripts/check.sh", rulesDir: repoDir.path)
        let task = makeRuleRequest(rule: rule)

        // Act
        let result = service.analyzeTask(task, scriptPath: "scripts/check.sh", repoPath: repoDir.path, hunks: [])

        // Assert
        if case .error(let e) = result {
            #expect(e.errorMessage.contains("not executable"))
        } else {
            Issue.record("Expected error, got \(result)")
        }
    }

    @Test("post-filtering: only violations on changed lines survive")
    func postFiltering() throws {
        // Arrange — script reports violations on lines 10, 15, 20; only line 15 is changed
        let scriptOutput = "10\t0\t5\tLine 10\n15\t0\t5\tLine 15\n20\t0\t5\tLine 20\n"
        let (scriptPath, repoPath, cleanup) = try createTempScript(content: scriptOutput)
        defer { cleanup() }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: scriptPath, rulesDir: repoPath)
        let task = makeRuleRequest(rule: rule)
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "changed line", contentChange: .added, newLineNumber: 15),
        ])]

        // Act
        let result = service.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.count == 1)
            #expect(r.violations[0].lineNumber == 15)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("newCodeLinesOnly: true filters to only added lines")
    func newCodeLinesOnlyFiltering() throws {
        // Arrange — script reports violations on lines 10, 11, 12
        // Line 10 is added, line 11 is changed (in move), line 12 is removed
        let scriptOutput = "10\t0\t5\n11\t0\t5\n12\t0\t5\n"
        let (scriptPath, repoPath, cleanup) = try createTempScript(content: scriptOutput)
        defer { cleanup() }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: scriptPath, newCodeLinesOnly: true, rulesDir: repoPath)
        let task = makeRuleRequest(rule: rule)
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "added", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "changed in move", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "removed", contentChange: .deleted, lineType: .removed, oldLineNumber: 12),
        ])]

        // Act
        let result = service.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: hunks)

        // Assert — only line 10 (changeKind == .added) passes
        if case .success(let r) = result {
            #expect(r.violations.count == 1)
            #expect(r.violations[0].lineNumber == 10)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("newCodeLinesOnly: false allows all changed lines")
    func allChangedLinesFiltering() throws {
        // Arrange
        let scriptOutput = "10\t0\t5\n11\t0\t5\n12\t0\t5\n13\t0\t5\n"
        let (scriptPath, repoPath, cleanup) = try createTempScript(content: scriptOutput)
        defer { cleanup() }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: scriptPath, newCodeLinesOnly: false, rulesDir: repoPath)
        let task = makeRuleRequest(rule: rule)
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "added", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "changed", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "removed", contentChange: .deleted, lineType: .removed, oldLineNumber: 12),
            makePRLine(content: "context", contentChange: .unchanged, lineType: .context, newLineNumber: 13),
        ])]

        // Act
        let result = service.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: hunks)

        // Assert — lines 10, 11, 12 pass (changed); line 13 (unchanged) does not
        if case .success(let r) = result {
            #expect(r.violations.count == 3)
            let lineNums = Set(r.violations.compactMap(\.lineNumber))
            #expect(lineNums == Set([10, 11, 12]))
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("malformed script output returns error")
    func malformedOutput() throws {
        // Arrange
        let scriptOutput = "this is not valid TSV"
        let (scriptPath, repoPath, cleanup) = try createTempScript(content: scriptOutput)
        defer { cleanup() }
        let service = ScriptAnalysisService()
        let rule = makeTaskRule(violationScript: scriptPath, rulesDir: repoPath)
        let task = makeRuleRequest(rule: rule)

        // Act
        let result = service.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: [])

        // Assert
        if case .error(let e) = result {
            #expect(e.errorMessage.contains("column"))
        } else {
            Issue.record("Expected error, got \(result)")
        }
    }
}

// MARK: - AnalysisMethod.script Codable Tests

@Suite("AnalysisMethod.script Codable")
struct AnalysisMethodScriptCodableTests {

    @Test("round-trips through JSON encode/decode")
    func roundTrip() throws {
        // Arrange
        let method = AnalysisMethod.script(path: "scripts/check-import-order.sh")

        // Act
        let data = try JSONEncoder().encode(method)
        let decoded = try JSONDecoder().decode(AnalysisMethod.self, from: data)

        // Assert
        #expect(decoded == method)
        if case .script(let path) = decoded {
            #expect(path == "scripts/check-import-order.sh")
        } else {
            Issue.record("Expected .script, got \(decoded)")
        }
    }

    @Test("encodes with type discriminator")
    func encodesTypeDiscriminator() throws {
        // Arrange
        let method = AnalysisMethod.script(path: "scripts/check.sh")

        // Act
        let data = try JSONEncoder().encode(method)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Assert
        #expect(json?["type"] as? String == "script")
        #expect(json?["path"] as? String == "scripts/check.sh")
    }

    @Test("displayName returns Script")
    func displayName() {
        // Arrange
        let method = AnalysisMethod.script(path: "scripts/check.sh")

        // Assert
        #expect(method.displayName == "Script")
    }

    @Test("costUsd returns 0")
    func costIsZero() {
        // Arrange
        let method = AnalysisMethod.script(path: "scripts/check.sh")

        // Assert
        #expect(method.costUsd == 0)
    }
}
