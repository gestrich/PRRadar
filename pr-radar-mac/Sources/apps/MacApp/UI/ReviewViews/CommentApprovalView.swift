import AppKit
import PRRadarModels
import SwiftUI

struct CommentApprovalView: View {

    let comments: [PRComment]
    let posted: Bool
    let prModel: PRModel
    var onPost: ((_ dryRun: Bool) -> Void)?

    @State private var approvedIds: Set<String> = []
    @State private var selectedComment: PRComment?
    @State private var editedComments: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                commentsList
                    .frame(minWidth: 280, idealWidth: 320)
                detailPanel
            }
        }
        .onAppear {
            approvedIds = Set(comments.map(\.id))
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            Text("\(approvedIds.count) of \(comments.count) comments approved")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if !posted {
                Button("Select All") {
                    approvedIds = Set(comments.map(\.id))
                }

                Button("Deselect All") {
                    approvedIds.removeAll()
                }

                Button("Post Approved (\(approvedIds.count))") {
                    onPost?(false)
                }
                .disabled(approvedIds.isEmpty)
                .buttonStyle(.borderedProminent)
            } else {
                Label("Comments posted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .bold()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Comments List

    @ViewBuilder
    private var commentsList: some View {
        if comments.isEmpty {
            ContentUnavailableView(
                "No Violations",
                systemImage: "checkmark.circle",
                description: Text("No rule violations were found.")
            )
        } else {
            List(selection: Binding(
                get: { selectedComment?.id },
                set: { id in selectedComment = comments.first { $0.id == id } }
            )) {
                ForEach(comments) { comment in
                    commentRow(comment)
                        .tag(comment.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: PRComment) -> some View {
        HStack(spacing: 8) {
            if !posted {
                Toggle("", isOn: Binding(
                    get: { approvedIds.contains(comment.id) },
                    set: { isOn in
                        if isOn { approvedIds.insert(comment.id) }
                        else { approvedIds.remove(comment.id) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SeverityBadge(score: comment.score)
                    Text(comment.ruleName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Text(fileLocation(comment))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(comment.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let comment = selectedComment {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ruleInfoSection(comment)
                    Divider()
                    commentSection(comment)
                    Divider()
                    codeContextSection(comment)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Select a Comment",
                systemImage: "text.bubble",
                description: Text("Select a violation from the list to review its details and code context.")
            )
        }
    }

    // MARK: - Rule Info

    @ViewBuilder
    private func ruleInfoSection(_ comment: PRComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SeverityBadge(score: comment.score)
                Text(comment.ruleName)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Text(fileLocation(comment))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            if let cost = comment.costUsd {
                HStack(spacing: 4) {
                    Text("Cost:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.4f", cost))
                }
                .font(.caption)
            }

            if let link = comment.documentationLink, let url = URL(string: link) {
                HStack(spacing: 4) {
                    Image(systemName: "book")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Link("Documentation", destination: url)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Comment Section

    @ViewBuilder
    private func commentSection(_ comment: PRComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed Comment")
                .font(.headline)

            if posted {
                Text(comment.comment)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                TextEditor(text: Binding(
                    get: { editedComments[comment.id] ?? comment.comment },
                    set: { editedComments[comment.id] = $0 }
                ))
                .font(.body)
                .frame(minHeight: 80)
                .border(Color(nsColor: .separatorColor))
            }
        }
    }

    // MARK: - Code Context

    @ViewBuilder
    private func codeContextSection(_ comment: PRComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code Context")
                .font(.headline)

            if let content = prModel.readFileFromRepo(comment.filePath) {
                CodeView(
                    fileContent: content,
                    fileName: comment.filePath,
                    highlightedLine: comment.lineNumber
                )
                .frame(minHeight: 300, maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            } else {
                ContentUnavailableView(
                    "File Not Available",
                    systemImage: "doc.questionmark",
                    description: Text("Could not read \(comment.filePath) from the repository.")
                )
                .frame(height: 120)
            }
        }
    }

    // MARK: - Helpers

    private func fileLocation(_ comment: PRComment) -> String {
        if let line = comment.lineNumber {
            return "\(comment.filePath):\(line)"
        }
        return comment.filePath
    }
}
