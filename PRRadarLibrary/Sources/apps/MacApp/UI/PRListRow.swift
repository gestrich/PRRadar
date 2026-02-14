import PRRadarModels
import SwiftUI

struct PRListRow: View {

    let prModel: PRModel

    private var pr: PRMetadata { prModel.metadata }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(pr.displayNumber)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())

                stateIndicator

                if prModel.operationMode != .idle {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                analysisBadge

                postedCommentsBadge

                if let relative = relativeTimestamp {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(pr.title)
                .font(.body)
                .fontWeight(isFallback ? .regular : .semibold)
                .lineLimit(2)

            if !pr.headRefName.isEmpty {
                Text(pr.headRefName)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !pr.author.login.isEmpty {
                Text(pr.author.name.isEmpty ? pr.author.login : pr.author.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("prRow_\(pr.number)")
    }

    // MARK: - Analysis Badge

    @ViewBuilder
    private var analysisBadge: some View {
        switch prModel.analysisState {
        case .loading, .unavailable:
            EmptyView()
        case .loaded(let violationCount, _, _):
            if violationCount > 0 {
                Text("\(violationCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.orange, in: Capsule())
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Posted Comments Badge

    @ViewBuilder
    private var postedCommentsBadge: some View {
        switch prModel.analysisState {
        case .loaded(_, _, let postedCommentCount):
            Text("\(max(postedCommentCount, 1))")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.green, in: Capsule())
                .opacity(postedCommentCount > 0 ? 1 : 0)
        default:
            EmptyView()
        }
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        let state = PRState(rawValue: pr.state.uppercased()) ?? .open
        let (color, label): (Color, String) = {
            switch state {
            case .open:
                return (Color(red: 35/255, green: 134/255, blue: 54/255), "Open")
            case .merged:
                return (Color(red: 138/255, green: 86/255, blue: 221/255), "Merged")
            case .closed:
                return (Color(red: 218/255, green: 55/255, blue: 51/255), "Closed")
            case .draft:
                return (Color(red: 101/255, green: 108/255, blue: 118/255), "Draft")
            }
        }()
        
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var isFallback: Bool {
        pr.author.login.isEmpty && pr.headRefName.isEmpty && pr.state.isEmpty
    }

    private var relativeTimestamp: String? {
        guard !pr.createdAt.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: pr.createdAt)
            ?? ISO8601DateFormatter().date(from: pr.createdAt)
        else { return nil }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Open PR") {
    PRListRow(
        prModel: PRModel(
            metadata: PRMetadata(
                number: 1234,
                title: "Add three-pane navigation with config sidebar and PR list",
                author: .init(login: "gestrich", name: "Bill Gestrich"),
                state: "OPEN",
                headRefName: "feature/three-pane-nav",
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2 * 86400))
            ),
            config: .init(repoPath: "", outputDir: "", agentScriptPath: ""),
            repoConfig: .init(name: "Test", repoPath: "")
        )
    )
    .frame(width: 260)
    .padding()
}
