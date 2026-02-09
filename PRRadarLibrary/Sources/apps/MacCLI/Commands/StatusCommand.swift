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

    @OptionGroup var options: CLIOptions

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config

        let allStatuses = DataPathsService.allPhaseStatuses(
            outputDir: config.absoluteOutputDir,
            prNumber: options.prNumber
        )

        struct DisplayStatus {
            let phase: PRRadarPhase
            let status: String
            let fileCount: Int
        }

        var statuses: [DisplayStatus] = []
        for phase in PRRadarPhase.allCases {
            let phaseStatus = allStatuses[phase]!
            let statusText: String
            if !phaseStatus.exists {
                statusText = "not started"
            } else if phaseStatus.isComplete {
                statusText = "complete"
            } else if phaseStatus.isPartial {
                statusText = "partial"
            } else {
                statusText = "failed"
            }
            statuses.append(DisplayStatus(
                phase: phase,
                status: statusText,
                fileCount: phaseStatus.completedCount
            ))
        }

        if options.json {
            var jsonOutput: [[String: Any]] = []
            for s in statuses {
                jsonOutput.append([
                    "phase": s.phase.rawValue,
                    "status": s.status,
                    "artifacts": s.fileCount,
                ])
            }
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Pipeline status for PR #\(options.prNumber):")
            print("")
            print("  \("Phase".padding(toLength: 30, withPad: " ", startingAt: 0))  \("Status".padding(toLength: 12, withPad: " ", startingAt: 0))  Artifacts")
            print("  \("-----".padding(toLength: 30, withPad: " ", startingAt: 0))  \("------".padding(toLength: 12, withPad: " ", startingAt: 0))  ---------")
            for s in statuses {
                let statusIcon: String
                switch s.status {
                case "complete": statusIcon = "\u{001B}[32m\u{2713}\u{001B}[0m"
                case "partial": statusIcon = "\u{001B}[33m~\u{001B}[0m"
                case "not started": statusIcon = " "
                default: statusIcon = "\u{001B}[31m\u{2717}\u{001B}[0m"
                }
                print("  \(statusIcon) \(s.phase.rawValue.padding(toLength: 28, withPad: " ", startingAt: 0))  \(s.status.padding(toLength: 12, withPad: " ", startingAt: 0))  \(s.fileCount)")
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
