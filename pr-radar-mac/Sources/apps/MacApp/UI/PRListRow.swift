import PRRadarModels
import SwiftUI

struct PRListRow: View {

    let pr: PRMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("#\(pr.number)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())

                stateIndicator

                Spacer()

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
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        let uppercased = pr.state.uppercased()
        switch uppercased {
        case "OPEN":
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case "MERGED":
            Circle()
                .fill(.purple)
                .frame(width: 8, height: 8)
        case "CLOSED":
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        default:
            Circle()
                .fill(.gray.opacity(0.4))
                .frame(width: 8, height: 8)
        }
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
        pr: PRMetadata(
            number: 1234,
            title: "Add three-pane navigation with config sidebar and PR list",
            author: .init(login: "gestrich", name: "Bill Gestrich"),
            state: "OPEN",
            headRefName: "feature/three-pane-nav",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2 * 86400))
        )
    )
    .frame(width: 260)
    .padding()
}

#Preview("Fallback PR") {
    PRListRow(pr: .fallback(number: 567))
        .frame(width: 260)
        .padding()
}
