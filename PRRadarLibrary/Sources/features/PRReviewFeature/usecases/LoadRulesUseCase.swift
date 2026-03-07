import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct LoadRulesUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute() async throws -> [(rulePath: RulePath, rules: [ReviewRule])] {
        let gitOps = GitHubServiceFactory.createGitOps()
        let ruleLoader = RuleLoaderService(gitOps: gitOps)
        var result: [(rulePath: RulePath, rules: [ReviewRule])] = []
        for rulePath in config.rulePaths {
            let dir = config.resolvedRulesDir(for: rulePath)
            let rules = try await ruleLoader.loadAllRules(rulesDir: dir)
            result.append((rulePath: rulePath, rules: rules))
        }
        return result
    }
}
