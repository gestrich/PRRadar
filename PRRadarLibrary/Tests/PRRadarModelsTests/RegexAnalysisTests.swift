import Foundation
import Testing
@testable import PRRadarCLIService
@testable import PRRadarModels

// MARK: - Helpers

private func makeClassifiedLine(
    content: String,
    classification: LineClassification,
    lineType: DiffLineType = .added,
    filePath: String = "Calculator.swift",
    newLineNumber: Int? = nil,
    oldLineNumber: Int? = nil
) -> ClassifiedDiffLine {
    ClassifiedDiffLine(
        content: content,
        rawLine: lineType == .added ? "+\(content)" : lineType == .removed ? "-\(content)" : " \(content)",
        lineType: lineType,
        classification: classification,
        newLineNumber: newLineNumber ?? (lineType == .added ? 1 : nil),
        oldLineNumber: oldLineNumber ?? (lineType == .removed ? 1 : nil),
        filePath: filePath
    )
}

private func makeClassifiedHunk(
    filePath: String = "Calculator.swift",
    lines: [ClassifiedDiffLine]
) -> ClassifiedHunk {
    ClassifiedHunk(filePath: filePath, oldStart: 1, newStart: 1, lines: lines)
}

private func makeTaskRule(
    name: String = "test-rule",
    violationRegex: String? = nil,
    violationMessage: String? = nil,
    newCodeLinesOnly: Bool = false
) -> TaskRule {
    TaskRule(
        name: name,
        description: "Test rule description",
        category: "safety",
        content: "Rule body",
        newCodeLinesOnly: newCodeLinesOnly,
        violationRegex: violationRegex,
        violationMessage: violationMessage
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

// MARK: - ReviewRule YAML Parsing Tests

@Suite("ReviewRule regex fields parsing")
struct ReviewRuleRegexParsingTests {

    @Test("fromFile parses violation_regex from YAML frontmatter")
    func fromFileViolationRegex() throws {
        // Arrange
        let content = """
        ---
        description: Test rule
        category: safety
        violation_regex: "return nil"
        ---
        Body
        """
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("test-rule.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        let rule = try ReviewRule.fromFile(fileURL)

        // Assert
        #expect(rule.violationRegex == "return nil")
        #expect(rule.isRegexOnly == true)

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("fromFile parses violation_message from YAML frontmatter")
    func fromFileViolationMessage() throws {
        // Arrange
        let content = """
        ---
        description: Test rule
        category: safety
        violation_regex: "![^=]"
        violation_message: "Avoid force unwrapping"
        ---
        Body
        """
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("test-rule.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        let rule = try ReviewRule.fromFile(fileURL)

        // Assert
        #expect(rule.violationMessage == "Avoid force unwrapping")

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("fromFile parses new_code_lines_only as true")
    func fromFileNewCodeLinesOnly() throws {
        // Arrange
        let content = """
        ---
        description: Test rule
        category: safety
        new_code_lines_only: true
        ---
        Body
        """
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("test-rule.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        let rule = try ReviewRule.fromFile(fileURL)

        // Assert
        #expect(rule.newCodeLinesOnly == true)

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("fromFile defaults new_code_lines_only to false when omitted")
    func fromFileNewCodeLinesOnlyDefault() throws {
        // Arrange
        let content = """
        ---
        description: Test rule
        category: safety
        ---
        Body
        """
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("test-rule.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        let rule = try ReviewRule.fromFile(fileURL)

        // Assert
        #expect(rule.newCodeLinesOnly == false)
        #expect(rule.violationRegex == nil)
        #expect(rule.isRegexOnly == false)

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("ReviewRule violation_regex round-trips through JSON encode/decode")
    func roundTrip() throws {
        // Arrange
        let rule = ReviewRule(
            name: "test",
            filePath: "/test.md",
            description: "Test",
            category: "safety",
            content: "body",
            newCodeLinesOnly: true,
            violationRegex: "return nil",
            violationMessage: "Don't return nil"
        )

        // Act
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ReviewRule.self, from: data)

        // Assert
        #expect(decoded.violationRegex == "return nil")
        #expect(decoded.violationMessage == "Don't return nil")
        #expect(decoded.newCodeLinesOnly == true)
        #expect(decoded.isRegexOnly == true)
    }
}

// MARK: - RegexAnalysisService Tests

@Suite("RegexAnalysisService")
struct RegexAnalysisServiceTests {

    @Test("matches single line with violation_regex")
    func singleMatch() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "return nil")
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "guard b != 0 else { return nil }", classification: .new, newLineNumber: 20),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "return nil", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.count == 1)
            #expect(r.violations[0].lineNumber == 20)
            #expect(r.violations[0].filePath == "Calculator.swift")
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("returns no violations when regex doesn't match")
    func noMatch() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "force_unwrap!")
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "let x = Optional.some(42)", classification: .new, newLineNumber: 5),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "force_unwrap!", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.isEmpty)
            #expect(!r.violatesRule)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("matches multiple lines producing multiple violations")
    func multiMatch() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "return nil")
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "guard a != 0 else { return nil }", classification: .new, newLineNumber: 20),
            makeClassifiedLine(content: "return 1.0 / Double(a)", classification: .new, newLineNumber: 21),
            makeClassifiedLine(content: "guard b != 0 else { return nil }", classification: .new, newLineNumber: 25),
            makeClassifiedLine(content: "guard c != 0 else { return nil }", classification: .new, newLineNumber: 30),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "return nil", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.count == 3)
            #expect(r.violations.map(\.lineNumber) == [20, 25, 30])
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("uses violation_message for comment text when available")
    func usesViolationMessage() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "return nil", violationMessage: "Custom message")
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "return nil", classification: .new, newLineNumber: 1),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "return nil", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations[0].comment == "Custom message")
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("falls back to rule description when violation_message is nil")
    func fallsBackToDescription() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "return nil")
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "return nil", classification: .new, newLineNumber: 1),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "return nil", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations[0].comment == "Test rule description")
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("returns regex analysis method with pattern")
    func analysisMethodIsRegex() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "return nil")
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "return nil", classification: .new, newLineNumber: 1),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "return nil", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            if case .regex(let p) = r.analysisMethod {
                #expect(p == "return nil")
            } else {
                Issue.record("Expected .regex analysis method")
            }
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("returns error for invalid regex pattern")
    func invalidRegex() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "[invalid")
        let task = makeRuleRequest(rule: rule)

        // Act
        let result = service.analyzeTask(task, pattern: "[invalid", classifiedHunks: [])

        // Assert
        if case .error(let e) = result {
            #expect(e.errorMessage.contains("Invalid regex"))
        } else {
            Issue.record("Expected error, got \(result)")
        }
    }

    @Test("returns no violations for empty classified hunks")
    func emptyHunks() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "return nil")
        let task = makeRuleRequest(rule: rule)

        // Act
        let result = service.analyzeTask(task, pattern: "return nil", classifiedHunks: [])

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.isEmpty)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }
}

// MARK: - New Code Only Filtering Tests

@Suite("RegexAnalysisService new code only filtering")
struct RegexNewCodeOnlyTests {

    @Test("newCodeLinesOnly checks only .new and .changedInMove lines")
    func newCodeLinesOnlyFiltering() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "TODO", newCodeLinesOnly: true)
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "// TODO: new task", classification: .new, newLineNumber: 10),
            makeClassifiedLine(content: "// TODO: moved task", classification: .moved, newLineNumber: 11),
            makeClassifiedLine(content: "// TODO: changed in move", classification: .changedInMove, newLineNumber: 12),
            makeClassifiedLine(content: "// TODO: context", classification: .context, lineType: .context, newLineNumber: 13),
            makeClassifiedLine(content: "// TODO: removed", classification: .removed, lineType: .removed, oldLineNumber: 5),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "TODO", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.count == 2)
            let lineNumbers = r.violations.compactMap(\.lineNumber)
            #expect(lineNumbers.contains(10))
            #expect(lineNumbers.contains(12))
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("without newCodeLinesOnly checks all changed lines")
    func allChangedLinesChecked() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "TODO", newCodeLinesOnly: false)
        let task = makeRuleRequest(rule: rule)
        let hunks = [makeClassifiedHunk(lines: [
            makeClassifiedLine(content: "// TODO: new", classification: .new, newLineNumber: 10),
            makeClassifiedLine(content: "// TODO: removed", classification: .removed, lineType: .removed, oldLineNumber: 5),
            makeClassifiedLine(content: "// TODO: changed", classification: .changedInMove, newLineNumber: 12),
            makeClassifiedLine(content: "// TODO: moved", classification: .moved, newLineNumber: 11),
            makeClassifiedLine(content: "// TODO: context", classification: .context, lineType: .context, newLineNumber: 13),
        ])]

        // Act
        let result = service.analyzeTask(task, pattern: "TODO", classifiedHunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.count == 3)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }
}

// MARK: - Focus Area Filtering Tests

@Suite("RegexAnalysisService focus area filtering")
struct RegexFocusAreaFilteringTests {

    @Test("filterHunksForFocusArea filters by file path and line range")
    func filtersByFileAndRange() {
        // Arrange
        let hunks = [
            makeClassifiedHunk(filePath: "A.swift", lines: [
                makeClassifiedLine(content: "line1", classification: .new, filePath: "A.swift", newLineNumber: 5),
                makeClassifiedLine(content: "line2", classification: .new, filePath: "A.swift", newLineNumber: 15),
                makeClassifiedLine(content: "line3", classification: .new, filePath: "A.swift", newLineNumber: 25),
            ]),
            makeClassifiedHunk(filePath: "B.swift", lines: [
                makeClassifiedLine(content: "other", classification: .new, filePath: "B.swift", newLineNumber: 10),
            ]),
        ]
        let focusArea = FocusArea(
            focusId: "A.swift", filePath: "A.swift",
            startLine: 10, endLine: 20,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let filtered = RegexAnalysisService.filterHunksForFocusArea(hunks, focusArea: focusArea)

        // Assert
        #expect(filtered.count == 1)
        #expect(filtered[0].lines.count == 1)
        #expect(filtered[0].lines[0].newLineNumber == 15)
    }

    @Test("filterHunksForFocusArea returns empty when no file matches")
    func noFileMatch() {
        // Arrange
        let hunks = [
            makeClassifiedHunk(filePath: "A.swift", lines: [
                makeClassifiedLine(content: "code", classification: .new, filePath: "A.swift", newLineNumber: 5),
            ]),
        ]
        let focusArea = FocusArea(
            focusId: "B.swift", filePath: "B.swift",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let filtered = RegexAnalysisService.filterHunksForFocusArea(hunks, focusArea: focusArea)

        // Assert
        #expect(filtered.isEmpty)
    }
}

// MARK: - Pipeline Routing Tests

@Suite("Pipeline routing based on rule configuration")
struct PipelineRoutingTests {

    @Test("TaskRule.isRegexOnly is true when violationRegex is set")
    func isRegexOnlyTrue() {
        // Arrange
        let rule = TaskRule(name: "r", description: "d", category: "c", content: "b", violationRegex: "pattern")

        // Assert
        #expect(rule.isRegexOnly == true)
    }

    @Test("TaskRule.isRegexOnly is false when violationRegex is nil")
    func isRegexOnlyFalse() {
        // Arrange
        let rule = TaskRule(name: "r", description: "d", category: "c", content: "b")

        // Assert
        #expect(rule.isRegexOnly == false)
    }

    @Test("ReviewRule.isRegexOnly matches TaskRule after RuleRequest.from()")
    func isRegexOnlyPropagates() {
        // Arrange
        let reviewRule = ReviewRule(
            name: "test",
            filePath: "/test.md",
            description: "Test",
            category: "safety",
            content: "body",
            violationRegex: "pattern"
        )
        let focusArea = FocusArea(
            focusId: "file.swift", filePath: "file.swift",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let request = RuleRequest.from(rule: reviewRule, focusArea: focusArea, gitBlobHash: "abc")

        // Assert
        #expect(request.rule.isRegexOnly == true)
        #expect(request.rule.violationRegex == "pattern")
    }

    @Test("TaskRule round-trips regex fields through JSON")
    func taskRuleRoundTrip() throws {
        // Arrange
        let rule = TaskRule(
            name: "test",
            description: "Test",
            category: "safety",
            content: "body",
            newCodeLinesOnly: true,
            violationRegex: "![^=]",
            violationMessage: "Avoid force unwrapping"
        )

        // Act
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(TaskRule.self, from: data)

        // Assert
        #expect(decoded.violationRegex == "![^=]")
        #expect(decoded.violationMessage == "Avoid force unwrapping")
        #expect(decoded.newCodeLinesOnly == true)
    }
}
