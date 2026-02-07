import SwiftUI

struct ContentView: View {

    @Environment(PRReviewModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            Text("Phase 1: Fetch PR Diff")
                .font(.title2)
                .bold()

            HStack {
                Text("Repo Path")
                    .frame(width: 80, alignment: .trailing)
                TextField("/path/to/repo", text: $model.repoPath)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("PR Number")
                    .frame(width: 80, alignment: .trailing)
                TextField("123", text: $model.prNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Spacer()
            }

            HStack {
                Text("Output Dir")
                    .frame(width: 80, alignment: .trailing)
                TextField("~/Desktop/code-reviews", text: $model.outputDir)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Run Phase 1") {
                    Task { await model.runDiff() }
                }
                .disabled(model.isRunning || model.repoPath.isEmpty || model.prNumber.isEmpty)

                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            switch model.state {
            case .idle:
                EmptyView()

            case .running(let logs):
                logsSection(logs)

            case .completed(let files, let logs):
                if !files.isEmpty {
                    Divider()
                    Text("Output Files")
                        .font(.headline)
                    List(files, id: \.self) { file in
                        Text(file)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                logsSection(logs)

            case .failed(let error, let logs):
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                logsSection(logs)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }

    @ViewBuilder
    private func logsSection(_ logs: String) -> some View {
        if !logs.isEmpty {
            Divider()
            Text("Logs")
                .font(.headline)
            ScrollView {
                Text(logs)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
        }
    }
}

#Preview {
    ContentView()
        .environment(PRReviewModel(venvBinPath: "", environment: [:]))
}
