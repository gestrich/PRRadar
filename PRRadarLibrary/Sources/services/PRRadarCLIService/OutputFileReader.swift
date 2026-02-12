import Foundation
import PRRadarConfigService

public enum OutputFileReader {
    public static func files(
        in config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) -> [String] {
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase,
            commitHash: commitHash
        )
        let contents = try? FileManager.default.contentsOfDirectory(atPath: phaseDir)
        return (contents ?? []).sorted()
    }

    public static func phaseDirectoryPath(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) -> String {
        DataPathsService.phaseDirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase,
            commitHash: commitHash
        )
    }

    public static func files(
        in config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        subdirectory: String,
        commitHash: String? = nil
    ) -> [String] {
        let subdir = DataPathsService.phaseSubdirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase,
            subdirectory: subdirectory,
            commitHash: commitHash
        )
        let contents = try? FileManager.default.contentsOfDirectory(atPath: subdir)
        return (contents ?? []).sorted()
    }

    public static func phaseSubdirectoryPath(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        subdirectory: String,
        commitHash: String? = nil
    ) -> String {
        DataPathsService.phaseSubdirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: phase,
            subdirectory: subdirectory,
            commitHash: commitHash
        )
    }
}
