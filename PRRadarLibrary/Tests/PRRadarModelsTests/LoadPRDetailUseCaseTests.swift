import Foundation
import Testing
@testable import PRRadarCLIService
@testable import PRRadarConfigService
@testable import PRRadarModels
@testable import PRReviewFeature

@Suite("LoadPRDetailUseCase")
struct LoadPRDetailUseCaseTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Helpers

    private func makeTempDir() throws -> String {
        let path = NSTemporaryDirectory() + "load-pr-detail-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func makeConfig(outputDir: String) -> RepositoryConfiguration {
        RepositoryConfiguration(name: "test", repoPath: "/tmp/fake-repo", outputDir: outputDir, rulesDir: "/tmp/rules", agentScriptPath: "/tmp/agent.py", githubAccount: "test")
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let data = try encoder.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Set up a minimal fully-analyzed PR output directory structure.
    private func setupFullPR(outputDir: String, prNumber: String, commitHash: String) throws {
        let metadataDir = "\(outputDir)/\(prNumber)/metadata"
        let diffDir = "\(outputDir)/\(prNumber)/analysis/\(commitHash)/diff"
        let prepareDir = "\(outputDir)/\(prNumber)/analysis/\(commitHash)/prepare"
        let prepareFocusDir = "\(prepareDir)/focus-areas"
        let prepareRulesDir = "\(prepareDir)/rules"
        let prepareTasksDir = "\(prepareDir)/tasks"
        let evaluateDir = "\(outputDir)/\(prNumber)/analysis/\(commitHash)/evaluate"
        let reportDir = "\(outputDir)/\(prNumber)/analysis/\(commitHash)/report"

        for dir in [metadataDir, diffDir, prepareFocusDir, prepareRulesDir, prepareTasksDir, evaluateDir, reportDir] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // Phase results
        try PhaseResultWriter.writeSuccess(phase: .metadata, outputDir: outputDir, prNumber: prNumber, stats: PhaseStats(artifactsProduced: 3))
        try PhaseResultWriter.writeSuccess(phase: .diff, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash, stats: PhaseStats(artifactsProduced: 5))
        try PhaseResultWriter.writeSuccess(phase: .prepare, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash, stats: PhaseStats(artifactsProduced: 10))
        try PhaseResultWriter.writeSuccess(phase: .analyze, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash, stats: PhaseStats(artifactsProduced: 2))
        try PhaseResultWriter.writeSuccess(phase: .report, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash, stats: PhaseStats(artifactsProduced: 2))

        // Diff files
        let diff = GitDiff(rawContent: "diff content", hunks: [], commitHash: commitHash)
        try writeJSON(diff, to: "\(diffDir)/\(DataPathsService.diffParsedJSONFilename)")
        try writeJSON(diff, to: "\(diffDir)/\(DataPathsService.effectiveDiffParsedJSONFilename)")

        // Prepare: focus areas
        let focusArea = FocusArea(focusId: "f1", filePath: "file.swift", startLine: 1, endLine: 10, description: "test focus", hunkIndex: 0, hunkContent: "@@ content")
        let focusOutput = FocusAreaTypeOutput(prNumber: 1, generatedAt: "2026-01-01", focusType: "file", focusAreas: [focusArea], totalHunksProcessed: 1, generationCostUsd: 0.01)
        try writeJSON(focusOutput, to: "\(prepareFocusDir)/data-file.json")

        // Prepare: rules
        let rule = ReviewRule(name: "test-rule", filePath: "rules/test.md", description: "A test rule", category: "test", content: "Rule content")
        try writeJSON([rule], to: "\(prepareRulesDir)/\(DataPathsService.allRulesFilename)")

        // Prepare: tasks
        let task = AnalysisTaskOutput(
            taskId: "t1",
            rule: TaskRule(name: "test-rule", description: "A test rule", category: "test", content: "Rule content"),
            focusArea: focusArea,
            gitBlobHash: "abc123",
            ruleBlobHash: "def456"
        )
        try writeJSON(task, to: "\(prepareTasksDir)/data-t1.json")

        // Evaluate: results and summary
        let evalResult = RuleEvaluationResult(
            taskId: "t1", ruleName: "test-rule", ruleFilePath: "rules/test.md",
            filePath: "file.swift",
            evaluation: RuleEvaluation(violatesRule: true, score: 7, comment: "Violation found", filePath: "file.swift", lineNumber: 5),
            modelUsed: "claude-sonnet-4-20250514", durationMs: 1000, costUsd: 0.10
        )
        try writeJSON(evalResult, to: "\(evaluateDir)/data-t1.json")

        let summary = AnalysisSummary(
            prNumber: 1, evaluatedAt: "2026-01-01T00:00:00Z",
            totalTasks: 1, violationsFound: 1, totalCostUsd: 0.10, totalDurationMs: 1000,
            results: [evalResult]
        )
        try writeJSON(summary, to: "\(evaluateDir)/\(DataPathsService.summaryJSONFilename)")

        // Report: summary.json and summary.md
        let reportSummary = ReportSummary(
            totalTasksEvaluated: 1, violationsFound: 1, highestSeverity: 7,
            totalCostUsd: 0.10, bySeverity: ["Moderate (5-7)": 1], byFile: ["file.swift": 1], byRule: ["test-rule": 1]
        )
        let report = ReviewReport(
            prNumber: 1, generatedAt: "2026-01-01T00:00:00Z",
            minScoreThreshold: 5, summary: reportSummary,
            violations: [ViolationRecord(ruleName: "test-rule", score: 7, filePath: "file.swift", lineNumber: 5, comment: "Violation found")]
        )
        try writeJSON(report, to: "\(reportDir)/\(DataPathsService.summaryJSONFilename)")
        try "# Report\n".write(toFile: "\(reportDir)/\(DataPathsService.summaryMarkdownFilename)", atomically: true, encoding: .utf8)

        // Metadata: gh-comments.json
        let comments = GitHubPullRequestComments(comments: [], reviews: [], reviewComments: [])
        try writeJSON(comments, to: "\(metadataDir)/\(DataPathsService.ghCommentsFilename)")

        // Metadata: image-url-map.json
        try writeJSON(["img1.png": "https://example.com/img1.png"], to: "\(metadataDir)/\(DataPathsService.imageURLMapFilename)")

        // Metadata: gh-pr.json (for commit hash resolution)
        let pr = GitHubPullRequest(number: 1, title: "Test PR", headRefOid: "\(commitHash)0000000000000000000000000000000000000")
        try writeJSON(pr, to: "\(metadataDir)/\(DataPathsService.ghPRFilename)")
    }

    // MARK: - Full PR with all fields populated

    @Test("Returns correct PRDetail with all fields populated from a fully-analyzed PR")
    func fullPR() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "abc1234"
        try setupFullPR(outputDir: outputDir, prNumber: "1", commitHash: commitHash)
        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: commitHash)

        // Assert
        #expect(detail.commitHash == commitHash)
        #expect(detail.syncSnapshot != nil)
        #expect(detail.syncSnapshot?.fullDiff != nil)
        #expect(detail.syncSnapshot?.effectiveDiff != nil)
        #expect(detail.preparation != nil)
        #expect(detail.preparation?.focusAreas.count == 1)
        #expect(detail.preparation?.rules.count == 1)
        #expect(detail.preparation?.tasks.count == 1)
        #expect(detail.analysis != nil)
        #expect(detail.analysis?.evaluations.count == 1)
        #expect(detail.analysis?.summary.violationsFound == 1)
        #expect(detail.report != nil)
        #expect(detail.report?.report.violations.count == 1)
        #expect(detail.report?.markdownContent.contains("Report") == true)
        #expect(detail.postedComments != nil)
        #expect(detail.imageURLMap["img1.png"] == "https://example.com/img1.png")
        #expect(detail.imageBaseDir != nil)
        #expect(detail.imageBaseDir?.hasSuffix("/metadata/images") == true)
        #expect(detail.analysisSummary != nil)
        #expect(detail.analysisSummary?.violationsFound == 1)
        #expect(detail.analysisSummary?.totalTasks == 1)
        #expect(detail.availableCommits.contains(commitHash))
    }

    // MARK: - Missing phases return nil/empty gracefully

    @Test("Returns nil/empty fields gracefully for missing phases")
    func emptyOutputDir() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.commitHash == "abc1234")
        #expect(detail.syncSnapshot == nil)
        #expect(detail.preparation == nil)
        #expect(detail.analysis == nil)
        #expect(detail.report == nil)
        #expect(detail.postedComments == nil)
        #expect(detail.imageURLMap.isEmpty)
        #expect(detail.imageBaseDir == nil)
        #expect(detail.savedTranscripts.isEmpty)
        #expect(detail.analysisSummary == nil)
        #expect(detail.availableCommits.isEmpty)
    }

    @Test("Returns partial data when only some phases are complete")
    func partialPhases() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "abc1234"
        let diffDir = "\(outputDir)/1/analysis/\(commitHash)/diff"
        try FileManager.default.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
        let diff = GitDiff(rawContent: "diff content", hunks: [], commitHash: commitHash)
        try writeJSON(diff, to: "\(diffDir)/\(DataPathsService.diffParsedJSONFilename)")
        try PhaseResultWriter.writeSuccess(phase: .diff, outputDir: outputDir, prNumber: "1", commitHash: commitHash, stats: PhaseStats(artifactsProduced: 1))

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: commitHash)

        // Assert
        #expect(detail.syncSnapshot != nil)
        #expect(detail.syncSnapshot?.fullDiff != nil)
        #expect(detail.preparation == nil)
        #expect(detail.analysis == nil)
        #expect(detail.report == nil)
    }

    // MARK: - Commit hash resolution

    @Test("Resolves commit hash from gh-pr.json when not explicitly provided")
    func resolveCommitHashFromMetadata() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let fullHash = "abc1234567890abcdef1234567890abcdef123456"
        let expectedShortHash = "abc1234"

        let metadataDir = "\(outputDir)/1/metadata"
        try FileManager.default.createDirectory(atPath: metadataDir, withIntermediateDirectories: true)
        let pr = GitHubPullRequest(number: 1, title: "Test PR", headRefOid: fullHash)
        try writeJSON(pr, to: "\(metadataDir)/\(DataPathsService.ghPRFilename)")

        // Write diff at the expected short hash so syncSnapshot is non-nil
        let diffDir = "\(outputDir)/1/analysis/\(expectedShortHash)/diff"
        try FileManager.default.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
        let diff = GitDiff(rawContent: "diff", hunks: [], commitHash: expectedShortHash)
        try writeJSON(diff, to: "\(diffDir)/\(DataPathsService.diffParsedJSONFilename)")

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1")

        // Assert
        #expect(detail.commitHash == expectedShortHash)
        #expect(detail.syncSnapshot != nil)
    }

    @Test("Falls back to scanning analysis/ directories when gh-pr.json missing")
    func resolveCommitHashFallback() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "def5678"

        // No metadata/gh-pr.json — create analysis directory directly
        let diffDir = "\(outputDir)/1/analysis/\(commitHash)/diff"
        try FileManager.default.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
        let diff = GitDiff(rawContent: "diff", hunks: [], commitHash: commitHash)
        try writeJSON(diff, to: "\(diffDir)/\(DataPathsService.diffParsedJSONFilename)")

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1")

        // Assert
        #expect(detail.commitHash == commitHash)
        #expect(detail.syncSnapshot != nil)
    }

    @Test("Returns nil commitHash when no metadata and no analysis directories exist")
    func resolveCommitHashNil() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1")

        // Assert
        #expect(detail.commitHash == nil)
    }

    // MARK: - Transcripts

    @Test("Loads transcripts from correct phase subdirectories")
    func loadTranscripts() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "abc1234"

        let prepareFocusDir = "\(outputDir)/1/analysis/\(commitHash)/prepare/focus-areas"
        let analyzeDir = "\(outputDir)/1/analysis/\(commitHash)/evaluate"
        try FileManager.default.createDirectory(atPath: prepareFocusDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: analyzeDir, withIntermediateDirectories: true)

        let transcriptEncoder = JSONEncoder()
        transcriptEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        transcriptEncoder.dateEncodingStrategy = .iso8601

        let prepareTranscript = ClaudeAgentTranscript(
            identifier: "prep-1", model: "claude-haiku-4-5-20251001",
            startedAt: "2026-01-01T00:00:00Z", prompt: "Prepare prompt",
            events: [], costUsd: 0.01, durationMs: 500
        )
        let analyzeTranscript = ClaudeAgentTranscript(
            identifier: "analyze-1", model: "claude-sonnet-4-20250514",
            startedAt: "2026-01-01T00:01:00Z", prompt: "Analyze prompt",
            events: [], costUsd: 0.05, durationMs: 2000
        )

        let prepData = try transcriptEncoder.encode(prepareTranscript)
        try prepData.write(to: URL(fileURLWithPath: "\(prepareFocusDir)/ai-transcript-prep-1.json"))

        let analyzeData = try transcriptEncoder.encode(analyzeTranscript)
        try analyzeData.write(to: URL(fileURLWithPath: "\(analyzeDir)/ai-transcript-analyze-1.json"))

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: commitHash)

        // Assert
        #expect(detail.savedTranscripts[.prepare]?.count == 1)
        #expect(detail.savedTranscripts[.prepare]?.first?.identifier == "prep-1")
        #expect(detail.savedTranscripts[.analyze]?.count == 1)
        #expect(detail.savedTranscripts[.analyze]?.first?.identifier == "analyze-1")
    }

    @Test("Ignores non-transcript files in phase directories")
    func transcriptsIgnoresNonTranscriptFiles() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "abc1234"
        let analyzeDir = "\(outputDir)/1/analysis/\(commitHash)/evaluate"
        try FileManager.default.createDirectory(atPath: analyzeDir, withIntermediateDirectories: true)

        // Write a non-transcript file
        try "{}".write(toFile: "\(analyzeDir)/data-t1.json", atomically: true, encoding: .utf8)
        try "{}".write(toFile: "\(analyzeDir)/phase_result.json", atomically: true, encoding: .utf8)

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: commitHash)

        // Assert
        #expect(detail.savedTranscripts[.analyze] == nil)
    }

    // MARK: - Posted comments and image map from metadata/

    @Test("Loads posted comments from metadata directory")
    func loadPostedComments() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let metadataDir = "\(outputDir)/1/metadata"
        try FileManager.default.createDirectory(atPath: metadataDir, withIntermediateDirectories: true)

        let comments = GitHubPullRequestComments(comments: [], reviews: [], reviewComments: [])
        try writeJSON(comments, to: "\(metadataDir)/\(DataPathsService.ghCommentsFilename)")

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.postedComments != nil)
        #expect(detail.postedComments?.comments.isEmpty == true)
    }

    @Test("Loads image URL map and computes imageBaseDir from metadata directory")
    func loadImageMap() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let metadataDir = "\(outputDir)/1/metadata"
        try FileManager.default.createDirectory(atPath: metadataDir, withIntermediateDirectories: true)

        let map = ["screenshot.png": "https://example.com/screenshot.png"]
        try writeJSON(map, to: "\(metadataDir)/\(DataPathsService.imageURLMapFilename)")

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.imageURLMap["screenshot.png"] == "https://example.com/screenshot.png")
        #expect(detail.imageBaseDir == "\(metadataDir)/images")
    }

    @Test("Returns empty image map when image-url-map.json is missing")
    func missingImageMap() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.imageURLMap.isEmpty)
        #expect(detail.imageBaseDir == nil)
    }

    // MARK: - Available commits scanning

    @Test("Scans available commits from analysis/ directory")
    func availableCommits() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let analysisRoot = "\(outputDir)/1/analysis"
        for hash in ["abc1234", "def5678", "ghi9012"] {
            try FileManager.default.createDirectory(
                atPath: "\(analysisRoot)/\(hash)", withIntermediateDirectories: true
            )
        }

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.availableCommits.count == 3)
        #expect(detail.availableCommits.contains("abc1234"))
        #expect(detail.availableCommits.contains("def5678"))
        #expect(detail.availableCommits.contains("ghi9012"))
    }

    @Test("Returns empty available commits when analysis/ directory does not exist")
    func availableCommitsEmpty() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.availableCommits.isEmpty)
    }

    @Test("Available commits excludes hidden directories")
    func availableCommitsExcludesHidden() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let analysisRoot = "\(outputDir)/1/analysis"
        try FileManager.default.createDirectory(atPath: "\(analysisRoot)/abc1234", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(analysisRoot)/.DS_Store", withIntermediateDirectories: true)

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.availableCommits == ["abc1234"])
    }

    // MARK: - Analysis summary

    @Test("Returns analysis summary from evaluate/summary.json")
    func analysisSummary() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "abc1234"
        let evaluateDir = "\(outputDir)/1/analysis/\(commitHash)/evaluate"
        try FileManager.default.createDirectory(atPath: evaluateDir, withIntermediateDirectories: true)

        let summary = AnalysisSummary(
            prNumber: 1, evaluatedAt: "2026-01-01T00:00:00Z",
            totalTasks: 3, violationsFound: 2, totalCostUsd: 0.30, totalDurationMs: 3000,
            results: []
        )
        try writeJSON(summary, to: "\(evaluateDir)/\(DataPathsService.summaryJSONFilename)")

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: commitHash)

        // Assert
        let loaded = try #require(detail.analysisSummary)
        #expect(loaded.prNumber == 1)
        #expect(loaded.totalTasks == 3)
        #expect(loaded.violationsFound == 2)
        #expect(loaded.totalCostUsd == 0.30)
    }

    @Test("Returns nil analysis summary when summary.json is missing")
    func analysisSummaryMissing() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "abc1234")

        // Assert
        #expect(detail.analysisSummary == nil)
    }

    // MARK: - Phase statuses

    @Test("Phase statuses reflect actual phase completion state")
    func phaseStatuses() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "abc1234"
        try PhaseResultWriter.writeSuccess(phase: .metadata, outputDir: outputDir, prNumber: "1", stats: PhaseStats(artifactsProduced: 3))
        try PhaseResultWriter.writeSuccess(phase: .diff, outputDir: outputDir, prNumber: "1", commitHash: commitHash, stats: PhaseStats(artifactsProduced: 5))
        try PhaseResultWriter.writeFailure(phase: .prepare, outputDir: outputDir, prNumber: "1", commitHash: commitHash, error: "timeout")

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: commitHash)

        // Assert
        #expect(detail.phaseStatuses[.metadata]?.isComplete == true)
        #expect(detail.phaseStatuses[.diff]?.isComplete == true)
        #expect(detail.phaseStatuses[.prepare]?.isComplete == false)
        #expect(detail.phaseStatuses[.prepare]?.exists == true)
        #expect(detail.phaseStatuses[.analyze]?.exists == false)
        #expect(detail.phaseStatuses[.report]?.exists == false)
    }

    // MARK: - SyncSnapshot nil when no diffs present

    @Test("Returns nil syncSnapshot when no diff files exist")
    func syncSnapshotNilWhenNoDiffs() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitHash = "abc1234"
        let diffDir = "\(outputDir)/1/analysis/\(commitHash)/diff"
        try FileManager.default.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
        // Write a non-diff file so the directory isn't empty
        try "marker".write(toFile: "\(diffDir)/phase_result.json", atomically: true, encoding: .utf8)

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: commitHash)

        // Assert
        #expect(detail.syncSnapshot == nil)
    }

    // MARK: - Available commits sorted

    @Test("Available commits are returned in sorted order")
    func availableCommitsSorted() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let analysisRoot = "\(outputDir)/1/analysis"
        for hash in ["zzz9999", "aaa1111", "mmm5555"] {
            try FileManager.default.createDirectory(atPath: "\(analysisRoot)/\(hash)", withIntermediateDirectories: true)
        }

        let config = makeConfig(outputDir: outputDir)
        let useCase = LoadPRDetailUseCase(config: config)

        // Act
        let detail = useCase.execute(prNumber: "1", commitHash: "aaa1111")

        // Assert
        #expect(detail.availableCommits == ["aaa1111", "mmm5555", "zzz9999"])
    }
}
