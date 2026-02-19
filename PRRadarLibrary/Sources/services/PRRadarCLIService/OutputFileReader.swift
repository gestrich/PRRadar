import Foundation
import PRRadarConfigService

public enum OutputFileReader {
    public static func files(
        in config: RepositoryConfiguration,
        prNumber: String,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) -> [String] {
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: config.resolvedOutputDir,
            prNumber: prNumber,
            phase: phase,
            commitHash: commitHash
        )
        let contents = try? FileManager.default.contentsOfDirectory(atPath: phaseDir)
        return contents ?? []
    }

    public static func phaseDirectoryPath(
        config: RepositoryConfiguration,
        prNumber: String,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) -> String {
        DataPathsService.phaseDirectory(
            outputDir: config.resolvedOutputDir,
            prNumber: prNumber,
            phase: phase,
            commitHash: commitHash
        )
    }

    public static func files(
        in config: RepositoryConfiguration,
        prNumber: String,
        phase: PRRadarPhase,
        subdirectory: String,
        commitHash: String? = nil
    ) -> [String] {
        let subdir = DataPathsService.phaseSubdirectory(
            outputDir: config.resolvedOutputDir,
            prNumber: prNumber,
            phase: phase,
            subdirectory: subdirectory,
            commitHash: commitHash
        )
        let contents = try? FileManager.default.contentsOfDirectory(atPath: subdir)
        return contents ?? []
    }

    public static func phaseSubdirectoryPath(
        config: RepositoryConfiguration,
        prNumber: String,
        phase: PRRadarPhase,
        subdirectory: String,
        commitHash: String? = nil
    ) -> String {
        DataPathsService.phaseSubdirectory(
            outputDir: config.resolvedOutputDir,
            prNumber: prNumber,
            phase: phase,
            subdirectory: subdirectory,
            commitHash: commitHash
        )
    }
}
