import Foundation
import Testing
@testable import PRRadarConfigService

@Suite("Phase Behavior")
struct PhaseBehaviorTests {

    // MARK: - PRRadarPhase

    @Test("phaseNumber returns correct numbers for all phases")
    func phaseNumbers() {
        #expect(PRRadarPhase.sync.phaseNumber == 1)
        #expect(PRRadarPhase.prepare.phaseNumber == 2)
        #expect(PRRadarPhase.analyze.phaseNumber == 3)
        #expect(PRRadarPhase.report.phaseNumber == 4)
    }

    @Test("requiredPredecessor returns correct predecessor")
    func requiredPredecessor() {
        #expect(PRRadarPhase.sync.requiredPredecessor == nil)
        #expect(PRRadarPhase.prepare.requiredPredecessor == .sync)
        #expect(PRRadarPhase.analyze.requiredPredecessor == .prepare)
        #expect(PRRadarPhase.report.requiredPredecessor == .analyze)
    }

    @Test("displayName returns human-readable names")
    func displayNames() {
        #expect(PRRadarPhase.sync.displayName == "Sync PR")
        #expect(PRRadarPhase.prepare.displayName == "Prepare")
        #expect(PRRadarPhase.analyze.displayName == "Analyze")
        #expect(PRRadarPhase.report.displayName == "Report")
    }

    // MARK: - PhaseStatus

    @Test("PhaseStatus summary reflects state correctly")
    func phaseStatusSummary() {
        let notStarted = PhaseStatus(
            phase: .sync, exists: false, isComplete: false,
            completedCount: 0, totalCount: 5, missingItems: []
        )
        #expect(notStarted.summary == "not started")

        let complete = PhaseStatus(
            phase: .sync, exists: true, isComplete: true,
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

    @Test("phaseDirectory builds correct path")
    func phaseDirectory() {
        let dir = DataPathsService.phaseDirectory(
            outputDir: "/output",
            prNumber: "42",
            phase: .sync
        )
        #expect(dir == "/output/42/phase-1-sync")
    }

    @Test("canRunPhase returns true for first phase")
    func canRunFirstPhase() {
        let canRun = DataPathsService.canRunPhase(
            .sync,
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
        #expect(error!.contains("phase-1-sync"))
    }

    @Test("phaseSubdirectory builds correct path")
    func phaseSubdirectory() {
        let dir = DataPathsService.phaseSubdirectory(
            outputDir: "/output",
            prNumber: "42",
            phase: .prepare,
            subdirectory: DataPathsService.prepareFocusAreasSubdir
        )
        #expect(dir == "/output/42/phase-2-prepare/focus-areas")
    }
}
