import Foundation
import Testing
@testable import PRRadarConfigService

@Suite("Phase Behavior")
struct PhaseBehaviorTests {

    // MARK: - PRRadarPhase

    @Test("phaseNumber returns correct numbers for all phases")
    func phaseNumbers() {
        #expect(PRRadarPhase.pullRequest.phaseNumber == 1)
        #expect(PRRadarPhase.focusAreas.phaseNumber == 2)
        #expect(PRRadarPhase.rules.phaseNumber == 3)
        #expect(PRRadarPhase.tasks.phaseNumber == 4)
        #expect(PRRadarPhase.evaluations.phaseNumber == 5)
        #expect(PRRadarPhase.report.phaseNumber == 6)
    }

    @Test("requiredPredecessor returns correct predecessor")
    func requiredPredecessor() {
        #expect(PRRadarPhase.pullRequest.requiredPredecessor == nil)
        #expect(PRRadarPhase.focusAreas.requiredPredecessor == .pullRequest)
        #expect(PRRadarPhase.rules.requiredPredecessor == .focusAreas)
        #expect(PRRadarPhase.tasks.requiredPredecessor == .rules)
        #expect(PRRadarPhase.evaluations.requiredPredecessor == .tasks)
        #expect(PRRadarPhase.report.requiredPredecessor == .evaluations)
    }

    @Test("displayName returns human-readable names")
    func displayNames() {
        #expect(PRRadarPhase.pullRequest.displayName == "Pull Request")
        #expect(PRRadarPhase.focusAreas.displayName == "Focus Areas")
        #expect(PRRadarPhase.rules.displayName == "Rules")
        #expect(PRRadarPhase.tasks.displayName == "Tasks")
        #expect(PRRadarPhase.evaluations.displayName == "Evaluations")
        #expect(PRRadarPhase.report.displayName == "Report")
    }

    // MARK: - PhaseStatus

    @Test("PhaseStatus summary reflects state correctly")
    func phaseStatusSummary() {
        let notStarted = PhaseStatus(
            phase: .pullRequest, exists: false, isComplete: false,
            completedCount: 0, totalCount: 5, missingItems: []
        )
        #expect(notStarted.summary == "not started")

        let complete = PhaseStatus(
            phase: .pullRequest, exists: true, isComplete: true,
            completedCount: 5, totalCount: 5, missingItems: []
        )
        #expect(complete.summary == "complete")

        let partial = PhaseStatus(
            phase: .evaluations, exists: true, isComplete: false,
            completedCount: 3, totalCount: 5, missingItems: ["task-4", "task-5"]
        )
        #expect(partial.summary == "partial (3/5)")
        #expect(partial.isPartial)

        let incomplete = PhaseStatus(
            phase: .rules, exists: true, isComplete: false,
            completedCount: 0, totalCount: 1, missingItems: ["all-rules.json"]
        )
        #expect(incomplete.summary == "incomplete")
        #expect(!incomplete.isPartial)
    }

    @Test("PhaseStatus completionPercentage calculates correctly")
    func completionPercentage() {
        let half = PhaseStatus(
            phase: .evaluations, exists: true, isComplete: false,
            completedCount: 5, totalCount: 10, missingItems: []
        )
        #expect(half.completionPercentage == 50.0)

        let empty = PhaseStatus(
            phase: .tasks, exists: false, isComplete: false,
            completedCount: 0, totalCount: 0, missingItems: []
        )
        #expect(empty.completionPercentage == 0.0)

        let emptyComplete = PhaseStatus(
            phase: .tasks, exists: true, isComplete: true,
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
            phase: .pullRequest
        )
        #expect(dir == "/output/42/phase-1-pull-request")
    }

    @Test("canRunPhase returns true for first phase")
    func canRunFirstPhase() {
        // Phase 1 has no predecessor, always runnable
        let canRun = DataPathsService.canRunPhase(
            .pullRequest,
            outputDir: "/nonexistent",
            prNumber: "1"
        )
        #expect(canRun)
    }

    @Test("validateCanRun returns error for phase with missing predecessor")
    func validateCanRunError() {
        let error = DataPathsService.validateCanRun(
            .focusAreas,
            outputDir: "/nonexistent",
            prNumber: "1"
        )
        #expect(error != nil)
        #expect(error!.contains("phase-1-pull-request"))
    }
}
