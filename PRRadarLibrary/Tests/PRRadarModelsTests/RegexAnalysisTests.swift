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
        violationMessage: violationMessage,
        rulesDir: "/tmp/rules"
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
    return RuleRequest(taskId: "\(rule.name)_\(filePath)", rule: rule, focusArea: focusArea, gitBlobHash: "abc123", ruleBlobHash: "hash123")
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
        #expect(rule.analysisType == .regex)

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
        #expect(rule.analysisType == .ai)

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
        #expect(decoded.analysisType == .regex)
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
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "guard b != 0 else { return nil }", contentChange: .added, newLineNumber: 20),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "return nil", hunks: hunks)

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
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "let x = Optional.some(42)", contentChange: .added, newLineNumber: 5),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "force_unwrap!", hunks: hunks)

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
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "guard a != 0 else { return nil }", contentChange: .added, newLineNumber: 20),
            makePRLine(content: "return 1.0 / Double(a)", contentChange: .added, newLineNumber: 21),
            makePRLine(content: "guard b != 0 else { return nil }", contentChange: .added, newLineNumber: 25),
            makePRLine(content: "guard c != 0 else { return nil }", contentChange: .added, newLineNumber: 30),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "return nil", hunks: hunks)

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
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "return nil", contentChange: .added, newLineNumber: 1),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "return nil", hunks: hunks)

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
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "return nil", contentChange: .added, newLineNumber: 1),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "return nil", hunks: hunks)

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
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "return nil", contentChange: .added, newLineNumber: 1),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "return nil", hunks: hunks)

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
        let (result, _) = service.analyzeTask(task, pattern: "[invalid", hunks: [])

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
        let (result, _) = service.analyzeTask(task, pattern: "return nil", hunks: [])

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

    @Test("newCodeLinesOnly checks only added lines (changeKind == .added)")
    func newCodeLinesOnlyFiltering() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "TODO", newCodeLinesOnly: true)
        let task = makeRuleRequest(rule: rule)
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "// TODO: new task", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "// TODO: moved task", contentChange: .unchanged, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "// TODO: changed in move", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 12),
            makePRLine(content: "// TODO: context", contentChange: .unchanged, lineType: .context, newLineNumber: 13),
            makePRLine(content: "// TODO: removed", contentChange: .deleted, lineType: .removed, oldLineNumber: 5),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "TODO", hunks: hunks)

        // Assert — only .new (changeKind == .added) passes; .changedInMove (changeKind == .changed) is excluded
        if case .success(let r) = result {
            #expect(r.violations.count == 1)
            let lineNumbers = r.violations.compactMap(\.lineNumber)
            #expect(lineNumbers.contains(10))
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
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "// TODO: new", contentChange: .added, newLineNumber: 10),
            makePRLine(content: "// TODO: removed", contentChange: .deleted, lineType: .removed, oldLineNumber: 5),
            makePRLine(content: "// TODO: changed", contentChange: .modified, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 12),
            makePRLine(content: "// TODO: moved", contentChange: .unchanged, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 11),
            makePRLine(content: "// TODO: context", contentChange: .unchanged, lineType: .context, newLineNumber: 13),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "TODO", hunks: hunks)

        // Assert
        if case .success(let r) = result {
            #expect(r.violations.count == 3)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("newCodeLinesOnly detects violations in new insertions inside moved blocks")
    func newCodeLinesOnlyDetectsAddedInsideMovedBlock() {
        // Arrange
        let service = RegexAnalysisService()
        let rule = makeTaskRule(violationRegex: "TODO", newCodeLinesOnly: true)
        let task = makeRuleRequest(rule: rule)
        let hunks = [makePRHunk(lines: [
            makePRLine(content: "// TODO: inserted in move", contentChange: .added, newLineNumber: 15),
            makePRLine(content: "// TODO: just moved", contentChange: .unchanged, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)), newLineNumber: 16),
        ])]

        // Act
        let (result, _) = service.analyzeTask(task, pattern: "TODO", hunks: hunks)

        // Assert — .added + move passes the filter because changeKind == .added
        if case .success(let r) = result {
            #expect(r.violations.count == 1)
            #expect(r.violations[0].lineNumber == 15)
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }
}

// MARK: - Focus Area Filtering Tests

@Suite("PRHunk focus area filtering")
struct PRHunkFocusAreaFilteringTests {

    @Test("filterForFocusArea filters by file path and line range")
    func filtersByFileAndRange() {
        // Arrange
        let hunks = [
            makePRHunk(filePath: "A.swift", lines: [
                makePRLine(content: "line1", contentChange: .added, filePath: "A.swift", newLineNumber: 5),
                makePRLine(content: "line2", contentChange: .added, filePath: "A.swift", newLineNumber: 15),
                makePRLine(content: "line3", contentChange: .added, filePath: "A.swift", newLineNumber: 25),
            ]),
            makePRHunk(filePath: "B.swift", lines: [
                makePRLine(content: "other", contentChange: .added, filePath: "B.swift", newLineNumber: 10),
            ]),
        ]
        let focusArea = FocusArea(
            focusId: "A.swift", filePath: "A.swift",
            startLine: 10, endLine: 20,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let filtered = PRHunk.filterForFocusArea(hunks, focusArea: focusArea)

        // Assert
        #expect(filtered.count == 1)
        #expect(filtered[0].lines.count == 1)
        #expect(filtered[0].lines[0].newLineNumber == 15)
    }

    @Test("filterForFocusArea returns empty when no file matches")
    func noFileMatch() {
        // Arrange
        let hunks = [
            makePRHunk(filePath: "A.swift", lines: [
                makePRLine(content: "code", contentChange: .added, filePath: "A.swift", newLineNumber: 5),
            ]),
        ]
        let focusArea = FocusArea(
            focusId: "B.swift", filePath: "B.swift",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let filtered = PRHunk.filterForFocusArea(hunks, focusArea: focusArea)

        // Assert
        #expect(filtered.isEmpty)
    }
}

// MARK: - Grep Filtering with PRHunks

@Suite("Grep filtering uses clean source content from PRHunks")
struct GrepFilteringPRHunkTests {

    private func makeRule(
        name: String = "test-rule",
        grepAny: [String]? = nil,
        grepAll: [String]? = nil,
        appliesTo: AppliesTo? = nil
    ) -> ReviewRule {
        ReviewRule(
            name: name,
            filePath: "/rules/\(name).md",
            description: "Test rule",
            category: "test",
            content: "Rule body",
            appliesTo: appliesTo,
            grep: GrepPatterns(all: grepAll, any: grepAny)
        )
    }

    @Test("ObjC method pattern matches clean source without diff prefix collision")
    func objcMethodPatternMatchesCleanSource() {
        // Arrange
        let rule = makeRule(
            name: "nullability",
            grepAny: ["^[+-]\\s*\\("],
            appliesTo: AppliesTo(filePatterns: ["*.h"])
        )
        let hunks = [makePRHunk(filePath: "Header.h", lines: [
            makePRLine(
                content: "- (UITabBarItem *)foo;",
                contentChange: .added,
                filePath: "Header.h",
                newLineNumber: 70
            ),
        ])]
        let focusArea = FocusArea(
            focusId: "Header.h", filePath: "Header.h",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let focusedHunks = PRHunk.filterForFocusArea(hunks, focusArea: focusArea)
        let changedContent = focusedHunks
            .flatMap { $0.changedLines }
            .map { $0.content }
            .joined(separator: "\n")

        // Assert
        #expect(rule.matchesDiffContent(changedContent))
    }

    @Test("ObjC class method pattern matches clean source")
    func objcClassMethodPatternMatchesCleanSource() {
        // Arrange
        let rule = makeRule(grepAny: ["^[+-]\\s*\\("])
        let hunks = [makePRHunk(filePath: "Header.h", lines: [
            makePRLine(
                content: "+ (instancetype)sharedInstance;",
                contentChange: .added,
                filePath: "Header.h",
                newLineNumber: 10
            ),
        ])]
        let focusArea = FocusArea(
            focusId: "Header.h", filePath: "Header.h",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let focusedHunks = PRHunk.filterForFocusArea(hunks, focusArea: focusArea)
        let changedContent = focusedHunks
            .flatMap { $0.changedLines }
            .map { $0.content }
            .joined(separator: "\n")

        // Assert
        #expect(rule.matchesDiffContent(changedContent))
    }

    @Test("@import pattern matches added import line")
    func importPatternMatchesAddedLine() {
        // Arrange
        let rule = makeRule(grepAny: ["@import"])
        let hunks = [makePRHunk(lines: [
            makePRLine(
                content: "@import UIKit;",
                contentChange: .added,
                newLineNumber: 1
            ),
        ])]
        let focusArea = FocusArea(
            focusId: "Calculator.swift", filePath: "Calculator.swift",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let focusedHunks = PRHunk.filterForFocusArea(hunks, focusArea: focusArea)
        let changedContent = focusedHunks
            .flatMap { $0.changedLines }
            .map { $0.content }
            .joined(separator: "\n")

        // Assert
        #expect(rule.matchesDiffContent(changedContent))
    }

    @Test("moved lines are excluded from grep matching")
    func movedLinesExcluded() {
        // Arrange
        let rule = makeRule(grepAny: ["@import"])
        let hunks = [makePRHunk(lines: [
            makePRLine(
                content: "@import UIKit;",
                contentChange: .unchanged, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)),
                newLineNumber: 1
            ),
            makePRLine(
                content: "@import Foundation;",
                contentChange: .unchanged, pairing: Pairing(role: .after, counterpart: Counterpart(filePath: "a", lineNumber: 1)),
                lineType: .removed,
                oldLineNumber: 5
            ),
        ])]
        let focusArea = FocusArea(
            focusId: "Calculator.swift", filePath: "Calculator.swift",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let focusedHunks = PRHunk.filterForFocusArea(hunks, focusArea: focusArea)
        let changedContent = focusedHunks
            .flatMap { $0.changedLines }
            .map { $0.content }
            .joined(separator: "\n")

        // Assert
        #expect(!rule.matchesDiffContent(changedContent))
    }

    @Test("context lines are excluded from grep matching")
    func contextLinesExcluded() {
        // Arrange
        let rule = makeRule(grepAny: ["@import"])
        let hunks = [makePRHunk(lines: [
            makePRLine(
                content: "@import UIKit;",
                contentChange: .unchanged,
                lineType: .context,
                newLineNumber: 1
            ),
        ])]
        let focusArea = FocusArea(
            focusId: "Calculator.swift", filePath: "Calculator.swift",
            startLine: 1, endLine: 100,
            description: "test", hunkIndex: 0, hunkContent: ""
        )

        // Act
        let focusedHunks = PRHunk.filterForFocusArea(hunks, focusArea: focusArea)
        let changedContent = focusedHunks
            .flatMap { $0.changedLines }
            .map { $0.content }
            .joined(separator: "\n")

        // Assert
        #expect(!rule.matchesDiffContent(changedContent))
    }
}

// MARK: - Pipeline Routing Tests

@Suite("Pipeline routing based on rule configuration")
struct PipelineRoutingTests {

    @Test("TaskRule.analysisType is .regex when violationRegex is set")
    func analysisTypeRegex() {
        // Arrange
        let rule = TaskRule(name: "r", description: "d", category: "c", content: "b", violationRegex: "pattern", rulesDir: "/tmp/rules")

        // Assert
        #expect(rule.analysisType == .regex)
    }

    @Test("TaskRule.analysisType is .ai when violationRegex is nil")
    func analysisTypeAI() {
        // Arrange
        let rule = TaskRule(name: "r", description: "d", category: "c", content: "b", rulesDir: "/tmp/rules")

        // Assert
        #expect(rule.analysisType == .ai)
    }

    @Test("ReviewRule.analysisType matches TaskRule after RuleRequest.from()")
    func analysisTypePropagates() {
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
        let request = RuleRequest.from(rule: reviewRule, focusArea: focusArea, gitBlobHash: "abc", ruleBlobHash: "hash123", rulesDir: "/tmp/rules")

        // Assert
        #expect(request.rule.analysisType == .regex)
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
            violationMessage: "Avoid force unwrapping",
            rulesDir: "/tmp/rules"
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
