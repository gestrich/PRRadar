import SwiftUI

/// A modal sheet for composing pull request details.
///
/// Simplified from RefactorApp's version to remove GithubService/OctoKit dependency.
/// Instead of directly creating the PR, this view collects the inputs and calls
/// `onCreate` with the composed PR details, letting the caller handle submission.
public struct CreatePullRequestSheet: View {
    let owner: String
    let repo: String
    let headBranch: String
    let baseBranch: String
    let defaultTitle: String
    let defaultBody: String
    let onCreate: (PullRequestDraft) async throws -> String  // Returns PR URL
    let onCancel: () -> Void

    @State private var prTitle: String = ""
    @State private var prBody: String = ""
    @State private var isDraft: Bool = true
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    public init(
        owner: String,
        repo: String,
        headBranch: String,
        baseBranch: String = "main",
        defaultTitle: String = "",
        defaultBody: String = "",
        onCreate: @escaping (PullRequestDraft) async throws -> String,
        onCancel: @escaping () -> Void
    ) {
        self.owner = owner
        self.repo = repo
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.defaultTitle = defaultTitle
        self.defaultBody = defaultBody
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text("Create Pull Request")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repository")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(owner)/\(repo)")
                        .font(.body)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Branches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(headBranch) → \(baseBranch)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }

                Divider()

                Text("Title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("PR Title", text: $prTitle)
                    .textFieldStyle(.roundedBorder)

                Text("Description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $prBody)
                    .font(.body)
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Toggle("Create as Draft", isOn: $isDraft)
                    .help("Draft PRs are not ready for review")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .disabled(isCreating)

                Button(isCreating ? "Creating..." : "Create PR") {
                    createPullRequest()
                }
                .buttonStyle(.borderedProminent)
                .disabled(prTitle.isEmpty || isCreating)
            }
        }
        .padding()
        .frame(width: 600, height: 550)
        .onAppear {
            prTitle = defaultTitle
            prBody = defaultBody
        }
    }

    private func createPullRequest() {
        let draft = PullRequestDraft(
            title: prTitle,
            body: prBody,
            owner: owner,
            repo: repo,
            head: headBranch,
            base: baseBranch,
            isDraft: isDraft
        )

        Task { @MainActor in
            isCreating = true
            errorMessage = nil

            do {
                _ = try await onCreate(draft)
            } catch {
                errorMessage = "Failed to create PR: \(error.localizedDescription)"
                isCreating = false
            }
        }
    }
}

/// The data needed to create a pull request
public struct PullRequestDraft: Sendable {
    public let title: String
    public let body: String
    public let owner: String
    public let repo: String
    public let head: String
    public let base: String
    public let isDraft: Bool
}
