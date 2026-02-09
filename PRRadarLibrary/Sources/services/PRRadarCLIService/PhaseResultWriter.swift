import Foundation
import PRRadarConfigService
import PRRadarModels

/// Service for writing phase_result.json files to track phase completion status.
public enum PhaseResultWriter {
    
    /// Write a successful phase result to the phase directory.
    ///
    /// - Parameters:
    ///   - phase: The phase that completed
    ///   - outputDir: The output directory (e.g., /path/to/output)
    ///   - prNumber: The PR number
    ///   - stats: Optional statistics about the phase execution
    public static func writeSuccess(
        phase: PRRadarPhase,
        outputDir: String,
        prNumber: String,
        stats: PhaseStats? = nil
    ) throws {
        let result = PhaseResult(
            phase: phase.rawValue,
            status: .success,
            errorMessage: nil,
            stats: stats
        )
        try write(result, phase: phase, outputDir: outputDir, prNumber: prNumber)
    }
    
    /// Write a failed phase result to the phase directory.
    ///
    /// - Parameters:
    ///   - phase: The phase that failed
    ///   - outputDir: The output directory
    ///   - prNumber: The PR number
    ///   - error: The error that occurred
    public static func writeFailure(
        phase: PRRadarPhase,
        outputDir: String,
        prNumber: String,
        error: String
    ) throws {
        let result = PhaseResult(
            phase: phase.rawValue,
            status: .failed,
            errorMessage: error,
            stats: nil
        )
        try write(result, phase: phase, outputDir: outputDir, prNumber: prNumber)
    }
    
    /// Read the phase result file for a given phase.
    ///
    /// - Parameters:
    ///   - phase: The phase to check
    ///   - outputDir: The output directory
    ///   - prNumber: The PR number
    /// - Returns: The PhaseResult if it exists, nil otherwise
    public static func read(
        phase: PRRadarPhase,
        outputDir: String,
        prNumber: String
    ) -> PhaseResult? {
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: phase
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
        prNumber: String
    ) throws {
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: phase
        )
        try DataPathsService.ensureDirectoryExists(at: phaseDir)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        
        let path = "\(phaseDir)/\(DataPathsService.phaseResultFilename)"
        try data.write(to: URL(fileURLWithPath: path))
    }
}
