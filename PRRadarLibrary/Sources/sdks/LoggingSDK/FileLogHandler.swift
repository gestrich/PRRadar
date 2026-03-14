import Foundation
import Logging

public struct FileLogHandler: LogHandler, Sendable {
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .info

    private let label: String
    private let fileURL: URL
    private let maxBytes: UInt64

    public init(label: String, fileURL: URL, maxBytes: UInt64 = 10_000_000) {
        self.label = label
        self.fileURL = fileURL
        self.maxBytes = maxBytes
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let merged = self.metadata.merging(metadata ?? [:]) { _, new in new }
        let entry = LogEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            level: "\(level)",
            label: label,
            message: "\(message)",
            metadata: merged.isEmpty ? nil : merged.mapValues { "\($0)" }
        )

        guard let data = try? JSONEncoder().encode(entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")

        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }

        let size = handle.seekToEndOfFile()
        if size > maxBytes {
            handle.seek(toFileOffset: 0)
            handle.truncateFile(atOffset: 0)
        }

        handle.write(Data(line.utf8))
    }
}

private struct LogEntry: Encodable {
    let timestamp: String
    let level: String
    let label: String
    let message: String
    let metadata: [String: String]?
}
