import Foundation
import Valet

public protocol KeychainStoring: Sendable {
    func setString(_ string: String, forKey key: String) throws
    func string(forKey key: String) throws -> String
    func removeObject(forKey key: String) throws
    func allKeys() throws -> Set<String>
}

public struct ValetKeychainStore: KeychainStoring {
    private let valet: Valet

    public init(identifier: String, accessibility: Accessibility = .whenUnlocked) {
        self.valet = Valet.valet(
            with: Identifier(nonEmpty: identifier)!,
            accessibility: accessibility
        )
    }

    public func setString(_ string: String, forKey key: String) throws {
        try valet.setString(string, forKey: key)
    }

    public func string(forKey key: String) throws -> String {
        try valet.string(forKey: key)
    }

    public func removeObject(forKey key: String) throws {
        try valet.removeObject(forKey: key)
    }

    public func allKeys() throws -> Set<String> {
        try valet.allKeys()
    }
}
