import Foundation
import Testing
@testable import PRRadarConfigService

@Suite("Phase Behavior")
struct PhaseBehaviorTests {

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
            prNumber: "42",
            phase: .metadata
        )
        #expect(dir == "/output/42/metadata")
    }

    @Test("phaseDirectory builds correct path for commit-scoped phases")
    func phaseDirectoryCommitScoped() {
        let dir = DataPathsService.phaseDirectory(
            outputDir: "/output",
            prNumber: "42",
            phase: .diff,
            commitHash: "abc1234"
        )
        #expect(dir == "/output/42/analysis/abc1234/diff")
    }

    @Test("metadataDirectory builds correct path")
    func metadataDirectory() {
        let dir = DataPathsService.metadataDirectory(
            outputDir: "/output",
            prNumber: "42"
        )
        #expect(dir == "/output/42/metadata")
    }

    @Test("analysisDirectory builds correct path")
    func analysisDirectory() {
        let dir = DataPathsService.analysisDirectory(
            outputDir: "/output",
            prNumber: "42",
            commitHash: "abc1234"
        )
        #expect(dir == "/output/42/analysis/abc1234")
    }

    @Test("commit-scoped phase subdirectories build correct paths")
    func commitScopedSubdirectories() {
        let prepareDir = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: "42", phase: .prepare, commitHash: "abc1234"
        )
        #expect(prepareDir == "/output/42/analysis/abc1234/prepare")

        let analyzeDir = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: "42", phase: .analyze, commitHash: "abc1234"
        )
        #expect(analyzeDir == "/output/42/analysis/abc1234/evaluate")

        let reportDir = DataPathsService.phaseDirectory(
            outputDir: "/output", prNumber: "42", phase: .report, commitHash: "abc1234"
        )
        #expect(reportDir == "/output/42/analysis/abc1234/report")
    }

    @Test("canRunPhase returns true for first phase")
    func canRunFirstPhase() {
        let canRun = DataPathsService.canRunPhase(
            .metadata,
            outputDir: "/nonexistent",
            prNumber: "1"
        )
        #expect(canRun)
    }

    @Test("canRunPhase returns true for diff (no predecessor)")
    func canRunDiffPhase() {
        let canRun = DataPathsService.canRunPhase(
            .diff,
            outputDir: "/nonexistent",
            prNumber: "1"
        )
        #expect(canRun)
    }

    @Test("validateCanRun returns error for phase with missing predecessor")
    func validateCanRunError() {
        let error = DataPathsService.validateCanRun(
            .prepare,
            outputDir: "/nonexistent",
            prNumber: "1"
        )
        #expect(error != nil)
        #expect(error!.contains("diff"))
    }

    @Test("phaseDirectory uses legacy flat path when commitHash is nil")
    func phaseDirectoryLegacyFallback() {
        let dir = DataPathsService.phaseDirectory(
            outputDir: "/output",
            prNumber: "42",
            phase: .diff
        )
        #expect(dir == "/output/42/diff")
    }

    @Test("phaseSubdirectory builds correct path with commit hash")
    func phaseSubdirectory() {
        let dir = DataPathsService.phaseSubdirectory(
            outputDir: "/output",
            prNumber: "42",
            phase: .prepare,
            subdirectory: DataPathsService.prepareFocusAreasSubdir,
            commitHash: "abc1234"
        )
        #expect(dir == "/output/42/analysis/abc1234/prepare/focus-areas")
    }
}
