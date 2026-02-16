import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRReviewFeature

@Suite("SaveConfigurationUseCase")
struct SaveConfigurationUseCaseTests {

    private func makeTempService() -> SettingsService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return SettingsService(settingsURL: fileURL)
    }

    // MARK: - Add

    @Test("Adding first configuration marks it as default")
    func addFirstConfigBecomesDefault() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let config = RepositoryConfigurationJSON(name: "first", repoPath: "/tmp/repo", githubAccount: "test")

        let result = try useCase.execute(config: config)

        #expect(result.configurations.count == 1)
        #expect(result.configurations[0].isDefault == true)
        #expect(result.configurations[0].name == "first")
    }

    @Test("Adding second configuration does not override default")
    func addSecondConfigKeepsDefault() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let first = RepositoryConfigurationJSON(name: "first", repoPath: "/tmp/repo1", githubAccount: "test")
        _ = try useCase.execute(config: first)

        let second = RepositoryConfigurationJSON(name: "second", repoPath: "/tmp/repo2", githubAccount: "test")
        let result = try useCase.execute(config: second)

        #expect(result.configurations.count == 2)
        #expect(result.configurations[0].isDefault == true)
        #expect(result.configurations[1].isDefault == false)
    }

    @Test("Added configuration persists to disk")
    func addPersistsToDisk() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let config = RepositoryConfigurationJSON(name: "persisted", repoPath: "/tmp/repo", githubAccount: "test")

        _ = try useCase.execute(config: config)

        let loaded = service.load()
        #expect(loaded.configurations.count == 1)
        #expect(loaded.configurations[0].name == "persisted")
    }

    // MARK: - Update

    @Test("Updating existing configuration replaces it in place")
    func updateExistingConfig() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let configId = UUID()
        let original = RepositoryConfigurationJSON(id: configId, name: "original", repoPath: "/tmp/repo", githubAccount: "test")
        _ = try useCase.execute(config: original)

        var modified = original
        modified.name = "updated"
        let result = try useCase.execute(config: modified)

        #expect(result.configurations.count == 1)
        #expect(result.configurations[0].name == "updated")
        #expect(result.configurations[0].id == configId)
    }

    @Test("Saving config with unknown ID adds it")
    func saveUnknownIdAdds() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let config = RepositoryConfigurationJSON(name: "new", repoPath: "/tmp/repo", githubAccount: "test")

        let result = try useCase.execute(config: config)

        #expect(result.configurations.count == 1)
        #expect(result.configurations[0].name == "new")
    }
}
