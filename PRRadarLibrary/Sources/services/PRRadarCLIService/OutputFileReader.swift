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

    public static func files(
        in config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        subdirectory: String
    ) -> [String] {
        let subdir = DataPathsService.phaseSubdirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase,
            subdirectory: subdirectory
        )
        let contents = try? FileManager.default.contentsOfDirectory(atPath: subdir)
        return (contents ?? []).sorted()
    }

    public static func phaseSubdirectoryPath(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        subdirectory: String
    ) -> String {
        DataPathsService.phaseSubdirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase,
            subdirectory: subdirectory
        )
    }
}
