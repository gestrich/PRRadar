import PRRadarModels
import SwiftUI

struct TaskRowView: View {

    let task: EvaluationTaskOutput

    @State private var isExpanded = false

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

            DisclosureGroup("Rule Content", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.rule.content)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if let link = task.rule.documentationLink {
                        HStack(spacing: 4) {
                            Text("Docs:")
                                .foregroundStyle(.secondary)
                            Text(link)
                                .foregroundStyle(.blue)
                        }
                        .font(.caption)
                    }
                }
            }
            .font(.caption)
        }
    }
}
