import ArgumentParser
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show pipeline status for a PR"
    )

    @Argument(help: "Pull request number")
    var prNumber: String

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        let config = resolveConfig(repoPath: repoPath, outputDir: outputDir)

        struct PhaseStatus {
            let phase: PRRadarPhase
            let status: String
            let fileCount: Int
        }

        var statuses: [PhaseStatus] = []

        for phase in PRRadarPhase.allCases {
            let files = OutputFileReader.files(in: config, prNumber: prNumber, phase: phase)
            let status: String
            if files.isEmpty {
                status = "missing"
            } else {
                let hasJson = files.contains { $0.hasSuffix(".json") }
                status = hasJson ? "complete" : "partial"
            }
            statuses.append(PhaseStatus(phase: phase, status: status, fileCount: files.count))
        }

        if json {
            var jsonOutput: [[String: Any]] = []
            for s in statuses {
                jsonOutput.append([
                    "phase": s.phase.rawValue,
                    "status": s.status,
                    "file_count": s.fileCount,
                ])
            }
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Pipeline status for PR #\(prNumber):")
            print("")
            print(String(format: "  %-30s  %-10s  %s", "Phase", "Status", "Files"))
            print(String(format: "  %-30s  %-10s  %s", "-----", "------", "-----"))
            for s in statuses {
                let statusIcon: String
                switch s.status {
                case "complete": statusIcon = "\u{001B}[32m\u{2713}\u{001B}[0m"
                case "partial": statusIcon = "\u{001B}[33m~\u{001B}[0m"
                default: statusIcon = "\u{001B}[31m\u{2717}\u{001B}[0m"
                }
                print("  \(statusIcon) \(String(format: "%-28s", s.phase.rawValue))  \(String(format: "%-10s", s.status))  \(s.fileCount)")
            }
        }
    }
}

func severityColor(_ score: Int) -> String {
    switch score {
    case 1...4: return "\u{001B}[32m"  // green
    case 5...7: return "\u{001B}[33m"  // yellow/orange
    default: return "\u{001B}[31m"     // red
    }
}
