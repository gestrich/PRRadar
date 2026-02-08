import Foundation
@preconcurrency import OctoKit
import PRRadarModels

// MARK: - Date Formatting

private func formatISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

// MARK: - PullRequest → GitHubPullRequest

extension OctoKit.PullRequest {
    func toGitHubPullRequest(files: [OctoKit.PullRequest.File]? = nil) -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: title ?? "",
            body: body,
            state: state?.rawValue,
            isDraft: draft,
            url: htmlURL?.absoluteString,
            baseRefName: base?.ref,
            headRefName: head?.ref,
            headRefOid: head?.sha,
            createdAt: createdAt.map { formatISO8601($0) },
            updatedAt: updatedAt.map { formatISO8601($0) },
            mergedAt: mergedAt.map { formatISO8601($0) },
            author: user.map { $0.toGitHubAuthor() },
            labels: labels?.compactMap { $0.toGitHubLabel() },
            files: files?.map { $0.toGitHubFile() }
        )
    }
}

// MARK: - User → GitHubAuthor

extension OctoKit.User {
    func toGitHubAuthor() -> GitHubAuthor {
        GitHubAuthor(
            login: login ?? "",
            id: String(id),
            name: name
        )
    }
}

// MARK: - Label → GitHubLabel

extension OctoKit.Label {
    func toGitHubLabel() -> GitHubLabel? {
        guard let name else { return nil }
        return GitHubLabel(
            id: name,
            name: name,
            color: color
        )
    }
}

// MARK: - PullRequest.File → GitHubFile

extension OctoKit.PullRequest.File {
    func toGitHubFile() -> GitHubFile {
        GitHubFile(
            path: filename,
            additions: additions,
            deletions: deletions
        )
    }
}

// MARK: - Repository → GitHubRepository

extension OctoKit.Repository {
    func toGitHubRepository() -> GitHubRepository {
        GitHubRepository(
            name: name ?? "",
            url: htmlURL,
            owner: GitHubOwner(
                login: owner.login ?? "",
                id: String(owner.id)
            )
        )
    }
}
