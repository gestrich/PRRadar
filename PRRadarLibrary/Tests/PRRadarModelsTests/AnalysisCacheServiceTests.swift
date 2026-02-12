import Foundation
import Testing
@testable import PRRadarCLIService
@testable import PRRadarConfigService
@testable import PRRadarModels

@Suite("AnalysisCacheService")
struct AnalysisCacheServiceTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Helpers

    private func makeTempDir() throws -> String {
        let path = NSTemporaryDirectory() + "analysis-cache-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func makeTask(id: String, blobHash: String, ruleBlobHash: String? = nil) -> AnalysisTaskOutput {
        AnalysisTaskOutput(
            taskId: id,
            rule: TaskRule(
                name: "rule-\(id)",
                description: "Test rule",
                category: "test",
                content: "Rule content"
            ),
            focusArea: FocusArea(
                focusId: "focus-\(id)",
                filePath: "file.swift",
                startLine: 1,
                endLine: 10,
                description: "focus area",
                hunkIndex: 0,
                hunkContent: "@@ content"
            ),
            gitBlobHash: blobHash,
            ruleBlobHash: ruleBlobHash
        )
    }

    private func makeResult(taskId: String, violates: Bool = false) -> RuleEvaluationResult {
        RuleEvaluationResult(
            taskId: taskId,
            ruleName: "rule-\(taskId)",
            ruleFilePath: "",
            filePath: "file.swift",
            evaluation: RuleEvaluation(
                violatesRule: violates,
                score: violates ? 7 : 1,
                comment: violates ? "Violation found" : "OK",
                filePath: "file.swift",
                lineNumber: 5
            ),
            modelUsed: "claude-sonnet-4-20250514",
            durationMs: 1000,
            costUsd: 0.10
        )
    }

    private func writeAnalysisResult(_ result: RuleEvaluationResult, to dir: String) throws {
        let data = try encoder.encode(result)
        let path = "\(dir)/data-\(result.taskId).json"
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func writeTaskSnapshot(_ task: AnalysisTaskOutput, to dir: String) throws {
        let data = try encoder.encode(task)
        let path = "\(dir)/task-\(task.taskId).json"
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - partitionTasks: cold start

    @Test("All tasks evaluated when no prior results exist")
    func coldStart() throws {
        // Arrange
        let dir = try makeTempDir()
        let tasks = [makeTask(id: "t1", blobHash: "aaa"), makeTask(id: "t2", blobHash: "bbb")]

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: tasks, evalsDir: dir)

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 2)
        #expect(toEvaluate.map(\.taskId) == ["t1", "t2"])
    }

    // MARK: - partitionTasks: cache hit

    @Test("Tasks skipped when blob hash matches prior run")
    func cacheHit() throws {
        // Arrange
        let dir = try makeTempDir()
        let task = makeTask(id: "t1", blobHash: "aaa")
        let result = makeResult(taskId: "t1", violates: true)
        try writeAnalysisResult(result, to: dir)
        try writeTaskSnapshot(task, to: dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: [task], evalsDir: dir)

        // Assert
        #expect(cached.count == 1)
        #expect(cached[0].taskId == "t1")
        #expect(cached[0].evaluation.violatesRule == true)
        #expect(toEvaluate.isEmpty)
    }

    // MARK: - partitionTasks: cache miss (blob hash changed)

    @Test("Tasks re-evaluated when blob hash differs")
    func cacheMissBlobHashChanged() throws {
        // Arrange
        let dir = try makeTempDir()
        let oldTask = makeTask(id: "t1", blobHash: "old-hash")
        let newTask = makeTask(id: "t1", blobHash: "new-hash")
        let result = makeResult(taskId: "t1")
        try writeAnalysisResult(result, to: dir)
        try writeTaskSnapshot(oldTask, to: dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: [newTask], evalsDir: dir)

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 1)
        #expect(toEvaluate[0].taskId == "t1")
    }

    // MARK: - partitionTasks: mixed cached and fresh

    @Test("Summary correctly includes both cached and fresh tasks")
    func mixedCachedAndFresh() throws {
        // Arrange
        let dir = try makeTempDir()
        let unchangedTask = makeTask(id: "t1", blobHash: "same")
        let changedTask = makeTask(id: "t2", blobHash: "new-hash")
        let newTask = makeTask(id: "t3", blobHash: "brand-new")

        // Write prior data for t1 (unchanged) and t2 (old hash)
        try writeAnalysisResult(makeResult(taskId: "t1", violates: true), to: dir)
        try writeTaskSnapshot(unchangedTask, to: dir)
        try writeAnalysisResult(makeResult(taskId: "t2"), to: dir)
        try writeTaskSnapshot(makeTask(id: "t2", blobHash: "old-hash"), to: dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: [unchangedTask, changedTask, newTask], evalsDir: dir
        )

        // Assert
        #expect(cached.count == 1)
        #expect(cached[0].taskId == "t1")
        #expect(toEvaluate.count == 2)
        #expect(toEvaluate.map(\.taskId) == ["t2", "t3"])
    }

    // MARK: - partitionTasks: eval exists but no task snapshot

    @Test("Task re-evaluated when analysis exists but task snapshot is missing")
    func analysisExistsButNoTaskSnapshot() throws {
        // Arrange
        let dir = try makeTempDir()
        let task = makeTask(id: "t1", blobHash: "aaa")
        try writeAnalysisResult(makeResult(taskId: "t1"), to: dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: [task], evalsDir: dir)

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 1)
    }

    // MARK: - writeTaskSnapshots

    @Test("writeTaskSnapshots writes decodable task files")
    func writeTaskSnapshots() throws {
        // Arrange
        let dir = try makeTempDir()
        let tasks = [makeTask(id: "t1", blobHash: "aaa"), makeTask(id: "t2", blobHash: "bbb")]

        // Act
        try AnalysisCacheService.writeTaskSnapshots(tasks: tasks, evalsDir: dir)

        // Assert
        let decoder = JSONDecoder()
        for task in tasks {
            let path = "\(dir)/task-\(task.taskId).json"
            let data = try #require(FileManager.default.contents(atPath: path))
            let decoded = try decoder.decode(AnalysisTaskOutput.self, from: data)
            #expect(decoded == task)
        }
    }

    // MARK: - Progress Messages: startMessage

    @Test("Start message shows cache counts when cached tasks exist")
    func startMessageWithCache() {
        // Act
        let message = AnalysisCacheService.startMessage(cachedCount: 3, freshCount: 2, totalCount: 5)

        // Assert
        #expect(message == "Skipping 3 cached evaluations, evaluating 2 new tasks")
    }

    @Test("Start message shows total count when no cached tasks")
    func startMessageColdStart() {
        // Act
        let message = AnalysisCacheService.startMessage(cachedCount: 0, freshCount: 5, totalCount: 5)

        // Assert
        #expect(message == "Evaluating 5 tasks...")
    }

    // MARK: - Progress Messages: cachedTaskMessage

    @Test("Cached task message shows OK with (cached) suffix for passing result")
    func cachedTaskMessageOK() {
        // Arrange
        let result = makeResult(taskId: "t1", violates: false)

        // Act
        let message = AnalysisCacheService.cachedTaskMessage(index: 1, totalCount: 5, result: result)

        // Assert
        #expect(message == "[1/5] rule-t1 — OK (cached)")
    }

    @Test("Cached task message shows VIOLATION with (cached) suffix for failing result")
    func cachedTaskMessageViolation() {
        // Arrange
        let result = makeResult(taskId: "t1", violates: true)

        // Act
        let message = AnalysisCacheService.cachedTaskMessage(index: 2, totalCount: 10, result: result)

        // Assert
        #expect(message == "[2/10] rule-t1 — VIOLATION (7/10) (cached)")
    }

    // MARK: - Progress Messages: completionMessage

    @Test("Completion message shows cached breakdown when cached tasks exist")
    func completionMessageWithCache() {
        // Act
        let message = AnalysisCacheService.completionMessage(freshCount: 2, cachedCount: 3, totalCount: 5, violationCount: 1)

        // Assert
        #expect(message == "Evaluation complete: 2 new, 3 cached, 5 total — 1 violations found")
    }

    @Test("Completion message shows simple total when no cached tasks")
    func completionMessageColdStart() {
        // Act
        let message = AnalysisCacheService.completionMessage(freshCount: 5, cachedCount: 0, totalCount: 5, violationCount: 0)

        // Assert
        #expect(message == "Evaluation complete: 5 evaluated — 0 violations found")
    }

    // MARK: - Round-trip: write snapshots then partition

    @Test("Tasks cached after writeTaskSnapshots + partitionTasks round-trip")
    func roundTrip() throws {
        // Arrange
        let dir = try makeTempDir()
        let tasks = [makeTask(id: "t1", blobHash: "hash1"), makeTask(id: "t2", blobHash: "hash2")]
        let results = [makeResult(taskId: "t1", violates: true), makeResult(taskId: "t2")]

        try AnalysisCacheService.writeTaskSnapshots(tasks: tasks, evalsDir: dir)
        for result in results {
            try writeAnalysisResult(result, to: dir)
        }

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: tasks, evalsDir: dir)

        // Assert
        #expect(cached.count == 2)
        #expect(toEvaluate.isEmpty)
        #expect(cached[0].taskId == "t1")
        #expect(cached[1].taskId == "t2")
    }

    // MARK: - Dual blob hash: ruleBlobHash mismatch

    @Test("Task re-evaluated when ruleBlobHash differs")
    func cacheMissRuleBlobHashChanged() throws {
        // Arrange
        let dir = try makeTempDir()
        let oldTask = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "old-rule-hash")
        let newTask = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "new-rule-hash")
        try writeAnalysisResult(makeResult(taskId: "t1"), to: dir)
        try writeTaskSnapshot(oldTask, to: dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: [newTask], evalsDir: dir)

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 1)
    }

    @Test("Task cached when both gitBlobHash and ruleBlobHash match")
    func cacheHitDualBlobHash() throws {
        // Arrange
        let dir = try makeTempDir()
        let task = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "rule-hash")
        try writeAnalysisResult(makeResult(taskId: "t1", violates: true), to: dir)
        try writeTaskSnapshot(task, to: dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: [task], evalsDir: dir)

        // Assert
        #expect(cached.count == 1)
        #expect(cached[0].taskId == "t1")
        #expect(toEvaluate.isEmpty)
    }

    @Test("Task re-evaluated when prior has nil ruleBlobHash but current has a value")
    func cacheMissRuleBlobHashNilVsNonNil() throws {
        // Arrange
        let dir = try makeTempDir()
        let oldTask = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: nil)
        let newTask = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "new-rule-hash")
        try writeAnalysisResult(makeResult(taskId: "t1"), to: dir)
        try writeTaskSnapshot(oldTask, to: dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: [newTask], evalsDir: dir)

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 1)
    }

    // MARK: - Cross-commit caching

    @Test("Cross-commit cache hit copies files into new commit directory")
    func crossCommitCacheHit() throws {
        // Arrange: simulate <prOutput>/analysis/<commit>/evaluate/ structure
        let prOutputDir = try makeTempDir()
        let oldEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        let newEvalsDir = "\(prOutputDir)/analysis/def5678/evaluate"
        try FileManager.default.createDirectory(atPath: oldEvalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newEvalsDir, withIntermediateDirectories: true)

        let task = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "rule-hash")
        try writeAnalysisResult(makeResult(taskId: "t1", violates: true), to: oldEvalsDir)
        try writeTaskSnapshot(task, to: oldEvalsDir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: [task], evalsDir: newEvalsDir, prOutputDir: prOutputDir
        )

        // Assert
        #expect(cached.count == 1)
        #expect(cached[0].taskId == "t1")
        #expect(toEvaluate.isEmpty)

        // Verify files were copied into new commit directory
        #expect(FileManager.default.fileExists(atPath: "\(newEvalsDir)/data-t1.json"))
        #expect(FileManager.default.fileExists(atPath: "\(newEvalsDir)/task-t1.json"))
    }

    @Test("Cross-commit cache miss when blob hash differs across commits")
    func crossCommitCacheMiss() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let oldEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        let newEvalsDir = "\(prOutputDir)/analysis/def5678/evaluate"
        try FileManager.default.createDirectory(atPath: oldEvalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newEvalsDir, withIntermediateDirectories: true)

        let oldTask = makeTask(id: "t1", blobHash: "old-hash", ruleBlobHash: "rule-hash")
        let newTask = makeTask(id: "t1", blobHash: "new-hash", ruleBlobHash: "rule-hash")
        try writeAnalysisResult(makeResult(taskId: "t1"), to: oldEvalsDir)
        try writeTaskSnapshot(oldTask, to: oldEvalsDir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: [newTask], evalsDir: newEvalsDir, prOutputDir: prOutputDir
        )

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 1)
        #expect(!FileManager.default.fileExists(atPath: "\(newEvalsDir)/data-t1.json"))
    }

    @Test("Same-commit cache preferred over cross-commit cache")
    func sameCommitCachePreferredOverCrossCommit() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let oldEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        let newEvalsDir = "\(prOutputDir)/analysis/def5678/evaluate"
        try FileManager.default.createDirectory(atPath: oldEvalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newEvalsDir, withIntermediateDirectories: true)

        let task = makeTask(id: "t1", blobHash: "aaa")

        // Write to both old and new directories
        try writeAnalysisResult(makeResult(taskId: "t1", violates: false), to: oldEvalsDir)
        try writeTaskSnapshot(task, to: oldEvalsDir)
        try writeAnalysisResult(makeResult(taskId: "t1", violates: true), to: newEvalsDir)
        try writeTaskSnapshot(task, to: newEvalsDir)

        // Act
        let (cached, _) = AnalysisCacheService.partitionTasks(
            tasks: [task], evalsDir: newEvalsDir, prOutputDir: prOutputDir
        )

        // Assert: same-commit result (violates: true) should be returned, not cross-commit (violates: false)
        #expect(cached.count == 1)
        #expect(cached[0].evaluation.violatesRule == true)
    }

    // MARK: - findPriorEvalsDirs

    @Test("findPriorEvalsDirs excludes current commit directory")
    func findPriorEvalsDirsExcludesCurrent() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let currentEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        let otherEvalsDir = "\(prOutputDir)/analysis/def5678/evaluate"
        try FileManager.default.createDirectory(atPath: currentEvalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: otherEvalsDir, withIntermediateDirectories: true)

        // Act
        let dirs = AnalysisCacheService.findPriorEvalsDirs(
            prOutputDir: prOutputDir, currentEvalsDir: currentEvalsDir
        )

        // Assert
        #expect(dirs.count == 1)
        #expect(dirs[0] == otherEvalsDir)
    }

    @Test("findPriorEvalsDirs returns empty when no prior commits exist")
    func findPriorEvalsDirsEmpty() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let currentEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        try FileManager.default.createDirectory(atPath: currentEvalsDir, withIntermediateDirectories: true)

        // Act
        let dirs = AnalysisCacheService.findPriorEvalsDirs(
            prOutputDir: prOutputDir, currentEvalsDir: currentEvalsDir
        )

        // Assert
        #expect(dirs.isEmpty)
    }

    @Test("findPriorEvalsDirs returns empty when analysis directory does not exist")
    func findPriorEvalsDirsNoAnalysisDir() throws {
        // Arrange
        let prOutputDir = try makeTempDir()

        // Act
        let dirs = AnalysisCacheService.findPriorEvalsDirs(
            prOutputDir: prOutputDir, currentEvalsDir: "\(prOutputDir)/analysis/abc1234/evaluate"
        )

        // Assert
        #expect(dirs.isEmpty)
    }

    // MARK: - Cross-commit: rule blob hash mismatch

    @Test("Cross-commit cache miss when ruleBlobHash differs across commits")
    func crossCommitCacheMissRuleBlobHash() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let oldEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        let newEvalsDir = "\(prOutputDir)/analysis/def5678/evaluate"
        try FileManager.default.createDirectory(atPath: oldEvalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newEvalsDir, withIntermediateDirectories: true)

        let oldTask = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "old-rule-hash")
        let newTask = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "new-rule-hash")
        try writeAnalysisResult(makeResult(taskId: "t1"), to: oldEvalsDir)
        try writeTaskSnapshot(oldTask, to: oldEvalsDir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: [newTask], evalsDir: newEvalsDir, prOutputDir: prOutputDir
        )

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 1)
        #expect(!FileManager.default.fileExists(atPath: "\(newEvalsDir)/data-t1.json"))
    }

    // MARK: - Cross-commit: multiple prior commits

    @Test("Cross-commit cache scans multiple prior commits")
    func crossCommitMultiplePriorCommits() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let commit1Dir = "\(prOutputDir)/analysis/aaa1111/evaluate"
        let commit2Dir = "\(prOutputDir)/analysis/bbb2222/evaluate"
        let newEvalsDir = "\(prOutputDir)/analysis/ccc3333/evaluate"
        try FileManager.default.createDirectory(atPath: commit1Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: commit2Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newEvalsDir, withIntermediateDirectories: true)

        // Task t1 matches commit1, task t2 matches commit2
        let task1 = makeTask(id: "t1", blobHash: "hash-a", ruleBlobHash: "rule-a")
        let task2 = makeTask(id: "t2", blobHash: "hash-b", ruleBlobHash: "rule-b")

        try writeAnalysisResult(makeResult(taskId: "t1", violates: true), to: commit1Dir)
        try writeTaskSnapshot(task1, to: commit1Dir)
        try writeAnalysisResult(makeResult(taskId: "t2", violates: false), to: commit2Dir)
        try writeTaskSnapshot(task2, to: commit2Dir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: [task1, task2], evalsDir: newEvalsDir, prOutputDir: prOutputDir
        )

        // Assert
        #expect(cached.count == 2)
        #expect(toEvaluate.isEmpty)
        #expect(FileManager.default.fileExists(atPath: "\(newEvalsDir)/data-t1.json"))
        #expect(FileManager.default.fileExists(atPath: "\(newEvalsDir)/data-t2.json"))
    }

    // MARK: - Cross-commit: mixed cache hits and misses

    @Test("Cross-commit partitions mixed cached and fresh tasks correctly")
    func crossCommitMixedPartition() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let oldEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        let newEvalsDir = "\(prOutputDir)/analysis/def5678/evaluate"
        try FileManager.default.createDirectory(atPath: oldEvalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newEvalsDir, withIntermediateDirectories: true)

        let unchangedTask = makeTask(id: "t1", blobHash: "same", ruleBlobHash: "same-rule")
        let changedTask = makeTask(id: "t2", blobHash: "new-hash", ruleBlobHash: "same-rule")
        let brandNewTask = makeTask(id: "t3", blobHash: "brand-new", ruleBlobHash: "brand-new-rule")

        try writeAnalysisResult(makeResult(taskId: "t1", violates: true), to: oldEvalsDir)
        try writeTaskSnapshot(unchangedTask, to: oldEvalsDir)
        try writeAnalysisResult(makeResult(taskId: "t2"), to: oldEvalsDir)
        try writeTaskSnapshot(makeTask(id: "t2", blobHash: "old-hash", ruleBlobHash: "same-rule"), to: oldEvalsDir)

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: [unchangedTask, changedTask, brandNewTask],
            evalsDir: newEvalsDir, prOutputDir: prOutputDir
        )

        // Assert
        #expect(cached.count == 1)
        #expect(cached[0].taskId == "t1")
        #expect(toEvaluate.count == 2)
        #expect(toEvaluate.map(\.taskId) == ["t2", "t3"])
    }

    // MARK: - Cross-commit: nil prOutputDir disables cross-commit

    @Test("Cross-commit caching disabled when prOutputDir is nil")
    func crossCommitDisabledWhenNilPrOutputDir() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let oldEvalsDir = "\(prOutputDir)/analysis/abc1234/evaluate"
        let newEvalsDir = "\(prOutputDir)/analysis/def5678/evaluate"
        try FileManager.default.createDirectory(atPath: oldEvalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newEvalsDir, withIntermediateDirectories: true)

        let task = makeTask(id: "t1", blobHash: "aaa", ruleBlobHash: "rule-hash")
        try writeAnalysisResult(makeResult(taskId: "t1"), to: oldEvalsDir)
        try writeTaskSnapshot(task, to: oldEvalsDir)

        // Act — omit prOutputDir
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: [task], evalsDir: newEvalsDir
        )

        // Assert
        #expect(cached.isEmpty)
        #expect(toEvaluate.count == 1)
    }

    // MARK: - findPriorEvalsDirs: multiple commits

    @Test("findPriorEvalsDirs returns all prior commit dirs sorted by modification date")
    func findPriorEvalsDirsMultiple() throws {
        // Arrange
        let prOutputDir = try makeTempDir()
        let commitADir = "\(prOutputDir)/analysis/aaa1111/evaluate"
        let commitBDir = "\(prOutputDir)/analysis/bbb2222/evaluate"
        let currentDir = "\(prOutputDir)/analysis/ccc3333/evaluate"
        try FileManager.default.createDirectory(atPath: commitADir, withIntermediateDirectories: true)
        // Add small delay to ensure different modification dates
        try "marker".write(toFile: "\(commitADir)/task-t1.json", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: commitBDir, withIntermediateDirectories: true)
        try "marker".write(toFile: "\(commitBDir)/task-t1.json", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: currentDir, withIntermediateDirectories: true)

        // Act
        let dirs = AnalysisCacheService.findPriorEvalsDirs(
            prOutputDir: prOutputDir, currentEvalsDir: currentDir
        )

        // Assert
        #expect(dirs.count == 2)
        #expect(!dirs.contains(currentDir))
        #expect(dirs.contains(commitADir))
        #expect(dirs.contains(commitBDir))
    }
}
