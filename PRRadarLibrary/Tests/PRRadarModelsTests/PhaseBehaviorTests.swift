import Foundation
import PRRadarModels
import Testing
@testable import PRRadarConfigService
@testable import PRRadarCLIService

@Suite("Phase Behavior")
struct PhaseBehaviorTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> String {
        let path = NSTemporaryDirectory() + "phase-behavior-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    // MARK: - PRRadarPhase

    @Test("phaseNumber returns correct numbers for all phases")
    func phaseNumbers() {
        #expect(PRRadarPhase.metadata.phaseNumber == 1)
        #expect(PRRadarPhase.diff.phaseNumber == 2)
        #expect(PRRadarPhase.prepare.phaseNumber == 3)
        #expect(PRRadarPhase.analyze.phaseNumber == 4)
        #expect(PRRadarPhase.report.phaseNumber == 5)
    }

    @Test("requiredPredecessor returns correct predecessor")
    func requiredPredecessor() {
        #expect(PRRadarPhase.metadata.requiredPredecessor == nil)
        #expect(PRRadarPhase.diff.requiredPredecessor == nil)
        #expect(PRRadarPhase.prepare.requiredPredecessor == .diff)
        #expect(PRRadarPhase.analyze.requiredPredecessor == .prepare)
        #expect(PRRadarPhase.report.requiredPredecessor == .analyze)
    }

    @Test("displayName returns human-readable names")
    func displayNames() {
        #expect(PRRadarPhase.metadata.displayName == "Metadata")
        #expect(PRRadarPhase.diff.displayName == "Diff")
        #expect(PRRadarPhase.prepare.displayName == "Prepare")
        #expect(PRRadarPhase.analyze.displayName == "Analyze")
        #expect(PRRadarPhase.report.displayName == "Report")
    }

    @Test("isCommitScoped returns correct scope")
    func isCommitScoped() {
        #expect(!PRRadarPhase.metadata.isCommitScoped)
        #expect(PRRadarPhase.diff.isCommitScoped)
        #expect(PRRadarPhase.prepare.isCommitScoped)
        #expect(PRRadarPhase.analyze.isCommitScoped)
        #expect(PRRadarPhase.report.isCommitScoped)
    }

    // MARK: - PhaseStatus

    @Test("PhaseStatus summary reflects state correctly")
    func phaseStatusSummary() {
        let notStarted = PhaseStatus(
            phase: .metadata, exists: false, isComplete: false,
            completedCount: 0, totalCount: 5, missingItems: []
        )
        #expect(notStarted.summary == "not started")

        let complete = PhaseStatus(
            phase: .metadata, exists: true, isComplete: true,
            completedCount: 5, totalCount: 5, missingItems: []
        )
        #expect(complete.summary == "complete")

        let partial = PhaseStatus(
            phase: .analyze, exists: true, isComplete: false,
            completedCount: 3, totalCount: 5, missingItems: ["task-4", "task-5"]
        )
        #expect(partial.summary == "partial (3/5)")
        #expect(partial.isPartial)

        let incomplete = PhaseStatus(
            phase: .prepare, exists: true, isComplete: false,
            completedCount: 0, totalCount: 1, missingItems: ["all-rules.json"]
        )
        #expect(incomplete.summary == "incomplete")
        #expect(!incomplete.isPartial)
    }

    @Test("PhaseStatus completionPercentage calculates correctly")
    func completionPercentage() {
        let half = PhaseStatus(
            phase: .analyze, exists: true, isComplete: false,
            completedCount: 5, totalCount: 10, missingItems: []
        )
        #expect(half.completionPercentage == 50.0)

        let empty = PhaseStatus(
            phase: .prepare, exists: false, isComplete: false,
            completedCount: 0, totalCount: 0, missingItems: []
        )
        #expect(empty.completionPercentage == 0.0)

        let emptyComplete = PhaseStatus(
            phase: .prepare, exists: true, isComplete: true,
            completedCount: 0, totalCount: 0, missingItems: []
        )
        #expect(emptyComplete.completionPercentage == 100.0)
    }

    // MARK: - DataPathsService

    @Test("phaseDirectory builds correct path for metadata (PR-scoped)")
    func phaseDirectoryMetadata() {
        let dir = DataPathsService.phaseDirectory(
            outputDir: "/output",
            prNumber: 42,
            phase: .metadata
        )
        #expect(dir == "/output/42/metadata")
    }

    @Test("phaseDirectory builds correct path for commit-scoped phases")
    func phaseDirectoryCommitScoped() {
        let dir = DataPathsService.phaseDirectory(
            outputDir: "/output",
            prNumber: 42,
            phase: .diff,
            commitHash: "abc1234"
        )
        #expect(dir == "/output/42/analysis/abc1234/diff")
    }

    @Test("metadataDirectory builds correct path")
    func metadataDirectory() {
        let dir = DataPathsService.metadataDirectory(
            outputDir: "/output",
            prNumber: 42
        )
        #expect(dir == "/output/42/metadata")
    }

    @Test("analysisDirectory builds correct path")
    func analysisDirectory() {
        let dir = DataPathsService.analysisDirectory(
            outputDir: "/output",
            prNumber: 42,
            commitHash: "abc1234"
        )
        #expect(dir == "/output/42/analysis/abc1234")
    }

    @Test("commit-scoped phase subdirectories build correct paths")
    func commitScopedSubdirectories() {
        let prepareDir = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: 42, phase: .prepare, commitHash: "abc1234"
        )
        #expect(prepareDir == "/output/42/analysis/abc1234/prepare")

        let analyzeDir = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: 42, phase: .analyze, commitHash: "abc1234"
        )
        #expect(analyzeDir == "/output/42/analysis/abc1234/evaluate")

        let reportDir = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: 42, phase: .report, commitHash: "abc1234"
        )
        #expect(reportDir == "/output/42/analysis/abc1234/report")
    }

    @Test("canRunPhase returns true for first phase")
    func canRunFirstPhase() {
        let canRun = DataPathsService.canRunPhase(
            .metadata,
            outputDir: "/nonexistent",
            prNumber: 1
        )
        #expect(canRun)
    }

    @Test("canRunPhase returns true for diff (no predecessor)")
    func canRunDiffPhase() {
        let canRun = DataPathsService.canRunPhase(
            .diff,
            outputDir: "/nonexistent",
            prNumber: 1
        )
        #expect(canRun)
    }

    @Test("validateCanRun returns error for phase with missing predecessor")
    func validateCanRunError() {
        let error = DataPathsService.validateCanRun(
            .prepare,
            outputDir: "/nonexistent",
            prNumber: 1
        )
        #expect(error != nil)
        #expect(error!.contains("diff"))
    }

    @Test("phaseDirectory uses legacy flat path when commitHash is nil")
    func phaseDirectoryLegacyFallback() {
        let dir = DataPathsService.phaseDirectory(
            outputDir: "/output",
            prNumber: 42,
            phase: .diff
        )
        #expect(dir == "/output/42/diff")
    }

    @Test("phaseSubdirectory builds correct path with commit hash")
    func phaseSubdirectory() {
        let dir = DataPathsService.phaseSubdirectory(
            outputDir: "/output",
            prNumber: 42,
            phase: .prepare,
            subdirectory: DataPathsService.prepareFocusAreasSubdir,
            commitHash: "abc1234"
        )
        #expect(dir == "/output/42/analysis/abc1234/prepare/focus-areas")
    }

    // MARK: - phaseDirectory: metadata ignores commitHash

    @Test("phaseDirectory for metadata ignores commitHash parameter")
    func metadataIgnoresCommitHash() {
        // Act
        let withHash = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: 42, phase: .metadata, commitHash: "abc1234"
        )
        let withoutHash = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: 42, phase: .metadata
        )

        // Assert
        #expect(withHash == withoutHash)
        #expect(withHash == "/output/42/metadata")
    }

    // MARK: - phaseExists: filesystem tests

    @Test("phaseExists returns false for nonexistent directory")
    func phaseExistsNonexistent() {
        // Act
        let exists = DataPathsService.phaseExists(
            outputDir: "/nonexistent", prNumber: 1, phase: .diff, commitHash: "abc1234"
        )

        // Assert
        #expect(!exists)
    }

    @Test("phaseExists returns false for empty directory")
    func phaseExistsEmptyDir() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let diffDir = "\(outputDir)/1/analysis/abc1234/diff"
        try FileManager.default.createDirectory(atPath: diffDir, withIntermediateDirectories: true)

        // Act
        let exists = DataPathsService.phaseExists(
            outputDir: outputDir, prNumber: 1, phase: .diff, commitHash: "abc1234"
        )

        // Assert
        #expect(!exists)
    }

    @Test("phaseExists returns true for directory with files")
    func phaseExistsWithFiles() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let diffDir = "\(outputDir)/1/analysis/abc1234/diff"
        try FileManager.default.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
        try "content".write(toFile: "\(diffDir)/diff-raw.diff", atomically: true, encoding: .utf8)

        // Act
        let exists = DataPathsService.phaseExists(
            outputDir: outputDir, prNumber: 1, phase: .diff, commitHash: "abc1234"
        )

        // Assert
        #expect(exists)
    }

    @Test("phaseExists checks correct commit directory, not adjacent commits")
    func phaseExistsIsolatesBetweenCommits() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let commitADir = "\(outputDir)/1/analysis/abc1234/diff"
        let commitBDir = "\(outputDir)/1/analysis/def5678/diff"
        try FileManager.default.createDirectory(atPath: commitADir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: commitBDir, withIntermediateDirectories: true)
        try "content".write(toFile: "\(commitADir)/diff-raw.diff", atomically: true, encoding: .utf8)

        // Act
        let existsA = DataPathsService.phaseExists(
            outputDir: outputDir, prNumber: 1, phase: .diff, commitHash: "abc1234"
        )
        let existsB = DataPathsService.phaseExists(
            outputDir: outputDir, prNumber: 1, phase: .diff, commitHash: "def5678"
        )

        // Assert
        #expect(existsA)
        #expect(!existsB)
    }

    // MARK: - phaseStatus: filesystem tests

    @Test("phaseStatus returns not started when no phase_result.json exists")
    func phaseStatusNotStarted() throws {
        // Arrange
        let outputDir = try makeTempDir()

        // Act
        let status = DataPathsService.phaseStatus(
            .diff, outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )

        // Assert
        #expect(!status.exists)
        #expect(!status.isComplete)
        #expect(status.summary == "not started")
    }

    @Test("phaseStatus returns complete when phase_result.json has success")
    func phaseStatusComplete() throws {
        // Arrange
        let outputDir = try makeTempDir()
        try PhaseResultWriter.writeSuccess(
            phase: .diff, outputDir: outputDir, prNumber: 1, commitHash: "abc1234",
            stats: PhaseStats(artifactsProduced: 3)
        )

        // Act
        let status = DataPathsService.phaseStatus(
            .diff, outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )

        // Assert
        #expect(status.exists)
        #expect(status.isComplete)
        #expect(status.completedCount == 3)
        #expect(status.summary == "complete")
    }

    @Test("phaseStatus returns incomplete when phase_result.json has failure")
    func phaseStatusFailed() throws {
        // Arrange
        let outputDir = try makeTempDir()
        try PhaseResultWriter.writeFailure(
            phase: .analyze, outputDir: outputDir, prNumber: 1,
            commitHash: "abc1234", error: "API timeout"
        )

        // Act
        let status = DataPathsService.phaseStatus(
            .analyze, outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )

        // Assert
        #expect(status.exists)
        #expect(!status.isComplete)
        #expect(status.summary == "incomplete")
    }

    @Test("phaseStatus reads from metadata directory for metadata phase")
    func phaseStatusMetadata() throws {
        // Arrange
        let outputDir = try makeTempDir()
        try PhaseResultWriter.writeSuccess(
            phase: .metadata, outputDir: outputDir, prNumber: 1,
            stats: PhaseStats(artifactsProduced: 4)
        )

        // Act
        let status = DataPathsService.phaseStatus(
            .metadata, outputDir: outputDir, prNumber: 1
        )

        // Assert
        #expect(status.exists)
        #expect(status.isComplete)
        #expect(status.completedCount == 4)
    }

    // MARK: - allPhaseStatuses: commit-scoped

    @Test("allPhaseStatuses returns status for all phases with commit hash")
    func allPhaseStatusesCommitScoped() throws {
        // Arrange
        let outputDir = try makeTempDir()
        try PhaseResultWriter.writeSuccess(
            phase: .metadata, outputDir: outputDir, prNumber: 1,
            stats: PhaseStats(artifactsProduced: 3)
        )
        try PhaseResultWriter.writeSuccess(
            phase: .diff, outputDir: outputDir, prNumber: 1, commitHash: "abc1234",
            stats: PhaseStats(artifactsProduced: 5)
        )
        try PhaseResultWriter.writeSuccess(
            phase: .prepare, outputDir: outputDir, prNumber: 1, commitHash: "abc1234",
            stats: PhaseStats(artifactsProduced: 10)
        )

        // Act
        let statuses = DataPathsService.allPhaseStatuses(
            outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )

        // Assert
        #expect(statuses[.metadata]?.isComplete == true)
        #expect(statuses[.diff]?.isComplete == true)
        #expect(statuses[.prepare]?.isComplete == true)
        #expect(statuses[.analyze]?.summary == "not started")
        #expect(statuses[.report]?.summary == "not started")
    }

    @Test("allPhaseStatuses isolates between different commits")
    func allPhaseStatusesDifferentCommits() throws {
        // Arrange
        let outputDir = try makeTempDir()
        try PhaseResultWriter.writeSuccess(
            phase: .diff, outputDir: outputDir, prNumber: 1, commitHash: "abc1234",
            stats: PhaseStats(artifactsProduced: 5)
        )

        // Act
        let statusesA = DataPathsService.allPhaseStatuses(
            outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )
        let statusesB = DataPathsService.allPhaseStatuses(
            outputDir: outputDir, prNumber: 1, commitHash: "def5678"
        )

        // Assert
        #expect(statusesA[.diff]?.isComplete == true)
        #expect(statusesB[.diff]?.summary == "not started")
    }

    // MARK: - canRunPhase: commit-scoped

    @Test("canRunPhase checks predecessor in commit-scoped directory")
    func canRunPhaseCommitScoped() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let diffDir = DataPathsService.phaseDirectory(
            outputDir: outputDir, prNumber: 1, phase: .diff, commitHash: "abc1234"
        )
        try FileManager.default.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
        try "content".write(toFile: "\(diffDir)/diff-raw.diff", atomically: true, encoding: .utf8)

        // Act
        let canRunPrepare = DataPathsService.canRunPhase(
            .prepare, outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )
        let canRunAnalyze = DataPathsService.canRunPhase(
            .analyze, outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )

        // Assert
        #expect(canRunPrepare)
        #expect(!canRunAnalyze)
    }

    // MARK: - PhaseResultWriter round-trip

    @Test("PhaseResultWriter write then read round-trips correctly")
    func phaseResultWriterRoundTrip() throws {
        // Arrange
        let outputDir = try makeTempDir()
        let stats = PhaseStats(artifactsProduced: 7, durationMs: 1500, costUsd: 0.42)

        // Act
        try PhaseResultWriter.writeSuccess(
            phase: .analyze, outputDir: outputDir, prNumber: 1,
            commitHash: "abc1234", stats: stats
        )
        let result = PhaseResultWriter.read(
            phase: .analyze, outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )

        // Assert
        let readResult = try #require(result)
        #expect(readResult.phase == "evaluate")
        #expect(readResult.status == .success)
        #expect(readResult.stats?.artifactsProduced == 7)
        #expect(readResult.stats?.durationMs == 1500)
        #expect(readResult.stats?.costUsd == 0.42)
    }

    @Test("PhaseResultWriter returns nil for nonexistent phase")
    func phaseResultWriterReadMissing() throws {
        // Arrange
        let outputDir = try makeTempDir()

        // Act
        let result = PhaseResultWriter.read(
            phase: .diff, outputDir: outputDir, prNumber: 1, commitHash: "abc1234"
        )

        // Assert
        #expect(result == nil)
    }
}
