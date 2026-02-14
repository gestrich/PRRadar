import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRReviewFeature

@Suite("RemoveConfigurationUseCase")
struct RemoveConfigurationUseCaseTests {

    private func makeTempService() -> SettingsService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return SettingsService(settingsURL: fileURL)
    }

    @Test("Removes configuration by ID")
    func removesById() throws {
        let service = makeTempService()
        let saveUseCase = SaveConfigurationUseCase(settingsService: service)
        let removeUseCase = RemoveConfigurationUseCase(settingsService: service)
        let config = RepoConfiguration(name: "to-remove", repoPath: "/tmp/repo")
        let settings = try saveUseCase.execute(config: config)

        let result = try removeUseCase.execute(id: config.id)

        #expect(result.configurations.isEmpty)
    }

    @Test("Reassigns default when removing the default configuration")
    func reassignsDefault() throws {
        let service = makeTempService()
        let saveUseCase = SaveConfigurationUseCase(settingsService: service)
        let removeUseCase = RemoveConfigurationUseCase(settingsService: service)
        let first = RepoConfiguration(name: "first", repoPath: "/tmp/repo1")
        _ = try saveUseCase.execute(config: first)
        let second = RepoConfiguration(name: "second", repoPath: "/tmp/repo2")
        let settings = try saveUseCase.execute(config: second)

        #expect(settings.configurations[0].isDefault == true)
        let result = try removeUseCase.execute(id: first.id)

        #expect(result.configurations.count == 1)
        #expect(result.configurations[0].name == "second")
        #expect(result.configurations[0].isDefault == true)
    }

    @Test("Removal persists to disk")
    func removalPersistsToDisk() throws {
        let service = makeTempService()
        let saveUseCase = SaveConfigurationUseCase(settingsService: service)
        let removeUseCase = RemoveConfigurationUseCase(settingsService: service)
        let config = RepoConfiguration(name: "temp", repoPath: "/tmp/repo")
        let settings = try saveUseCase.execute(config: config)

        _ = try removeUseCase.execute(id: config.id)

        let loaded = service.load()
        #expect(loaded.configurations.isEmpty)
    }
}
