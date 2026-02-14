import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRReviewFeature
@testable import MacApp

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {

    private func makeModel() -> SettingsModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        let service = SettingsService(fileURL: fileURL)
        return SettingsModel(
            loadSettingsUseCase: LoadSettingsUseCase(settingsService: service),
            saveConfigurationUseCase: SaveConfigurationUseCase(settingsService: service),
            removeConfigurationUseCase: RemoveConfigurationUseCase(settingsService: service),
            setDefaultConfigurationUseCase: SetDefaultConfigurationUseCase(settingsService: service)
        )
    }

    // MARK: - Initialization

    @Test("Initializes with empty settings when no file exists")
    func initEmpty() {
        let model = makeModel()
        #expect(model.settings.configurations.isEmpty)
    }

    // MARK: - CRUD

    @Test("addConfiguration adds and updates settings property")
    func addConfiguration() {
        let model = makeModel()
        let config = RepoConfiguration(name: "test", repoPath: "/tmp/repo")

        model.addConfiguration(config)

        #expect(model.settings.configurations.count == 1)
        #expect(model.settings.configurations[0].name == "test")
    }

    @Test("updateConfiguration modifies existing configuration")
    func updateConfiguration() {
        let model = makeModel()
        let configId = UUID()
        let config = RepoConfiguration(id: configId, name: "original", repoPath: "/tmp/repo")
        model.addConfiguration(config)

        var modified = config
        modified.name = "updated"
        model.updateConfiguration(modified)

        #expect(model.settings.configurations.count == 1)
        #expect(model.settings.configurations[0].name == "updated")
    }

    @Test("removeConfiguration removes by ID")
    func removeConfiguration() {
        let model = makeModel()
        let config = RepoConfiguration(name: "doomed", repoPath: "/tmp/repo")
        model.addConfiguration(config)

        model.removeConfiguration(id: config.id)

        #expect(model.settings.configurations.isEmpty)
    }

    @Test("setDefault changes the default configuration")
    func setDefault() {
        let model = makeModel()
        let first = RepoConfiguration(name: "first", repoPath: "/tmp/repo1")
        let second = RepoConfiguration(name: "second", repoPath: "/tmp/repo2")
        model.addConfiguration(first)
        model.addConfiguration(second)

        model.setDefault(id: second.id)

        #expect(model.settings.configurations[0].isDefault == false)
        #expect(model.settings.configurations[1].isDefault == true)
    }

    // MARK: - observeChanges

    @Test("observeChanges yields settings on mutation")
    func observeChangesYields() async {
        let model = makeModel()
        let stream = model.observeChanges()
        let config = RepoConfiguration(name: "observed", repoPath: "/tmp/repo")

        model.addConfiguration(config)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received?.configurations.count == 1)
        #expect(received?.configurations[0].name == "observed")
    }
}
