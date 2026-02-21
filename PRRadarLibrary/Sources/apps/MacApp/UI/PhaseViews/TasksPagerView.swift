import PRRadarModels
import SwiftUI

struct TasksPagerView: View {

    let fileName: String
    let tasks: [RuleRequest]
    let onDismiss: () -> Void

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
}
