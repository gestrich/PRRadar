import Foundation
import PRRadarConfigService
import PRRadarModels

/// Service for writing phase_result.json files to track phase completion status.
public enum PhaseResultWriter {
    
    public static func writeSuccess(
        phase: PRRadarPhase,
        outputDir: String,
        prNumber: Int,
        commitHash: String? = nil,
        stats: PhaseStats? = nil
    ) throws {
        let result = PhaseResult(
            phase: phase.rawValue,
            status: .success,
            errorMessage: nil,
            stats: stats
        )
        try write(result, phase: phase, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash)
    }

    public static func writeFailure(
        phase: PRRadarPhase,
        outputDir: String,
        prNumber: Int,
        commitHash: String? = nil,
        error: String
    ) throws {
        let result = PhaseResult(
            phase: phase.rawValue,
            status: .failed,
            errorMessage: error,
            stats: nil
        )
        try write(result, phase: phase, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash)
    }

    public static func read(
        phase: PRRadarPhase,
        outputDir: String,
        prNumber: Int,
        commitHash: String? = nil
    ) -> PhaseResult? {
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: phase,
            commitHash: commitHash
        )
        let path = "\(phaseDir)/\(DataPathsService.phaseResultFilename)"

        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }

        return try? JSONDecoder().decode(PhaseResult.self, from: data)
    }

    // MARK: - Private Helpers

    private static func write(
        _ result: PhaseResult,
        phase: PRRadarPhase,
        outputDir: String,
        prNumber: Int,
        commitHash: String? = nil
    ) throws {
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: phase,
            commitHash: commitHash
        )
        try DataPathsService.ensureDirectoryExists(at: phaseDir)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let path = "\(phaseDir)/\(DataPathsService.phaseResultFilename)"
        try data.write(to: URL(fileURLWithPath: path))
    }
}
