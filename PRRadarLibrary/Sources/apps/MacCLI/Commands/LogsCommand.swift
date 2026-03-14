import ArgumentParser
import Foundation
import LoggingSDK
import PRReviewFeature

struct LogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View PRRadar log entries"
    )

    @Flag(name: .long, help: "Show only the most recent analysis run")
    var lastRun: Bool = false

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var from: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var to: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Filter by log level (debug, info, warning, error)")
    var level: String?

    func validate() throws {
        if (from != nil) != (to != nil) {
            throw ValidationError("Both --from and --to must be specified together")
        }
        if lastRun && from != nil {
            throw ValidationError("Cannot combine --last-run with --from/--to")
        }
    }

    func run() throws {
        let query: LogQuery
        if lastRun {
            query = .lastRun
        } else if let fromStr = from, let toStr = to {
            guard let fromDate = parseDateString(fromStr) else {
                throw ValidationError("Invalid --from date '\(fromStr)'. Use YYYY-MM-DD format.")
            }
            guard var toDate = parseDateString(toStr) else {
                throw ValidationError("Invalid --to date '\(toStr)'. Use YYYY-MM-DD format.")
            }
            toDate = Calendar.current.date(byAdding: .day, value: 1, to: toDate)!
            query = .dateRange(from: fromDate, to: toDate)
        } else {
            query = .all
        }

        var entries = try FetchLogsUseCase().execute(query: query)

        if let level {
            entries = entries.filter { $0.level == level }
        }

        if entries.isEmpty {
            print("No log entries found.")
            return
        }

        if json {
            let data = try JSONEncoder().encode(entries)
            print(String(data: data, encoding: .utf8)!)
        } else {
            for entry in entries {
                let metaStr: String
                if let metadata = entry.metadata, !metadata.isEmpty {
                    metaStr = " " + metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
                } else {
                    metaStr = ""
                }
                let levelColor = levelColorCode(entry.level)
                print("\(entry.timestamp) \(levelColor)[\(entry.level.uppercased())]\u{001B}[0m \(entry.label): \(entry.message)\(metaStr)")
            }
        }
    }

    private func levelColorCode(_ level: String) -> String {
        switch level {
        case "error", "critical": return "\u{001B}[31m"
        case "warning": return "\u{001B}[33m"
        case "info": return "\u{001B}[32m"
        case "debug", "trace": return "\u{001B}[90m"
        default: return ""
        }
    }
}
