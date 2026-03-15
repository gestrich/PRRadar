import Foundation
import Testing
@testable import PRRadarCLIService

@Suite("GitHubAppTokenService")
struct GitHubAppTokenServiceTests {

    private let service = GitHubAppTokenService()

    // Test RSA private key (2048-bit PKCS#8, generated for testing only — not used anywhere real)
    private let testPrivateKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC5NNMRB/YPrdhW
    E4BDAMW9FJTTdToXfkaLBuDKIe5zK9NbW7YSRUr7+FoDBs6Wu0ZLzx6b+5UyWsa6
    cnBUTBVPa9xx+/Xbt1jS0mPBj5VOdnw2lvek75JvK8z79/yJOICRTSYq0nXipOSu
    oOQAukn9SACIy5vk1hDYT7Y05LSZjIn+qGOXG8oSZh4JLP5QmVX2NQim0HM14OWr
    2s0fxoNPPEWTUispkvC9X9F1OPYgoZKvlZ1s3G+0VTc6Ckst+tqwm5YDE/GL+V+0
    I09iOKsR30GqTpbuvgM+l6gCiMdHKsjqPNXS6VoWLrfTd4jJHo8AYD6F+WqmFjsW
    11HtcJc7AgMBAAECggEAAxCVN5BuqXbCgDYlZrZyDz1ycwdbFT1xNGbCPIYQOJau
    kjHz0tyTr5S+BJPNwl/J+4IrawBgSSuIY1h2dGan6Z8K0FYPjPm9PgveO7tBCMHc
    L1kTMwcF4NIUO80wQCMPuZfRvF6sNbpt0Ff4PezXQZo57AmWhFRohfPXu4tXU70g
    6da2OebfDSLYwZAos9rpAs8o2CRS5p3wPoi6oPQx7KGd67EsHPaFVMTgarvZB2Em
    fRvC9p2HGgwXz3Mk52vIuzJOv7R2rYnt4PsfoE3epD3sBDUDKsu7+qh2L3PuP+tn
    i9OxphypNHB8PmdZzcnDxbzfMnLw+OMTg3n7PIoUJQKBgQDl9Gf5fG8hasu4ZLzI
    rvBOKafIJGH6QTvFDXiVorChUOaHMW/j1NJ37DtVuwt2Rj7amoMgr16bN3RFjRu5
    f02NUd3+CiTQVTkLPGZHV+rJ0ObUFHpPWM2bpgj7fa9kEskZDDTgzOsdp9ctRckB
    axogXRcLFnzb8c8zbZpQZENn7QKBgQDOLu2pk2SONweY4yFsRkftErzH0KTBM7WQ
    3lxG6C1mGz3j14jcP7YiWlvLQE/IgP9A7qeJwI/0dJIiw7jIjKQPaR4nBJGP7CIT
    VpKEOLCQJKEG/VT1XcgXt5zBjEHpUX9wFAfYRUzilse9zaFCwsvD2kCZsF5cdyDQ
    DtxKtSBGxwKBgQCPM0B8kQzzlnn+/lzB7I8hXbdqX53UJkN+VwE8ze+IxcSJdDPl
    gWb/31Cj9rMQmHYT1BzMgek8Z7A0j8cwISK+WrkPtmlug2Pep2JaE1nXDAxzDb2N
    JBQGVcNKOd67RyeMPZnAVFwmP5s0Sjz+cR/3/4CWGw7uOQt7T0nFvmprkQKBgHJM
    q63lKsp4ETsdNssaTwdK6uJudNcx/kZ4LnmUfo5rLa0gMBvBKgvzQY30cgY6FMb/
    RltkJ6mh8d1Z2Rc8eDqe0Hta2gMKKX3E8WZhMuhFlgsU50M6oREc1caqJWPdrSMJ
    x6uKB2xZoBNFak9jQ6ioVkWc80KZO9R7WH4F2QXDAoGBAIH67KOKOaEGCMy1mlNI
    CiX7BZdbRYUjuSdpiI8ZTfn8TdIVs11zYUa1PYi9EuoTM8Eda6fLCWMuEVkBZ+ep
    En+kV/QjxrlWR+q0EG7tNXffOCmpWbttVyo1EPJd1dqwp51GyzpdbJ9LDiVs0lO8
    H8NpHEeytkQqUhcYVf/ur6jL
    -----END PRIVATE KEY-----
    """

    @Test("JWT has three base64url-encoded segments")
    func jwtStructure() throws {
        // Arrange / Act
        let jwt = try service.createJWT(appId: "12345", privateKeyPEM: testPrivateKeyPEM)

        // Assert
        let parts = jwt.split(separator: ".")
        #expect(parts.count == 3)
    }

    @Test("JWT header contains RS256 algorithm")
    func jwtHeader() throws {
        // Arrange / Act
        let jwt = try service.createJWT(appId: "12345", privateKeyPEM: testPrivateKeyPEM)

        // Assert
        let headerB64 = String(jwt.split(separator: ".")[0])
        let headerData = try base64URLDecode(headerB64)
        let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        #expect(header?["alg"] as? String == "RS256")
        #expect(header?["typ"] as? String == "JWT")
    }

    @Test("JWT payload contains correct issuer and timestamps")
    func jwtPayload() throws {
        // Arrange
        let fixedDate = Date(timeIntervalSince1970: 1700000000)

        // Act
        let jwt = try service.createJWT(appId: "99999", privateKeyPEM: testPrivateKeyPEM, now: fixedDate)

        // Assert
        let payloadB64 = String(jwt.split(separator: ".")[1])
        let payloadData = try base64URLDecode(payloadB64)
        let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        #expect(payload?["iss"] as? String == "99999")
        #expect(payload?["iat"] as? Int == 1700000000 - 60)
        #expect(payload?["exp"] as? Int == 1700000000 + 600)
    }

    @Test("JWT contains only base64url-safe characters")
    func jwtBase64URLSafe() throws {
        // Arrange / Act
        let jwt = try service.createJWT(appId: "12345", privateKeyPEM: testPrivateKeyPEM)

        // Assert
        for part in jwt.split(separator: ".") {
            #expect(!part.contains("+"))
            #expect(!part.contains("/"))
            #expect(!part.contains("="))
        }
    }

    @Test("Invalid PEM throws invalidPrivateKey")
    func invalidPEMThrows() {
        // Arrange / Act / Assert
        #expect(throws: GitHubAppTokenError.self) {
            _ = try service.createJWT(appId: "12345", privateKeyPEM: "not-a-pem")
        }
    }

    // MARK: - Helpers

    private func base64URLDecode(_ string: String) throws -> Data {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else {
            throw DecodingError("Invalid base64")
        }
        return data
    }
}

private struct DecodingError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
