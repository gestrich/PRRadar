import Foundation
import PRRadarConfigService
import PRReviewFeature

@Observable
@MainActor
public final class SettingsModel {

    private let loadSettingsUseCase: LoadSettingsUseCase
    private let saveConfigurationUseCase: SaveConfigurationUseCase
    private let removeConfigurationUseCase: RemoveConfigurationUseCase
    private let setDefaultConfigurationUseCase: SetDefaultConfigurationUseCase

    private var continuations: [UUID: AsyncStream<AppSettings>.Continuation] = [:]

    private(set) var settings: AppSettings {
        didSet {
            for continuation in continuations.values {
                continuation.yield(settings)
            }
        }
    }

    public init(
        loadSettingsUseCase: LoadSettingsUseCase,
        saveConfigurationUseCase: SaveConfigurationUseCase,
        removeConfigurationUseCase: RemoveConfigurationUseCase,
        setDefaultConfigurationUseCase: SetDefaultConfigurationUseCase
    ) {
        self.loadSettingsUseCase = loadSettingsUseCase
        self.saveConfigurationUseCase = saveConfigurationUseCase
        self.removeConfigurationUseCase = removeConfigurationUseCase
        self.setDefaultConfigurationUseCase = setDefaultConfigurationUseCase
        self.settings = loadSettingsUseCase.execute()
    }

    public convenience init() {
        let service = SettingsService()
        self.init(
            loadSettingsUseCase: LoadSettingsUseCase(settingsService: service),
            saveConfigurationUseCase: SaveConfigurationUseCase(settingsService: service),
            removeConfigurationUseCase: RemoveConfigurationUseCase(settingsService: service),
            setDefaultConfigurationUseCase: SetDefaultConfigurationUseCase(settingsService: service)
        )
    }

    // MARK: - CRUD

    func addConfiguration(_ config: RepoConfiguration) throws {
        settings = try saveConfigurationUseCase.execute(config: config)
    }

    func updateConfiguration(_ config: RepoConfiguration) throws {
        settings = try saveConfigurationUseCase.execute(config: config)
    }

    func removeConfiguration(id: UUID) throws {
        settings = try removeConfigurationUseCase.execute(id: id, settings: settings)
    }

    func setDefault(id: UUID) throws {
        settings = try setDefaultConfigurationUseCase.execute(id: id, settings: settings)
    }

    // MARK: - Child-to-Parent Propagation

    func observeChanges() -> AsyncStream<AppSettings> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: AppSettings.self)
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.continuations.removeValue(forKey: id)
            }
        }
        return stream
    }

}
