import Foundation
@testable import MacApp
@testable import PRRadarConfigService
@testable import PRReviewFeature
import Testing

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {

    private func makeModel() -> SettingsModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        let service = SettingsService(settingsURL: fileURL)
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
    func addConfiguration() throws {
        let model = makeModel()
        let config = RepositoryConfigurationJSON(name: "test", repoPath: "/tmp/repo")

        try model.addConfiguration(config)

        #expect(model.settings.configurations.count == 1)
        #expect(model.settings.configurations[0].name == "test")
    }

    @Test("updateConfiguration modifies existing configuration")
    func updateConfiguration() throws {
        let model = makeModel()
        let configId = UUID()
        let config = RepositoryConfigurationJSON(id: configId, name: "original", repoPath: "/tmp/repo")
        try model.addConfiguration(config)

        var modified = config
        modified.name = "updated"
        try model.updateConfiguration(modified)

        #expect(model.settings.configurations.count == 1)
        #expect(model.settings.configurations[0].name == "updated")
    }

    @Test("removeConfiguration removes by ID")
    func removeConfiguration() throws {
        let model = makeModel()
        let config = RepositoryConfigurationJSON(name: "doomed", repoPath: "/tmp/repo")
        try model.addConfiguration(config)

        try model.removeConfiguration(id: config.id)

        #expect(model.settings.configurations.isEmpty)
    }

    @Test("setDefault changes the default configuration")
    func setDefault() throws {
        let model = makeModel()
        let first = RepositoryConfigurationJSON(name: "first", repoPath: "/tmp/repo1")
        let second = RepositoryConfigurationJSON(name: "second", repoPath: "/tmp/repo2")
        try model.addConfiguration(first)
        try model.addConfiguration(second)

        try model.setDefault(id: second.id)

        #expect(model.settings.configurations[0].isDefault == false)
        #expect(model.settings.configurations[1].isDefault == true)
    }

    // MARK: - Upsert Behavior

    @Test("Updating nonexistent configuration adds it")
    func updateNonexistentAdds() throws {
        let model = makeModel()
        let config = RepositoryConfigurationJSON(name: "ghost", repoPath: "/tmp/repo")

        try model.updateConfiguration(config)

        #expect(model.settings.configurations.count == 1)
        #expect(model.settings.configurations[0].name == "ghost")
    }

    @Test("Successful add does not throw")
    func addDoesNotThrow() throws {
        let model = makeModel()
        let config = RepositoryConfigurationJSON(name: "valid", repoPath: "/tmp/repo")

        try model.addConfiguration(config)

        #expect(model.settings.configurations.count == 1)
    }

    // MARK: - observeChanges

    @Test("observeChanges yields settings on mutation")
    func observeChangesYields() async throws {
        let model = makeModel()
        let stream = model.observeChanges()
        let config = RepositoryConfigurationJSON(name: "observed", repoPath: "/tmp/repo")

        try model.addConfiguration(config)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received?.configurations.count == 1)
        #expect(received?.configurations[0].name == "observed")
    }
}
