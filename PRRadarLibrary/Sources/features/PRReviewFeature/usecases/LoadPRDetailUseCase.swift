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
        let ghPR = PRDiscoveryService.loadGitHubPR(outputDir: config.resolvedOutputDir, prNumber: prNumber)

        let syncSnapshot: SyncSnapshot? = {
            let snapshot = SyncPRUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: resolvedCommit)
            if snapshot.prDiff != nil {
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

        let savedOutputs = loadSavedOutputs(prNumber: prNumber, commitHash: resolvedCommit)

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
            baseRefName: ghPR?.baseRefName,
            availableCommits: availableCommits,
            phaseStatuses: phaseStatuses,
            syncSnapshot: syncSnapshot,
            prDiff: syncSnapshot?.prDiff,
            storedEffectiveDiff: PhaseOutputParser.loadEffectiveDiff(config: config, prNumber: prNumber, commitHash: resolvedCommit),
            preparation: preparation,
            analysis: analysis,
            report: report,
            postedComments: postedComments,
            imageURLMap: imageURLMap,
            imageBaseDir: imageBaseDir,
            savedOutputs: savedOutputs,
            analysisSummary: analysisSummary,
            reviewComments: reviewComments
        )
    }

    // MARK: - Private

    private func loadSavedOutputs(prNumber: Int, commitHash: String?) -> [PRRadarPhase: [EvaluationOutput]] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result: [PRRadarPhase: [EvaluationOutput]] = [:]

        let prepareFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare,
            subdirectory: DataPathsService.prepareFocusAreasSubdir, commitHash: commitHash
        )
        let prepareOutputs = loadOutputs(
            from: prepareFiles, prNumber: prNumber, phase: .prepare,
            subdirectory: DataPathsService.prepareFocusAreasSubdir, commitHash: commitHash, decoder: decoder
        )
        if !prepareOutputs.isEmpty {
            result[.prepare] = prepareOutputs
        }

        let analyzeFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: commitHash
        )
        let analyzeOutputs = loadOutputs(
            from: analyzeFiles, prNumber: prNumber, phase: .analyze,
            subdirectory: nil, commitHash: commitHash, decoder: decoder
        )
        if !analyzeOutputs.isEmpty {
            result[.analyze] = analyzeOutputs
        }

        return result
    }

    private func loadOutputs(
        from files: [String], prNumber: Int, phase: PRRadarPhase,
        subdirectory: String?, commitHash: String?, decoder: JSONDecoder
    ) -> [EvaluationOutput] {
        let outputFiles = files.filter { $0.hasPrefix("output-") && $0.hasSuffix(".json") }
        var outputs: [EvaluationOutput] = []
        for filename in outputFiles {
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
            if let data, let output = try? decoder.decode(EvaluationOutput.self, from: data) {
                outputs.append(output)
            }
        }
        return outputs
    }

    private func scanAvailableCommits(prNumber: Int) -> [String] {
        let analysisRoot = "\(config.resolvedOutputDir)/\(prNumber)/\(DataPathsService.analysisDirectoryName)"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: analysisRoot) else {
            return []
        }
        return dirs.filter { !$0.hasPrefix(".") }.sorted()
    }
}
