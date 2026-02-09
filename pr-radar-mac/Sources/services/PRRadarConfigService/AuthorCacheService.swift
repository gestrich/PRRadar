import Foundation
import PRRadarModels

public final class AuthorCacheService: Sendable {
    private let fileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("PRRadar")
        self.fileURL = appSupport.appendingPathComponent("author-cache.json")
    }

    public func load() -> AuthorCache {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AuthorCache()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(AuthorCache.self, from: data)
        } catch {
            return AuthorCache()
        }
    }

    public func save(_ cache: AuthorCache) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cache)
        try data.write(to: fileURL)
    }

    public func lookup(login: String) -> AuthorCacheEntry? {
        let cache = load()
        return cache.entries[login]
    }

    public func update(login: String, name: String) throws {
        var cache = load()
        let formatter = ISO8601DateFormatter()
        let entry = AuthorCacheEntry(
            login: login,
            name: name,
            fetchedAt: formatter.string(from: Date())
        )
        cache.entries[login] = entry
        try save(cache)
    }
}
