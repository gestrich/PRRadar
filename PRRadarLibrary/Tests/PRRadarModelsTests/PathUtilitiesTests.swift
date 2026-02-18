import Foundation
import Testing
@testable import EnvironmentSDK

@Suite("PathUtilities")
struct PathUtilitiesTests {

    // MARK: - resolve(_:relativeTo:)

    @Test("resolve returns basePath/path for relative path")
    func resolveRelativePath() {
        let result = PathUtilities.resolve("code-reviews", relativeTo: "/Users/bill/repo")
        #expect(result == "/Users/bill/repo/code-reviews")
    }

    @Test("resolve expands tilde and returns absolute path")
    func resolveTildePath() {
        let result = PathUtilities.resolve("~/shared-rules", relativeTo: "/Users/bill/repo")
        #expect(!result.contains("~"))
        #expect(result.hasSuffix("/shared-rules"))
        #expect(NSString(string: result).isAbsolutePath)
    }

    @Test("resolve returns absolute path unchanged")
    func resolveAbsolutePath() {
        let result = PathUtilities.resolve("/opt/company-rules", relativeTo: "/Users/bill/repo")
        #expect(result == "/opt/company-rules")
    }

    @Test("resolve handles nested relative path")
    func resolveNestedRelativePath() {
        let result = PathUtilities.resolve("output/reviews", relativeTo: "/repo")
        #expect(result == "/repo/output/reviews")
    }

    // MARK: - expandTilde(_:)

    @Test("expandTilde expands home directory")
    func expandTildeHome() {
        let result = PathUtilities.expandTilde("~/Documents")
        #expect(!result.contains("~"))
        #expect(result.hasSuffix("/Documents"))
        #expect(NSString(string: result).isAbsolutePath)
    }

    @Test("expandTilde returns absolute path unchanged")
    func expandTildeAbsolute() {
        let result = PathUtilities.expandTilde("/opt/rules")
        #expect(result == "/opt/rules")
    }

    @Test("expandTilde returns relative path unchanged")
    func expandTildeRelative() {
        let result = PathUtilities.expandTilde("code-reviews")
        #expect(result == "code-reviews")
    }
}
