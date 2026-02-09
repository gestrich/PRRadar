import Foundation
import PRRadarConfigService

public enum OutputFileReader {
    public static func files(
        in config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase
    ) -> [String] {
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase
        )
        let contents = try? FileManager.default.contentsOfDirectory(atPath: phaseDir)
        return (contents ?? []).sorted()
    }

    public static func phaseDirectoryPath(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase
    ) -> String {
        DataPathsService.phaseDirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase
        )
    }
}
