import Foundation
import PRRadarConfigService

public enum PhaseOutputParser {

    /// Decode a single JSON file from a phase output directory.
    public static func parsePhaseOutput<T: Decodable>(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        filename: String
    ) throws -> T {
        let data = try readPhaseFile(config: config, prNumber: prNumber, phase: phase, filename: filename)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// List all files in a phase output directory.
    public static func listPhaseFiles(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase
    ) -> [String] {
        OutputFileReader.files(in: config, prNumber: prNumber, phase: phase)
    }

    /// Read raw file data from a phase output directory.
    public static func readPhaseFile(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        filename: String
    ) throws -> Data {
        let dir = OutputFileReader.phaseDirectoryPath(config: config, prNumber: prNumber, phase: phase)
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
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase,
        filename: String
    ) throws -> String {
        let data = try readPhaseFile(config: config, prNumber: prNumber, phase: phase, filename: filename)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PhaseOutputError.unreadableFile(
                OutputFileReader.phaseDirectoryPath(config: config, prNumber: prNumber, phase: phase) + "/\(filename)"
            )
        }
        return text
    }

    /// Decode all data artifact JSON files (those with the `data-` prefix) in a phase directory.
    public static func parseAllPhaseFiles<T: Decodable>(
        config: PRRadarConfig,
        prNumber: String,
        phase: PRRadarPhase
    ) throws -> [T] {
        let dataFiles = listPhaseFiles(config: config, prNumber: prNumber, phase: phase)
            .filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        return try dataFiles.compactMap { filename in
            try parsePhaseOutput(config: config, prNumber: prNumber, phase: phase, filename: filename) as T
        }
    }
}

public enum PhaseOutputError: Error, Sendable {
    case fileNotFound(String)
    case unreadableFile(String)
}
