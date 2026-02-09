import PRRadarModels
import SwiftUI

struct ViolationCard: View {

    let violation: ViolationRecord
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SeverityBadge(score: violation.score)

                Text(violation.ruleName)
                    .font(.headline)

                Spacer()

                Text(fileLocation)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                Text(violation.comment)
                    .font(.body)
                    .padding(.top, 4)

                if let method = violation.methodName {
                    HStack(spacing: 4) {
                        Text("Method:")
                            .foregroundStyle(.secondary)
                        Text(method)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .font(.caption)
                }

                if let link = violation.documentationLink {
                    HStack(spacing: 4) {
                        Text("Docs:")
                            .foregroundStyle(.secondary)
                        Text(link)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    private var fileLocation: String {
        if let line = violation.lineNumber {
            return "\(violation.filePath):\(line)"
        }
        return violation.filePath
    }
}
