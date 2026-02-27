import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct LoadPRDetailUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(prNumber: Int, commitHash: String? = nil) -> PRDetail {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let syncSnapshot: SyncSnapshot? = {
            let snapshot = SyncPRUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: resolvedCommit)
            if snapshot.fullDiff != nil || snapshot.effectiveDiff != nil {
                return snapshot
            }
            return nil
        }()

        let preparation = try? PrepareUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: resolvedCommit)
        let analysis = try? AnalyzeUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: resolvedCommit)
        let report = try? GenerateReportUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: resolvedCommit)

        let phaseStatuses = DataPathsService.allPhaseStatuses(
            outputDir: config.resolvedOutputDir,
            prNumber: prNumber,
            commitHash: resolvedCommit
        )

        let postedComments: GitHubPullRequestComments? = try? PhaseOutputParser.parsePhaseOutput(
            config: config,
            prNumber: prNumber,
            phase: .metadata,
            filename: DataPathsService.ghCommentsFilename
        )

        var imageURLMap: [String: String] = [:]
        var imageBaseDir: String?
        if let map: [String: String] = try? PhaseOutputParser.parsePhaseOutput(
            config: config,
            prNumber: prNumber,
            phase: .metadata,
            filename: DataPathsService.imageURLMapFilename
        ) {
            imageURLMap = map
            let phaseDir = OutputFileReader.phaseDirectoryPath(
                config: config, prNumber: prNumber, phase: .metadata
            )
            imageBaseDir = "\(phaseDir)/images"
        }

        let savedTranscripts = loadSavedTranscripts(prNumber: prNumber, commitHash: resolvedCommit)

        let availableCommits = scanAvailableCommits(prNumber: prNumber)

        let analysisSummary: PRReviewSummary? = try? PhaseOutputParser.parsePhaseOutput(
            config: config,
            prNumber: prNumber,
            phase: .analyze,
            filename: DataPathsService.summaryJSONFilename,
            commitHash: resolvedCommit
        )

        let reviewComments = FetchReviewCommentsUseCase(config: config)
            .execute(prNumber: prNumber, commitHash: resolvedCommit)

        return PRDetail(
            commitHash: resolvedCommit,
            availableCommits: availableCommits,
            phaseStatuses: phaseStatuses,
            syncSnapshot: syncSnapshot,
            preparation: preparation,
            analysis: analysis,
            report: report,
            postedComments: postedComments,
            imageURLMap: imageURLMap,
            imageBaseDir: imageBaseDir,
            savedTranscripts: savedTranscripts,
            analysisSummary: analysisSummary,
            reviewComments: reviewComments
        )
    }

    // MARK: - Private

    private func loadSavedTranscripts(prNumber: Int, commitHash: String?) -> [PRRadarPhase: [ClaudeAgentTranscript]] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result: [PRRadarPhase: [ClaudeAgentTranscript]] = [:]

        let prepareFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare,
            subdirectory: DataPathsService.prepareFocusAreasSubdir, commitHash: commitHash
        )
        let prepareTranscripts = loadTranscripts(
            from: prepareFiles, prNumber: prNumber, phase: .prepare,
            subdirectory: DataPathsService.prepareFocusAreasSubdir, commitHash: commitHash, decoder: decoder
        )
        if !prepareTranscripts.isEmpty {
            result[.prepare] = prepareTranscripts
        }

        let analyzeFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: commitHash
        )
        let analyzeTranscripts = loadTranscripts(
            from: analyzeFiles, prNumber: prNumber, phase: .analyze,
            subdirectory: nil, commitHash: commitHash, decoder: decoder
        )
        if !analyzeTranscripts.isEmpty {
            result[.analyze] = analyzeTranscripts
        }

        return result
    }

    private func loadTranscripts(
        from files: [String], prNumber: Int, phase: PRRadarPhase,
        subdirectory: String?, commitHash: String?, decoder: JSONDecoder
    ) -> [ClaudeAgentTranscript] {
        let transcriptFiles = files.filter { $0.hasPrefix("ai-transcript-") && $0.hasSuffix(".json") }
        var transcripts: [ClaudeAgentTranscript] = []
        for filename in transcriptFiles {
            let data: Data?
            if let subdirectory {
                data = try? PhaseOutputParser.readPhaseFile(
                    config: config, prNumber: prNumber, phase: phase,
                    subdirectory: subdirectory, filename: filename, commitHash: commitHash
                )
            } else {
                data = try? PhaseOutputParser.readPhaseFile(
                    config: config, prNumber: prNumber, phase: phase,
                    filename: filename, commitHash: commitHash
                )
            }
            if let data, let transcript = try? decoder.decode(ClaudeAgentTranscript.self, from: data) {
                transcripts.append(transcript)
            }
        }
        return transcripts
    }

    private func scanAvailableCommits(prNumber: Int) -> [String] {
        let analysisRoot = "\(config.resolvedOutputDir)/\(prNumber)/\(DataPathsService.analysisDirectoryName)"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: analysisRoot) else {
            return []
        }
        return dirs.filter { !$0.hasPrefix(".") }.sorted()
    }
}
