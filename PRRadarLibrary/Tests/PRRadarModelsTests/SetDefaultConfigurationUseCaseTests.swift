import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRReviewFeature

@Suite("SetDefaultConfigurationUseCase")
struct SetDefaultConfigurationUseCaseTests {

    private func makeTempService() -> SettingsService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return SettingsService(settingsURL: fileURL)
    }

    @Test("Sets the specified configuration as default")
    func setsDefault() throws {
        let service = makeTempService()
        let saveUseCase = SaveConfigurationUseCase(settingsService: service)
        let setDefaultUseCase = SetDefaultConfigurationUseCase(settingsService: service)
        let first = RepoConfiguration(name: "first", repoPath: "/tmp/repo1")
        _ = try saveUseCase.execute(config: first)
        let second = RepoConfiguration(name: "second", repoPath: "/tmp/repo2")
        let settings = try saveUseCase.execute(config: second)

        let result = try setDefaultUseCase.execute(id: second.id, settings: settings)

        #expect(result.configurations[0].isDefault == false)
        #expect(result.configurations[1].isDefault == true)
    }

    @Test("Toggling default clears previous default")
    func clearsPreviousDefault() throws {
        let service = makeTempService()
        let saveUseCase = SaveConfigurationUseCase(settingsService: service)
        let setDefaultUseCase = SetDefaultConfigurationUseCase(settingsService: service)
        let first = RepoConfiguration(name: "first", repoPath: "/tmp/repo1")
        _ = try saveUseCase.execute(config: first)
        let second = RepoConfiguration(name: "second", repoPath: "/tmp/repo2")
        _ = try saveUseCase.execute(config: second)

        var settings = try setDefaultUseCase.execute(id: second.id, settings: service.load())
        let result = try setDefaultUseCase.execute(id: first.id, settings: settings)

        #expect(result.configurations[0].isDefault == true)
        #expect(result.configurations[1].isDefault == false)
    }

    @Test("Default change persists to disk")
    func persistsToDisk() throws {
        let service = makeTempService()
        let saveUseCase = SaveConfigurationUseCase(settingsService: service)
        let setDefaultUseCase = SetDefaultConfigurationUseCase(settingsService: service)
        let first = RepoConfiguration(name: "first", repoPath: "/tmp/repo1")
        _ = try saveUseCase.execute(config: first)
        let second = RepoConfiguration(name: "second", repoPath: "/tmp/repo2")
        _ = try saveUseCase.execute(config: second)

        _ = try setDefaultUseCase.execute(id: second.id, settings: service.load())

        let loaded = service.load()
        #expect(loaded.configurations[0].isDefault == false)
        #expect(loaded.configurations[1].isDefault == true)
    }
}
