import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRReviewFeature

@Suite("LoadSettingsUseCase")
struct LoadSettingsUseCaseTests {

    private func makeTempService() -> (SettingsService, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return (SettingsService(settingsURL: fileURL), fileURL)
    }

    @Test("Returns empty settings when no file exists")
    func loadsEmptyWhenNoFile() {
        let (service, _) = makeTempService()
        let useCase = LoadSettingsUseCase(settingsService: service)

        let settings = useCase.execute()

        #expect(settings.configurations.isEmpty)
    }

    @Test("Returns persisted settings from disk")
    func loadsPersistedSettings() throws {
        let (service, _) = makeTempService()
        let config = RepoConfiguration(name: "test", repoPath: "/tmp/repo")
        var settings = AppSettings()
        service.addConfiguration(config, to: &settings)
        try service.save(settings)

        let useCase = LoadSettingsUseCase(settingsService: service)
        let loaded = useCase.execute()

        #expect(loaded.configurations.count == 1)
        #expect(loaded.configurations[0].name == "test")
    }
}
