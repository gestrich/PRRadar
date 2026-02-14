import Foundation
import PRRadarConfigService
import PRReviewFeature

@Observable
@MainActor
public final class SettingsModel {

    private(set) var settings: AppSettings

    private let loadSettingsUseCase: LoadSettingsUseCase
    private let saveConfigurationUseCase: SaveConfigurationUseCase
    private let removeConfigurationUseCase: RemoveConfigurationUseCase
    private let setDefaultConfigurationUseCase: SetDefaultConfigurationUseCase

    private var continuations: [UUID: AsyncStream<AppSettings>.Continuation] = [:]

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

    func addConfiguration(_ config: RepoConfiguration) {
        do {
            settings = try saveConfigurationUseCase.execute(config: config, settings: settings, isNew: true)
            notifyObservers()
        } catch {
            settings = loadSettingsUseCase.execute()
        }
    }

    func updateConfiguration(_ config: RepoConfiguration) {
        do {
            settings = try saveConfigurationUseCase.execute(config: config, settings: settings, isNew: false)
            notifyObservers()
        } catch {
            settings = loadSettingsUseCase.execute()
        }
    }

    func removeConfiguration(id: UUID) {
        do {
            settings = try removeConfigurationUseCase.execute(id: id, settings: settings)
            notifyObservers()
        } catch {
            settings = loadSettingsUseCase.execute()
        }
    }

    func setDefault(id: UUID) {
        do {
            settings = try setDefaultConfigurationUseCase.execute(id: id, settings: settings)
            notifyObservers()
        } catch {
            settings = loadSettingsUseCase.execute()
        }
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

    private func notifyObservers() {
        for continuation in continuations.values {
            continuation.yield(settings)
        }
    }
}
