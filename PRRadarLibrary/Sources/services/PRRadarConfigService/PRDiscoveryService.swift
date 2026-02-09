import Foundation
import PRRadarModels

public enum PRDiscoveryService {
    public static func discoverPRs(outputDir: String, repoSlug: String? = nil) -> [PRMetadata] {
        let fileManager = FileManager.default
        let expandedPath = NSString(string: outputDir).expandingTildeInPath

        guard fileManager.fileExists(atPath: expandedPath),
              let contents = try? fileManager.contentsOfDirectory(atPath: expandedPath)
        else {
            return []
        }

        let prs: [PRMetadata] = contents.compactMap { dirName in
            guard let prNumber = Int(dirName) else { return nil }

            let phaseDir = "\(expandedPath)/\(dirName)/\(PRRadarPhase.pullRequest.rawValue)"
            let ghPRPath = "\(phaseDir)/gh-pr.json"

            guard fileManager.fileExists(atPath: ghPRPath),
                  let data = fileManager.contents(atPath: ghPRPath)
            else {
                return repoSlug == nil ? PRMetadata.fallback(number: prNumber) : nil
            }
            
            let metadata: PRMetadata
            if let ghPR = try? JSONDecoder().decode(GitHubPullRequest.self, from: data) {
                metadata = PRMetadata(
                    number: ghPR.number,
                    title: ghPR.title,
                    body: ghPR.body,
                    author: PRMetadata.Author(
                        login: ghPR.author?.login ?? "",
                        name: ghPR.author?.name ?? ""
                    ),
                    state: ghPR.enhancedState.rawValue,
                    headRefName: ghPR.headRefName ?? "",
                    createdAt: ghPR.createdAt ?? "",
                    updatedAt: ghPR.updatedAt,
                    url: ghPR.url
                )
            } else if let prMeta = try? JSONDecoder().decode(PRMetadata.self, from: data) {
                metadata = prMeta
            } else {
                return repoSlug == nil ? PRMetadata.fallback(number: prNumber) : nil
            }

            if let repoSlug {
                let ghRepoPath = "\(phaseDir)/gh-repo.json"
                guard let repoData = fileManager.contents(atPath: ghRepoPath),
                      let repoJSON = try? JSONSerialization.jsonObject(with: repoData) as? [String: Any],
                      let owner = (repoJSON["owner"] as? [String: Any])?["login"] as? String,
                      let name = repoJSON["name"] as? String,
                      "\(owner)/\(name)" == repoSlug
                else {
                    return nil
                }
            }

            return metadata
        }

        return prs.sorted { $0.number > $1.number }
    }

    public static func repoSlug(fromRepoPath repoPath: String) -> String? {
        let gitConfigPath = "\(repoPath)/.git/config"
        guard let content = try? String(contentsOfFile: gitConfigPath, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)
        var inOriginSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[remote \"origin\"]" {
                inOriginSection = true
                continue
            }
            if trimmed.hasPrefix("[") {
                inOriginSection = false
                continue
            }
            if inOriginSection, trimmed.hasPrefix("url = ") {
                let url = String(trimmed.dropFirst("url = ".count))
                return slugFromRemoteURL(url)
            }
        }
        return nil
    }

    private static func slugFromRemoteURL(_ remoteURL: String) -> String? {
        // HTTPS: https://github.com/owner/repo.git
        if let range = remoteURL.range(of: "github.com/") {
            var slug = String(remoteURL[range.upperBound...])
            if slug.hasSuffix(".git") { slug = String(slug.dropLast(4)) }
            return slug.isEmpty ? nil : slug
        }
        // SSH: git@github.com:owner/repo.git
        if let range = remoteURL.range(of: "github.com:") {
            var slug = String(remoteURL[range.upperBound...])
            if slug.hasSuffix(".git") { slug = String(slug.dropLast(4)) }
            return slug.isEmpty ? nil : slug
        }
        return nil
    }
}
