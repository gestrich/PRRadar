import ArgumentParser
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show pipeline status for a PR"
    )

    @OptionGroup var options: CLIOptions

    func run() async throws {
        let config = try resolveConfigFromOptions(options)

        let commitHash = options.commit ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: options.prNumber)

        let allStatuses = DataPathsService.allPhaseStatuses(
            outputDir: config.resolvedOutputDir,
            prNumber: options.prNumber,
            commitHash: commitHash
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

        let availableCommits = listAvailableCommits(outputDir: config.resolvedOutputDir, prNumber: options.prNumber)

        if options.json {
            var jsonOutput: [String: Any] = [:]
            if let commitHash { jsonOutput["commitHash"] = commitHash }
            jsonOutput["availableCommits"] = availableCommits
            var phases: [[String: Any]] = []
            for s in statuses {
                phases.append([
                    "phase": s.phase.rawValue,
                    "status": s.status,
                    "artifacts": s.fileCount,
                ])
            }
            jsonOutput["phases"] = phases
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            if let commitHash {
                print("Pipeline status for PR #\(options.prNumber) @ \(commitHash):")
            } else {
                print("Pipeline status for PR #\(options.prNumber):")
            }
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
            if availableCommits.count > 1 {
                print("\n  Available commits:")
                for c in availableCommits {
                    let marker = (c == commitHash) ? " (current)" : ""
                    print("    \(c)\(marker)")
                }
            }
        }
    }

    private func listAvailableCommits(outputDir: String, prNumber: Int) -> [String] {
        let analysisRoot = "\(outputDir)/\(prNumber)/\(DataPathsService.analysisDirectoryName)"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: analysisRoot) else {
            return []
        }
        return dirs.filter { !$0.hasPrefix(".") }.sorted()
    }
}

func severityColor(_ score: Int) -> String {
    switch score {
    case 1...4: return "\u{001B}[32m"  // green
    case 5...7: return "\u{001B}[33m"  // yellow/orange
    default: return "\u{001B}[31m"     // red
    }
}
