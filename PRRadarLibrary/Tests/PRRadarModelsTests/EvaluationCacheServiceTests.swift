import Foundation
import Testing
@testable import PRRadarCLIService
@testable import PRRadarModels

@Suite("EvaluationCacheService")
struct EvaluationCacheServiceTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Helpers

    private func makeTempDir() throws -> String {
        let path = NSTemporaryDirectory() + "eval-cache-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func makeTask(id: String, blobHash: String) -> EvaluationTaskOutput {
        EvaluationTaskOutput(
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
            gitBlobHash: blobHash
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

    private func writeEvalResult(_ result: RuleEvaluationResult, to dir: String) throws {
        let data = try encoder.encode(result)
        let path = "\(dir)/data-\(result.taskId).json"
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func writeTaskSnapshot(_ task: EvaluationTaskOutput, to dir: String) throws {
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
        let (cached, toEvaluate) = EvaluationCacheService.partitionTasks(tasks: tasks, evalsDir: dir)

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
        try writeEvalResult(result, to: dir)
        try writeTaskSnapshot(task, to: dir)

        // Act
        let (cached, toEvaluate) = EvaluationCacheService.partitionTasks(tasks: [task], evalsDir: dir)

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
        try writeEvalResult(result, to: dir)
        try writeTaskSnapshot(oldTask, to: dir)

        // Act
        let (cached, toEvaluate) = EvaluationCacheService.partitionTasks(tasks: [newTask], evalsDir: dir)

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
        try writeEvalResult(makeResult(taskId: "t1", violates: true), to: dir)
        try writeTaskSnapshot(unchangedTask, to: dir)
        try writeEvalResult(makeResult(taskId: "t2"), to: dir)
        try writeTaskSnapshot(makeTask(id: "t2", blobHash: "old-hash"), to: dir)

        // Act
        let (cached, toEvaluate) = EvaluationCacheService.partitionTasks(
            tasks: [unchangedTask, changedTask, newTask], evalsDir: dir
        )

        // Assert
        #expect(cached.count == 1)
        #expect(cached[0].taskId == "t1")
        #expect(toEvaluate.count == 2)
        #expect(toEvaluate.map(\.taskId) == ["t2", "t3"])
    }

    // MARK: - partitionTasks: eval exists but no task snapshot

    @Test("Task re-evaluated when eval exists but task snapshot is missing")
    func evalExistsButNoTaskSnapshot() throws {
        // Arrange
        let dir = try makeTempDir()
        let task = makeTask(id: "t1", blobHash: "aaa")
        try writeEvalResult(makeResult(taskId: "t1"), to: dir)

        // Act
        let (cached, toEvaluate) = EvaluationCacheService.partitionTasks(tasks: [task], evalsDir: dir)

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
        try EvaluationCacheService.writeTaskSnapshots(tasks: tasks, evalsDir: dir)

        // Assert
        let decoder = JSONDecoder()
        for task in tasks {
            let path = "\(dir)/task-\(task.taskId).json"
            let data = try #require(FileManager.default.contents(atPath: path))
            let decoded = try decoder.decode(EvaluationTaskOutput.self, from: data)
            #expect(decoded == task)
        }
    }

    // MARK: - Round-trip: write snapshots then partition

    @Test("Tasks cached after writeTaskSnapshots + partitionTasks round-trip")
    func roundTrip() throws {
        // Arrange
        let dir = try makeTempDir()
        let tasks = [makeTask(id: "t1", blobHash: "hash1"), makeTask(id: "t2", blobHash: "hash2")]
        let results = [makeResult(taskId: "t1", violates: true), makeResult(taskId: "t2")]

        try EvaluationCacheService.writeTaskSnapshots(tasks: tasks, evalsDir: dir)
        for result in results {
            try writeEvalResult(result, to: dir)
        }

        // Act
        let (cached, toEvaluate) = EvaluationCacheService.partitionTasks(tasks: tasks, evalsDir: dir)

        // Assert
        #expect(cached.count == 2)
        #expect(toEvaluate.isEmpty)
        #expect(cached[0].taskId == "t1")
        #expect(cached[1].taskId == "t2")
    }
}
