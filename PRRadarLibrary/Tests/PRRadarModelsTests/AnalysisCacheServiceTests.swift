import Foundation
import Testing
@testable import PRRadarCLIService
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
        let path = NSTemporaryDirectory() + "eval-cache-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func makeTask(id: String, blobHash: String) -> AnalysisTaskOutput {
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
        try writeEvalResult(result, to: dir)
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
        try writeEvalResult(result, to: dir)
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
        try writeEvalResult(makeResult(taskId: "t1", violates: true), to: dir)
        try writeTaskSnapshot(unchangedTask, to: dir)
        try writeEvalResult(makeResult(taskId: "t2"), to: dir)
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

    @Test("Task re-evaluated when eval exists but task snapshot is missing")
    func evalExistsButNoTaskSnapshot() throws {
        // Arrange
        let dir = try makeTempDir()
        let task = makeTask(id: "t1", blobHash: "aaa")
        try writeEvalResult(makeResult(taskId: "t1"), to: dir)

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
            try writeEvalResult(result, to: dir)
        }

        // Act
        let (cached, toEvaluate) = AnalysisCacheService.partitionTasks(tasks: tasks, evalsDir: dir)

        // Assert
        #expect(cached.count == 2)
        #expect(toEvaluate.isEmpty)
        #expect(cached[0].taskId == "t1")
        #expect(cached[1].taskId == "t2")
    }
}
