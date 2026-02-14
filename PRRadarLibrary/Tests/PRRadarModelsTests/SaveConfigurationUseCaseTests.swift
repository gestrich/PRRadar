import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRReviewFeature

@Suite("SaveConfigurationUseCase")
struct SaveConfigurationUseCaseTests {

    private func makeTempService() -> SettingsService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return SettingsService(fileURL: fileURL)
    }

    // MARK: - Add (isNew: true)

    @Test("Adding first configuration marks it as default")
    func addFirstConfigBecomesDefault() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let config = RepoConfiguration(name: "first", repoPath: "/tmp/repo")

        let result = try useCase.execute(config: config, settings: AppSettings(), isNew: true)

        #expect(result.configurations.count == 1)
        #expect(result.configurations[0].isDefault == true)
        #expect(result.configurations[0].name == "first")
    }

    @Test("Adding second configuration does not override default")
    func addSecondConfigKeepsDefault() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let first = RepoConfiguration(name: "first", repoPath: "/tmp/repo1")
        let settings = try useCase.execute(config: first, settings: AppSettings(), isNew: true)

        let second = RepoConfiguration(name: "second", repoPath: "/tmp/repo2")
        let result = try useCase.execute(config: second, settings: settings, isNew: true)

        #expect(result.configurations.count == 2)
        #expect(result.configurations[0].isDefault == true)
        #expect(result.configurations[1].isDefault == false)
    }

    @Test("Added configuration persists to disk")
    func addPersistsToDisk() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let config = RepoConfiguration(name: "persisted", repoPath: "/tmp/repo")

        _ = try useCase.execute(config: config, settings: AppSettings(), isNew: true)

        let loaded = service.load()
        #expect(loaded.configurations.count == 1)
        #expect(loaded.configurations[0].name == "persisted")
    }

    // MARK: - Update (isNew: false)

    @Test("Updating existing configuration replaces it in place")
    func updateExistingConfig() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let configId = UUID()
        let original = RepoConfiguration(id: configId, name: "original", repoPath: "/tmp/repo")
        let settings = try useCase.execute(config: original, settings: AppSettings(), isNew: true)

        var modified = original
        modified.name = "updated"
        let result = try useCase.execute(config: modified, settings: settings, isNew: false)

        #expect(result.configurations.count == 1)
        #expect(result.configurations[0].name == "updated")
        #expect(result.configurations[0].id == configId)
    }

    @Test("Updating non-existent configuration throws configurationNotFound")
    func updateNonExistentThrows() throws {
        let service = makeTempService()
        let useCase = SaveConfigurationUseCase(settingsService: service)
        let config = RepoConfiguration(name: "ghost", repoPath: "/tmp/repo")

        #expect(throws: SaveConfigurationError.self) {
            try useCase.execute(config: config, settings: AppSettings(), isNew: false)
        }
    }
}
