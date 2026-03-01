import Foundation

public protocol KeychainStoring: Sendable {
    func setString(_ string: String, forKey key: String) throws
    func string(forKey key: String) throws -> String
    func removeObject(forKey key: String) throws
    func allKeys() throws -> Set<String>
}

public enum KeychainStoreError: Error {
    case itemNotFound
    case readOnly
    case commandFailed(String)
}
