import Foundation

public struct LogReaderService: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = PRRadarLogging.defaultLogFileURL) {
        self.fileURL = fileURL
    }

    public func readAll() throws -> [LogEntry] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(LogEntry.self, from: Data(line.utf8))
            }
    }

    public func readByDateRange(from start: Date, to end: Date) throws -> [LogEntry] {
        try readAll().filter { entry in
            guard let date = entry.date else { return false }
            return date >= start && date <= end
        }
    }

    public func readLastRun() throws -> [LogEntry] {
        let all = try readAll()

        guard let lastStartIndex = all.lastIndex(where: { $0.message == "Analysis started" }) else {
            return []
        }

        return Array(all[lastStartIndex...])
    }

    public func readRuns() throws -> [[LogEntry]] {
        let all = try readAll()
        var runs: [[LogEntry]] = []
        var currentRun: [LogEntry] = []

        for entry in all {
            if entry.message == "Analysis started" {
                if !currentRun.isEmpty {
                    runs.append(currentRun)
                }
                currentRun = [entry]
            } else {
                currentRun.append(entry)
            }
        }

        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        return runs
    }
}
