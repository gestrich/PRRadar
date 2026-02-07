import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRReviewFeature

@Observable
@MainActor
final class PRReviewModel {

    enum State {
        case idle
        case running(logs: String)
        case completed(files: [String], logs: String)
        case failed(error: String, logs: String)
    }

    private(set) var state: State = .idle

    var repoPath: String {
        get { access(keyPath: \.repoPath); return UserDefaults.standard.string(forKey: "repoPath") ?? "" }
        set { withMutation(keyPath: \.repoPath) { UserDefaults.standard.set(newValue, forKey: "repoPath") } }
    }

    var prNumber: String {
        get { access(keyPath: \.prNumber); return UserDefaults.standard.string(forKey: "prNumber") ?? "" }
        set { withMutation(keyPath: \.prNumber) { UserDefaults.standard.set(newValue, forKey: "prNumber") } }
    }

    var outputDir: String {
        get { access(keyPath: \.outputDir); return UserDefaults.standard.string(forKey: "outputDir") ?? "" }
        set { withMutation(keyPath: \.outputDir) { UserDefaults.standard.set(newValue, forKey: "outputDir") } }
    }

    private let venvBinPath: String
    private let environment: [String: String]

    init(venvBinPath: String, environment: [String: String]) {
        self.venvBinPath = venvBinPath
        self.environment = environment
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func runDiff() async {
        let config = PRRadarConfig(
            venvBinPath: venvBinPath,
            repoPath: repoPath,
            outputDir: outputDir
        )

        state = .running(logs: "Looking for prradar in: \(venvBinPath)\n")

        let runner = PRRadarCLIRunner()
        let useCase = FetchDiffUseCase(
            runner: runner,
            config: config,
            environment: environment
        )

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .completed(let files):
                    if case .running(let logs) = state {
                        state = .completed(files: files, logs: logs)
                    }
                case .failed(let error):
                    if case .running(let logs) = state {
                        state = .failed(error: error, logs: logs)
                    }
                }
            }
        } catch {
            let logs = if case .running(let l) = state { l } else { "" }
            state = .failed(error: error.localizedDescription, logs: logs)
        }
    }
}
