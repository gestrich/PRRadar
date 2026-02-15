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
    private let listCredentialAccountsUseCase: ListCredentialAccountsUseCase
    private let saveCredentialsUseCase: SaveCredentialsUseCase
    private let removeCredentialsUseCase: RemoveCredentialsUseCase
    private let loadCredentialStatusUseCase: LoadCredentialStatusUseCase

    private var continuations: [UUID: AsyncStream<AppSettings>.Continuation] = [:]

    private(set) var settings: AppSettings {
        didSet {
            for continuation in continuations.values {
                continuation.yield(settings)
            }
        }
    }

    private(set) var credentialAccounts: [CredentialStatus] = []

    public init(
        loadSettingsUseCase: LoadSettingsUseCase,
        saveConfigurationUseCase: SaveConfigurationUseCase,
        removeConfigurationUseCase: RemoveConfigurationUseCase,
        setDefaultConfigurationUseCase: SetDefaultConfigurationUseCase,
        listCredentialAccountsUseCase: ListCredentialAccountsUseCase,
        saveCredentialsUseCase: SaveCredentialsUseCase,
        removeCredentialsUseCase: RemoveCredentialsUseCase,
        loadCredentialStatusUseCase: LoadCredentialStatusUseCase
    ) {
        self.loadSettingsUseCase = loadSettingsUseCase
        self.saveConfigurationUseCase = saveConfigurationUseCase
        self.removeConfigurationUseCase = removeConfigurationUseCase
        self.setDefaultConfigurationUseCase = setDefaultConfigurationUseCase
        self.listCredentialAccountsUseCase = listCredentialAccountsUseCase
        self.saveCredentialsUseCase = saveCredentialsUseCase
        self.removeCredentialsUseCase = removeCredentialsUseCase
        self.loadCredentialStatusUseCase = loadCredentialStatusUseCase
        self.settings = loadSettingsUseCase.execute()
    }

    public convenience init() {
        let service = SettingsService()
        self.init(
            loadSettingsUseCase: LoadSettingsUseCase(settingsService: service),
            saveConfigurationUseCase: SaveConfigurationUseCase(settingsService: service),
            removeConfigurationUseCase: RemoveConfigurationUseCase(settingsService: service),
            setDefaultConfigurationUseCase: SetDefaultConfigurationUseCase(settingsService: service),
            listCredentialAccountsUseCase: ListCredentialAccountsUseCase(settingsService: service),
            saveCredentialsUseCase: SaveCredentialsUseCase(settingsService: service),
            removeCredentialsUseCase: RemoveCredentialsUseCase(settingsService: service),
            loadCredentialStatusUseCase: LoadCredentialStatusUseCase(settingsService: service)
        )
    }

    // MARK: - CRUD

    func addConfiguration(_ config: RepositoryConfigurationJSON) throws {
        settings = try saveConfigurationUseCase.execute(config: config)
    }

    func updateConfiguration(_ config: RepositoryConfigurationJSON) throws {
        settings = try saveConfigurationUseCase.execute(config: config)
    }

    func removeConfiguration(id: UUID) throws {
        settings = try removeConfigurationUseCase.execute(id: id)
    }

    func setDefault(id: UUID) throws {
        settings = try setDefaultConfigurationUseCase.execute(id: id)
    }

    // MARK: - Credentials

    func refreshCredentialAccounts() {
        guard let accounts = try? listCredentialAccountsUseCase.execute() else {
            credentialAccounts = []
            return
        }
        credentialAccounts = accounts.map { loadCredentialStatusUseCase.execute(account: $0) }
    }

    func saveCredentials(account: String, githubToken: String?, anthropicKey: String?) throws {
        try saveCredentialsUseCase.execute(account: account, githubToken: githubToken, anthropicKey: anthropicKey)
        refreshCredentialAccounts()
    }

    func removeCredentials(account: String) throws {
        try removeCredentialsUseCase.execute(account: account)
        refreshCredentialAccounts()
    }

    func credentialStatus(for account: String) -> CredentialStatus {
        loadCredentialStatusUseCase.execute(account: account)
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
