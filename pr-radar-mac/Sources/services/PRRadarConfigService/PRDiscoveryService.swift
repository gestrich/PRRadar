import Foundation
import PRRadarModels

public enum PRDiscoveryService {
    public static func discoverPRs(outputDir: String) -> [PRMetadata] {
        let fileManager = FileManager.default
        let expandedPath = NSString(string: outputDir).expandingTildeInPath

        guard fileManager.fileExists(atPath: expandedPath),
              let contents = try? fileManager.contentsOfDirectory(atPath: expandedPath)
        else {
            return []
        }

        let prs: [PRMetadata] = contents.compactMap { dirName in
            guard let prNumber = Int(dirName) else { return nil }

            let ghPRPath = "\(expandedPath)/\(dirName)/\(PRRadarPhase.pullRequest.rawValue)/gh-pr.json"

            guard fileManager.fileExists(atPath: ghPRPath),
                  let data = fileManager.contents(atPath: ghPRPath),
                  let metadata = try? JSONDecoder().decode(PRMetadata.self, from: data)
            else {
                return PRMetadata.fallback(number: prNumber)
            }

            return metadata
        }

        return prs.sorted { $0.number > $1.number }
    }
}
