import AppKit
import PRRadarModels
import SwiftUI

/// A reusable component for displaying change information with copy functionality
public struct ChangeInfoView: View {
    public let title: String
    public let authorName: String?
    public let authorEmail: String?
    public let commitDate: String?
    public let commitHash: String?
    public let commitMessage: String?
    public let lineNumber: Int?
    public let diff: GitDiff?

    @State private var showCopiedFeedback = false
    @State private var showingDiff = false

    public init(
        title: String,
        authorName: String? = nil,
        authorEmail: String? = nil,
        commitDate: String? = nil,
        commitHash: String? = nil,
        commitMessage: String? = nil,
        lineNumber: Int? = nil,
        diff: GitDiff? = nil
    ) {
        self.title = title
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.commitDate = commitDate
        self.commitHash = commitHash
        self.commitMessage = commitMessage
        self.lineNumber = lineNumber
        self.diff = diff
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if diff != nil {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: {
                    copyChangeInfo()
                    showCopiedFeedback = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        showCopiedFeedback = false
                    }
                }) {
                    Label(
                        showCopiedFeedback ? "Copied!" : "Copy",
                        systemImage: showCopiedFeedback ? "checkmark.circle" : "doc.on.doc"
                    )
                    .font(.caption)
                    .foregroundStyle(showCopiedFeedback ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy change information")
            }

            if let authorName = authorName ?? authorEmail {
                HStack(spacing: 4) {
                    Text("Author:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(authorName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            if let commitDate {
                HStack(spacing: 4) {
                    Text("Date:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(relativeTimeString(from: commitDate))
                        .font(.caption)
                        .foregroundStyle(isRecentChange(commitDate) ? .red : .primary)
                        .fontWeight(isRecentChange(commitDate) ? .medium : .regular)
                }
            }

            if let commitHash {
                HStack(spacing: 4) {
                    Text("Commit:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(commitHash.prefix(7)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }

            if let commitMessage, !commitMessage.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("Message:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(commitMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if diff != nil {
                showingDiff = true
            }
        }
        .sheet(isPresented: $showingDiff) {
            if let diff {
                SimpleDiffView(diff: diff, title: title)
            }
        }
    }

    private func copyChangeInfo() {
        var info = ""

        if let lineNumber {
            info += "Line \(lineNumber) "
        }

        if let authorName = authorName ?? authorEmail {
            info += "changed by \(authorName) "
        }

        if let commitDate,
           let date = parseCommitDate(commitDate) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            info += "on \(formatter.string(from: date)) "
        }

        if let commitHash {
            info += "in commit \(String(commitHash.prefix(7)))"
        }

        if let commitMessage, !commitMessage.isEmpty {
            info += "\n\nMessage: \(commitMessage)"
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info, forType: .string)
    }

    private func relativeTimeString(from dateString: String) -> String {
        guard let date = parseCommitDate(dateString) else {
            return dateString
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func parseCommitDate(_ dateString: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: dateString) {
            return date
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: dateString)
    }

    private func isRecentChange(_ dateString: String) -> Bool {
        guard let date = parseCommitDate(dateString) else { return false }

        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        return date > sixMonthsAgo
    }
}
