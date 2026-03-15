import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Security

public struct GitHubAppTokenService: Sendable {

    public init() {}

    public func generateInstallationToken(
        appId: String,
        installationId: String,
        privateKeyPEM: String
    ) async throws -> String {
        let jwt = try createJWT(appId: appId, privateKeyPEM: privateKeyPEM)
        return try await exchangeJWTForToken(jwt: jwt, installationId: installationId)
    }

    // MARK: - JWT Creation

    func createJWT(appId: String, privateKeyPEM: String, now: Date = Date()) throws -> String {
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let iat = Int(now.timeIntervalSince1970) - 60
        let exp = Int(now.timeIntervalSince1970) + 600
        let payload = #"{"iss":"\#(appId)","iat":\#(iat),"exp":\#(exp)}"#

        let headerB64 = base64URLEncode(Data(header.utf8))
        let payloadB64 = base64URLEncode(Data(payload.utf8))
        let signingInput = "\(headerB64).\(payloadB64)"

        let privateKey = try loadPrivateKey(pem: privateKeyPEM)
        let signatureData = try sign(data: Data(signingInput.utf8), with: privateKey)
        let signatureB64 = base64URLEncode(signatureData)

        return "\(signingInput).\(signatureB64)"
    }

    // MARK: - Token Exchange

    private struct InstallationTokenResponse: Decodable {
        let token: String
    }

    private func exchangeJWTForToken(jwt: String, installationId: String) async throws -> String {
        let urlString = "https://api.github.com/app/installations/\(installationId)/access_tokens"
        guard let url = URL(string: urlString) else {
            throw GitHubAppTokenError.tokenExchangeFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAppTokenError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw GitHubAppTokenError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let tokenResponse = try JSONDecoder().decode(InstallationTokenResponse.self, from: data)
        return tokenResponse.token
    }

    // MARK: - RSA Key Loading

    func loadPrivateKey(pem: String) throws -> SecKey {
        let derData = try extractDERFromPEM(pem)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            throw GitHubAppTokenError.invalidPrivateKey
        }
        return key
    }

    private func extractDERFromPEM(_ pem: String) throws -> Data {
        let lines = pem.components(separatedBy: "\n")
        let base64Lines = lines.filter { line in
            !line.hasPrefix("-----") && !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let base64String = base64Lines.joined()
        guard let derData = Data(base64Encoded: base64String) else {
            throw GitHubAppTokenError.invalidPrivateKey
        }

        // If this is PKCS#8 wrapped, strip the header to get raw PKCS#1 RSA key
        // PKCS#8 RSA key starts with: 30 82 ... 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 04 82 ...
        if derData.count > 26 {
            let bytes = [UInt8](derData)
            // Check for PKCS#8 OID for rsaEncryption (1.2.840.113549.1.1.1)
            let rsaOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
            if let range = bytes.firstRange(of: rsaOID) {
                // Skip past the OID, the NULL parameter (05 00), and the OCTET STRING tag+length
                var offset = range.upperBound
                if offset < bytes.count && bytes[offset] == 0x05 { offset += 2 } // NULL
                if offset < bytes.count && bytes[offset] == 0x04 { // OCTET STRING
                    offset += 1
                    // Parse length
                    if offset < bytes.count {
                        if bytes[offset] & 0x80 != 0 {
                            let lenBytes = Int(bytes[offset] & 0x7F)
                            offset += 1 + lenBytes
                        } else {
                            offset += 1
                        }
                    }
                    if offset < derData.count {
                        return Data(bytes[offset...])
                    }
                }
            }
        }

        return derData
    }

    // MARK: - Signing

    private func sign(data: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            throw GitHubAppTokenError.signingFailed
        }
        return signature as Data
    }

    // MARK: - Base64URL

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Errors

public enum GitHubAppTokenError: Error, LocalizedError {
    case invalidPrivateKey
    case signingFailed
    case tokenExchangeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Failed to load GitHub App private key. Ensure the PEM is a valid PKCS#8 or PKCS#1 RSA private key."
        case .signingFailed:
            return "Failed to sign JWT with the GitHub App private key."
        case .tokenExchangeFailed(let detail):
            return "Failed to exchange JWT for installation token: \(detail)"
        }
    }
}
