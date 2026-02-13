import Foundation
import PRRadarConfigService
import PRRadarModels

public struct DeletePRDataUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String) async throws -> PRMetadata {
        let prDir = "\(config.absoluteOutputDir)/\(prNumber)"

        if FileManager.default.fileExists(atPath: prDir) {
            try FileManager.default.removeItem(atPath: prDir)
        }

        let syncUseCase = SyncPRUseCase(config: config)
        for try await progress in syncUseCase.execute(prNumber: prNumber) {
            switch progress {
            case .failed(let error, _):
                throw DeletePRDataError.syncFailed(error)
            default:
                break
            }
        }

        let discovered = PRDiscoveryService.discoverPRs(outputDir: config.absoluteOutputDir)
        if let metadata = discovered.first(where: { $0.number == Int(prNumber) }) {
            return metadata
        }

        guard let num = Int(prNumber) else {
            throw DeletePRDataError.invalidPRNumber(prNumber)
        }
        return PRMetadata.fallback(number: num)
    }
}

public enum DeletePRDataError: LocalizedError {
    case syncFailed(String)
    case invalidPRNumber(String)

    public var errorDescription: String? {
        switch self {
        case .syncFailed(let message):
            "Failed to re-fetch PR data: \(message)"
        case .invalidPRNumber(let number):
            "Invalid PR number: \(number)"
        }
    }
}
