import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRRadarModels

@Suite("Flat Task-Level Caching")
struct FlatTaskLevelCachingTests {

    // MARK: - Task ID Uniqueness

    @Test("Same-named rules from different directories produce different task IDs")
    func taskIdUniquenessAcrossRuleDirs() {
        // Arrange
        let rule = ReviewRule(
            name: "no-force-unwrap",
            filePath: "/rules/swift-rules/no-force-unwrap.md",
            description: "No force unwraps",
            category: "safety",
            content: "Avoid force unwrapping"
        )
        let focusArea = FocusArea(
            focusId: "file-main-1-10",
            filePath: "main.swift",
            startLine: 1,
            endLine: 10,
            description: "main file",
            hunkIndex: 0,
            hunkContent: "@@ content"
        )

        // Act
        let taskA = RuleRequest.from(rule: rule, focusArea: focusArea, gitBlobHash: "abc123", rulesDir: "/rules/swift-rules")
        let taskB = RuleRequest.from(rule: rule, focusArea: focusArea, gitBlobHash: "abc123", rulesDir: "/rules/security-rules")

        // Assert
        #expect(taskA.taskId != taskB.taskId)
        #expect(taskA.taskId.contains("swift-rules"))
        #expect(taskB.taskId.contains("security-rules"))
    }

    @Test("rulesDirSlug returns last path component")
    func rulesDirSlugReturnsLastComponent() {
        #expect(RuleRequest.rulesDirSlug("/Users/bill/rules/swift-rules") == "swift-rules")
        #expect(RuleRequest.rulesDirSlug("/tmp/security-rules") == "security-rules")
        #expect(RuleRequest.rulesDirSlug("/rules") == "rules")
    }

    @Test("Task ID format includes rule name, focus ID, and rules dir slug")
    func taskIdFormatIncludesAllComponents() {
        // Arrange
        let rule = ReviewRule(
            name: "error-handling",
            filePath: "/rules/error-handling.md",
            description: "Check errors",
            category: "reliability",
            content: "Content"
        )
        let focusArea = FocusArea(
            focusId: "file-app-5-15",
            filePath: "app.swift",
            startLine: 5,
            endLine: 15,
            description: "app file",
            hunkIndex: 0,
            hunkContent: "@@ content"
        )

        // Act
        let task = RuleRequest.from(rule: rule, focusArea: focusArea, gitBlobHash: "deadbeef", rulesDir: "/tmp/my-rules")

        // Assert
        #expect(task.taskId == "error-handling_file-app-5-15_my-rules")
    }

    // MARK: - Additive Task File Writes

    @Test("Writing tasks to directory preserves existing task files")
    func additiveTaskFileWrites() throws {
        // Arrange
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prradar-test-\(UUID().uuidString)")
            .appendingPathComponent(DataPathsService.prepareTasksSubdir)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let existingTask = RuleRequest(
            taskId: "existing-rule_file-foo-1-5_swift-rules",
            rule: TaskRule(
                name: "existing-rule",
                description: "Existing",
                category: "test",
                content: "content",
                rulesDir: "/rules/swift-rules"
            ),
            focusArea: FocusArea(
                focusId: "file-foo-1-5",
                filePath: "foo.swift",
                startLine: 1, endLine: 5,
                description: "foo", hunkIndex: 0, hunkContent: "@@ content"
            ),
            gitBlobHash: "aaa111"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let existingData = try encoder.encode(existingTask)
        let existingFilePath = tmpDir.appendingPathComponent("\(DataPathsService.dataFilePrefix)\(existingTask.taskId).json")
        try existingData.write(to: existingFilePath)

        // Act - write a new task file (simulating what TaskCreatorService does)
        let newTask = RuleRequest(
            taskId: "new-rule_file-bar-1-5_security-rules",
            rule: TaskRule(
                name: "new-rule",
                description: "New",
                category: "test",
                content: "content",
                rulesDir: "/rules/security-rules"
            ),
            focusArea: FocusArea(
                focusId: "file-bar-1-5",
                filePath: "bar.swift",
                startLine: 1, endLine: 5,
                description: "bar", hunkIndex: 0, hunkContent: "@@ content"
            ),
            gitBlobHash: "bbb222"
        )
        let newData = try encoder.encode(newTask)
        let newFilePath = tmpDir.appendingPathComponent("\(DataPathsService.dataFilePrefix)\(newTask.taskId).json")
        try newData.write(to: newFilePath)

        // Assert - both files exist
        let files = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
            .filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }
            .sorted()
        #expect(files.count == 2)
        #expect(files.contains("\(DataPathsService.dataFilePrefix)existing-rule_file-foo-1-5_swift-rules.json"))
        #expect(files.contains("\(DataPathsService.dataFilePrefix)new-rule_file-bar-1-5_security-rules.json"))

        // Verify existing file content is intact
        let readBack = try Data(contentsOf: existingFilePath)
        let decoded = try JSONDecoder().decode(RuleRequest.self, from: readBack)
        #expect(decoded.taskId == existingTask.taskId)
    }

    // MARK: - Focus Area Cache

    @Test("Focus areas loaded from disk when files already exist")
    func focusAreaCacheLoading() throws {
        // Arrange
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prradar-focus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let focusAreas = [
            FocusArea(
                focusId: "file-main-1-10",
                filePath: "main.swift",
                startLine: 1, endLine: 10,
                description: "main file", hunkIndex: 0, hunkContent: "@@ content"
            ),
            FocusArea(
                focusId: "file-app-5-15",
                filePath: "app.swift",
                startLine: 5, endLine: 15,
                description: "app file", hunkIndex: 0, hunkContent: "@@ more content"
            ),
        ]

        let typeOutput = FocusAreaTypeOutput(
            prNumber: 1,
            generatedAt: "2026-01-01T00:00:00Z",
            focusType: "file",
            focusAreas: focusAreas,
            totalHunksProcessed: 2,
            generationCostUsd: 0.01
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(typeOutput)
        let filePath = tmpDir.appendingPathComponent("\(DataPathsService.dataFilePrefix)file.json")
        try data.write(to: filePath)

        // Act - simulate PrepareUseCase cache check
        let existingFiles = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
            .filter { $0.hasPrefix(DataPathsService.dataFilePrefix) && $0.hasSuffix(".json") }

        var loadedFocusAreas: [FocusArea] = []
        for file in existingFiles {
            let fileData = try Data(contentsOf: URL(fileURLWithPath: "\(tmpDir.path)/\(file)"))
            let output = try JSONDecoder().decode(FocusAreaTypeOutput.self, from: fileData)
            loadedFocusAreas.append(contentsOf: output.focusAreas)
        }

        // Assert
        #expect(!existingFiles.isEmpty)
        #expect(loadedFocusAreas.count == 2)
        #expect(loadedFocusAreas[0].focusId == "file-app-5-15" || loadedFocusAreas[0].focusId == "file-main-1-10")
    }

    // MARK: - Rules File Per-Directory

    @Test("Rules files use per-directory naming")
    func rulesFilePerDirectoryNaming() {
        // Arrange & Act
        let filenameA = DataPathsService.rulesFilename(forRulesDir: "/rules/swift-rules")
        let filenameB = DataPathsService.rulesFilename(forRulesDir: "/rules/security-rules")

        // Assert
        #expect(filenameA == "rules-swift-rules.json")
        #expect(filenameB == "rules-security-rules.json")
        #expect(filenameA != filenameB)
    }

    @Test("isRulesFile matches per-directory rules files")
    func isRulesFileMatchesPerDirFiles() {
        #expect(DataPathsService.isRulesFile("rules-swift-rules.json"))
        #expect(DataPathsService.isRulesFile("rules-security-rules.json"))
        #expect(!DataPathsService.isRulesFile("data-task1.json"))
        #expect(!DataPathsService.isRulesFile("all-rules.json"))
    }

    // MARK: - TaskRule Preserves rulesDir

    @Test("TaskRule created via factory preserves rulesDir from source")
    func taskRulePreservesRulesDir() {
        // Arrange
        let rule = ReviewRule(
            name: "test-rule",
            filePath: "/rules/my-dir/test-rule.md",
            description: "Test",
            category: "test",
            content: "Content"
        )

        // Act
        let task = RuleRequest.from(rule: rule, focusArea: FocusArea(
            focusId: "file-x-1-5",
            filePath: "x.swift",
            startLine: 1, endLine: 5,
            description: "x", hunkIndex: 0, hunkContent: "@@ content"
        ), gitBlobHash: "abc", rulesDir: "/rules/my-dir")

        // Assert
        #expect(task.rule.rulesDir == "/rules/my-dir")
    }
}
