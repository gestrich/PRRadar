import ArgumentParser
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct TranscriptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcript",
        abstract: "View saved AI transcripts for a PR"
    )

    @OptionGroup var options: CLIOptions

    @Option(name: .long, help: "Filter by phase (prepare, evaluate)")
    var phase: String?

    @Option(name: .long, help: "Display a specific task's transcript by identifier")
    var task: String?

    @Flag(name: .long, help: "Output raw transcript JSON")
    var jsonOutput: Bool = false

    @Flag(name: .long, help: "Output rendered markdown (default for terminal)")
    var markdown: Bool = false

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let commitHash = options.commit ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: options.prNumber)

        let phasesToCheck: [PRRadarPhase]
        if let phaseStr = phase {
            guard let matched = PRRadarPhase.allCases.first(where: { $0.rawValue == phaseStr }) else {
                throw CLIError.phaseFailed("Unknown phase '\(phaseStr)'. Valid: prepare, evaluate")
            }
            phasesToCheck = [matched]
        } else {
            phasesToCheck = [.prepare, .analyze]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var allTranscripts: [(phase: PRRadarPhase, transcript: ClaudeAgentTranscript)] = []

        for p in phasesToCheck {
            let files = PhaseOutputParser.listPhaseFiles(
                config: config, prNumber: options.prNumber, phase: p, commitHash: commitHash
            )
            let transcriptFiles = files.filter { $0.hasPrefix("ai-transcript-") && $0.hasSuffix(".json") }

            for filename in transcriptFiles {
                guard let data = try? PhaseOutputParser.readPhaseFile(
                    config: config, prNumber: options.prNumber, phase: p, filename: filename, commitHash: commitHash
                ),
                      let transcript = try? decoder.decode(ClaudeAgentTranscript.self, from: data)
                else { continue }

                allTranscripts.append((phase: p, transcript: transcript))
            }
        }

        if allTranscripts.isEmpty {
            if options.json || jsonOutput {
                print("[]")
            } else {
                print("No transcripts found for PR #\(options.prNumber).")
            }
            return
        }

        // If a specific task is requested, filter to it
        if let taskId = task {
            guard let match = allTranscripts.first(where: { $0.transcript.identifier == taskId }) else {
                throw CLIError.phaseFailed("No transcript found with identifier '\(taskId)'")
            }
            printTranscript(match.transcript, phase: match.phase)
            return
        }

        // List mode: show all transcripts
        if options.json || jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let transcriptObjects = allTranscripts.map(\.transcript)
            let data = try encoder.encode(transcriptObjects)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Transcripts for PR #\(options.prNumber):\n")
            for (p, transcript) in allTranscripts {
                let model = displayName(forModelId: transcript.model)
                let cost = String(format: "$%.4f", transcript.costUsd)
                let duration = "\(transcript.durationMs)ms"
                print("  [\(p.displayName)] \(transcript.identifier)  \(model)  \(cost)  \(duration)")
            }
            print("\nUse --task <identifier> to view a specific transcript.")
        }
    }

    private func printTranscript(_ transcript: ClaudeAgentTranscript, phase: PRRadarPhase) {
        if options.json || jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(transcript) {
                print(String(data: data, encoding: .utf8)!)
            }
        } else {
            print(ClaudeAgentTranscriptWriter.renderMarkdown(transcript))
        }
    }
}
