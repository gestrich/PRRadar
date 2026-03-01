#if os(macOS)
import Foundation

public struct SecurityCLIKeychainStore: KeychainStoring {
    private let service: String

    public init(identifier: String) {
        self.service = identifier
    }

    public func setString(_ string: String, forKey key: String) throws {
        // -U = update if exists
        let result = run(
            "security", "add-generic-password",
            "-U", "-s", service, "-a", key, "-w", string
        )
        if result.status != 0 {
            throw KeychainStoreError.commandFailed(result.stderr)
        }
    }

    public func string(forKey key: String) throws -> String {
        let result = run("security", "find-generic-password", "-s", service, "-a", key, "-w")
        if result.status != 0 {
            throw KeychainStoreError.itemNotFound
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func removeObject(forKey key: String) throws {
        let result = run("security", "delete-generic-password", "-s", service, "-a", key)
        if result.status != 0 {
            if result.stderr.contains("could not be found") { return }
            throw KeychainStoreError.commandFailed(result.stderr)
        }
    }

    public func allKeys() throws -> Set<String> {
        let result = run("security", "dump-keychain")
        if result.status != 0 {
            throw KeychainStoreError.commandFailed(result.stderr)
        }
        return parseAccountKeys(from: result.stdout, service: service)
    }

    // MARK: - Private

    private func run(_ args: String...) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = Array(args.dropFirst())
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try? process.run()
        // Read pipe data before waitUntilExit to avoid deadlock when pipe buffer fills
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    /// Parse `security dump-keychain` output to find all account keys for our service.
    /// Lines of interest:  "svce"<blob>="com.gestrich.PRRadar"  and  "acct"<blob>="key"
    func parseAccountKeys(from dump: String, service: String) -> Set<String> {
        var keys = Set<String>()
        let lines = dump.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("class: \"genp\"") {
                var svce: String?
                var acct: String?
                var j = i + 1
                while j < lines.count {
                    let attrLine = lines[j].trimmingCharacters(in: .whitespaces)
                    if attrLine.hasPrefix("class:") || attrLine.hasPrefix("keychain:") { break }
                    if let value = extractBlobValue(attrLine, key: "svce") { svce = value }
                    if let value = extractBlobValue(attrLine, key: "acct") { acct = value }
                    j += 1
                }
                if svce == service, let acct, !acct.isEmpty {
                    keys.insert(acct)
                }
                i = j
            } else {
                i += 1
            }
        }
        return keys
    }

    private func extractBlobValue(_ line: String, key: String) -> String? {
        let prefix = "\"\(key)\"<blob>=\""
        guard line.hasPrefix(prefix), line.hasSuffix("\"") else { return nil }
        let start = line.index(line.startIndex, offsetBy: prefix.count)
        let end = line.index(before: line.endIndex)
        guard start < end else { return nil }
        return String(line[start..<end])
    }
}
#endif
