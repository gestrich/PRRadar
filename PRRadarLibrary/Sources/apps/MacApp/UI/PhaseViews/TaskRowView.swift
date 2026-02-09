import PRRadarModels
import SwiftUI

struct TaskRowView: View {

    let task: EvaluationTaskOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.rule.name)
                    .font(.headline)
                Spacer()
                Text(task.rule.category)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            Text(task.rule.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(task.focusArea.description)
                    .font(.caption)
                Text("Lines \(task.focusArea.startLine)-\(task.focusArea.endLine)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.focusArea.focusType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            if !task.rule.content.isEmpty {
                Text(task.rule.content)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let link = task.rule.documentationLink, let url = URL(string: link) {
                HStack(spacing: 4) {
                    Text("Docs:")
                        .foregroundStyle(.secondary)
                    Link(link, destination: url)
                }
                .font(.caption)
            }
        }
    }
}
