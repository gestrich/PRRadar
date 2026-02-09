import PRRadarModels
import SwiftUI

struct CommentsPhaseView: View {

    let comments: [PRComment]
    let cliOutput: String?
    let posted: Bool
    var onPost: ((_ dryRun: Bool) -> Void)?

    @State private var selectedIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            commentsList
        }
        .onAppear {
            selectedIds = Set(comments.map(\.id))
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            PhaseSummaryBar(items: [
                .init(label: "Comments:", value: "\(comments.count)"),
                .init(label: "Selected:", value: "\(selectedIds.count)"),
            ])

            Spacer()

            if !posted {
                Button("Select All") {
                    selectedIds = Set(comments.map(\.id))
                }

                Button("Deselect All") {
                    selectedIds.removeAll()
                }

                Button("Post Selected") {
                    onPost?(false)
                }
                .disabled(selectedIds.isEmpty)
                .buttonStyle(.borderedProminent)
            } else {
                Text("Comments posted")
                    .foregroundStyle(.green)
                    .bold()
            }
        }
        .padding()
    }

    // MARK: - Comments List

    @ViewBuilder
    private var commentsList: some View {
        if comments.isEmpty {
            ContentUnavailableView(
                "No Violations",
                systemImage: "checkmark.circle",
                description: Text("No violations to comment on.")
            )
        } else {
            List {
                ForEach(comments) { comment in
                    commentRow(comment)
                }

                if let output = cliOutput, !output.isEmpty {
                    Section("CLI Output") {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: PRComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !posted {
                Toggle("", isOn: Binding(
                    get: { selectedIds.contains(comment.id) },
                    set: { isOn in
                        if isOn {
                            selectedIds.insert(comment.id)
                        } else {
                            selectedIds.remove(comment.id)
                        }
                    }
                ))
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SeverityBadge(score: comment.score)

                    Text(comment.ruleName)
                        .font(.headline)

                    Spacer()

                    Text(fileLocation(comment))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(comment.comment)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func fileLocation(_ comment: PRComment) -> String {
        if let line = comment.lineNumber {
            return "\(comment.filePath):\(line)"
        }
        return comment.filePath
    }
}
