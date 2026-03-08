import PRRadarModels
import SwiftUI

struct TasksPagerView: View {

    @Environment(PRModel.self) private var prModel

    let fileName: String
    let tasks: [RuleRequest]
    let onDismiss: () -> Void
    var onViewOutput: ((String) -> Void)?

    @State private var currentIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    currentIndex = max(0, currentIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex == 0)

                Text("\(currentIndex + 1) of \(tasks.count)")
                    .monospacedDigit()

                Button {
                    currentIndex = min(tasks.count - 1, currentIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentIndex >= tasks.count - 1)

                Text("— \(fileName)")
                    .foregroundStyle(.secondary)

                Spacer()

                if !tasks.isEmpty {
                    evaluationStatusView(for: tasks[currentIndex].taskId)
                }

                Button("Done") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if !tasks.isEmpty {
                ScrollView {
                    TaskRowView(task: tasks[currentIndex])
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func evaluationStatusView(for taskId: String) -> some View {
        let state = prModel.evaluationState(forTaskId: taskId)
        HStack(spacing: 6) {
            switch state {
            case .none:
                EmptyView()
            case .queued:
                Text("Queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .streaming:
                ProgressView()
                    .controlSize(.mini)
                Text("Evaluating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .complete(let hasOutput):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

                if hasOutput, let onViewOutput {
                    Button {
                        onViewOutput(taskId)
                    } label: {
                        Label("View Output", systemImage: "text.bubble")
                            .font(.caption)
                    }
                }
            }
        }
    }
}
