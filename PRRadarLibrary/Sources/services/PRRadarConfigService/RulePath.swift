import Foundation

public struct RulePath: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var path: String
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDefault = isDefault
    }
}
