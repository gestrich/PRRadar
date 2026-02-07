import Foundation

public final class SettingsService: Sendable {
    private let fileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("PRRadar")
        self.fileURL = appSupport.appendingPathComponent("settings.json")
    }

    public func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL)
    }

    public func addConfiguration(_ config: RepoConfiguration, to settings: inout AppSettings) {
        var config = config
        if settings.configurations.isEmpty {
            config.isDefault = true
        }
        settings.configurations.append(config)
    }

    public func removeConfiguration(id: UUID, from settings: inout AppSettings) {
        let wasDefault = settings.configurations.first(where: { $0.id == id })?.isDefault ?? false
        settings.configurations.removeAll(where: { $0.id == id })
        if wasDefault, let first = settings.configurations.first {
            let idx = settings.configurations.firstIndex(of: first)!
            settings.configurations[idx].isDefault = true
        }
    }

    public func setDefault(id: UUID, in settings: inout AppSettings) {
        for i in settings.configurations.indices {
            settings.configurations[i].isDefault = (settings.configurations[i].id == id)
        }
    }
}
