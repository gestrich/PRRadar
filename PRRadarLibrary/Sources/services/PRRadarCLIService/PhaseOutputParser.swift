import Foundation
import PRRadarConfigService

public enum PhaseOutputParser {

    /// Decode a single JSON file from a phase output directory.
    public static func parsePhaseOutput<T: Decodable>(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        filename: String,
        commitHash: String? = nil
    ) throws -> T {
        let data = try readPhaseFile(config: config, prNumber: prNumber, phase: phase, filename: filename, commitHash: commitHash)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// List all files in a phase output directory.
    public static func listPhaseFiles(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) -> [String] {
        OutputFileReader.files(in: config, prNumber: prNumber, phase: phase, commitHash: commitHash)
    }

    /// Read raw file data from a phase output directory.
    public static func readPhaseFile(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        filename: String,
        commitHash: String? = nil
    ) throws -> Data {
        let dir = OutputFileReader.phaseDirectoryPath(config: config, prNumber: prNumber, phase: phase, commitHash: commitHash)
        let path = "\(dir)/\(filename)"
        guard FileManager.default.fileExists(atPath: path) else {
            throw PhaseOutputError.fileNotFound(path)
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw PhaseOutputError.unreadableFile(path)
        }
        return data
    }

    /// Read a text file from a phase output directory.
    public static func readPhaseTextFile(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        filename: String,
        commitHash: String? = nil
    ) throws -> String {
        let data = try readPhaseFile(config: config, prNumber: prNumber, phase: phase, filename: filename, commitHash: commitHash)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PhaseOutputError.unreadableFile(
                OutputFileReader.phaseDirectoryPath(config: config, prNumber: prNumber, phase: phase, commitHash: commitHash) + "/\(filename)"
            )
        }
        return text
    }

    /// Decode all data artifact JSON files (those with the `data-` prefix) in a phase directory.
    public static func parseAllPhaseFiles<T: Decodable>(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) throws -> [T] {
        let dataFiles = listPhaseFiles(config: config, prNumber: prNumber, phase: phase, commitHash: commitHash)
            .filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        return try dataFiles.compactMap { filename in
            try parsePhaseOutput(config: config, prNumber: prNumber, phase: phase, filename: filename, commitHash: commitHash) as T
        }
    }

    // MARK: - Subdirectory Variants

    /// Decode a single JSON file from a phase subdirectory.
    public static func parsePhaseOutput<T: Decodable>(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        subdirectory: String,
        filename: String,
        commitHash: String? = nil
    ) throws -> T {
        let data = try readPhaseFile(config: config, prNumber: prNumber, phase: phase, subdirectory: subdirectory, filename: filename, commitHash: commitHash)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// List all files in a phase subdirectory.
    public static func listPhaseFiles(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        subdirectory: String,
        commitHash: String? = nil
    ) -> [String] {
        OutputFileReader.files(in: config, prNumber: prNumber, phase: phase, subdirectory: subdirectory, commitHash: commitHash)
    }

    /// Read raw file data from a phase subdirectory.
    public static func readPhaseFile(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        subdirectory: String,
        filename: String,
        commitHash: String? = nil
    ) throws -> Data {
        let dir = OutputFileReader.phaseSubdirectoryPath(config: config, prNumber: prNumber, phase: phase, subdirectory: subdirectory, commitHash: commitHash)
        let path = "\(dir)/\(filename)"
        guard FileManager.default.fileExists(atPath: path) else {
            throw PhaseOutputError.fileNotFound(path)
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw PhaseOutputError.unreadableFile(path)
        }
        return data
    }

    /// Decode all data artifact JSON files in a phase subdirectory.
    public static func parseAllPhaseFiles<T: Decodable>(
        config: RepositoryConfiguration,
        prNumber: Int,
        phase: PRRadarPhase,
        subdirectory: String,
        commitHash: String? = nil
    ) throws -> [T] {
        let dataFiles = listPhaseFiles(config: config, prNumber: prNumber, phase: phase, subdirectory: subdirectory, commitHash: commitHash)
            .filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        return try dataFiles.compactMap { filename in
            try parsePhaseOutput(config: config, prNumber: prNumber, phase: phase, subdirectory: subdirectory, filename: filename, commitHash: commitHash) as T
        }
    }
}

public enum PhaseOutputError: Error, Sendable {
    case fileNotFound(String)
    case unreadableFile(String)
}
