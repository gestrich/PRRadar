import SwiftUI
import PRRadarConfigService

struct ContentView: View {

    @Environment(PRReviewModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            Text("Phase 1: Fetch PR Diff")
                .font(.title2)
                .bold()

            HStack {
                Text("Config")
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { model.selectedConfiguration?.id },
                    set: { id in
                        if let id, let config = model.settings.configurations.first(where: { $0.id == id }) {
                            model.selectConfiguration(config)
                        }
                    }
                )) {
                    if model.settings.configurations.isEmpty {
                        Text("No configurations").tag(nil as UUID?)
                    }
                    ForEach(model.settings.configurations) { config in
                        Text(config.name).tag(config.id as UUID?)
                    }
                }
                .frame(maxWidth: 250)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Manage configurations")
            }

            if let selected = model.selectedConfiguration {
                HStack {
                    Text("Repo")
                        .frame(width: 80, alignment: .trailing)
                    Text(selected.repoPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
                Button("Run Phase 1") {
                    Task { await model.runDiff() }
                }
                .disabled(model.isRunning || model.selectedConfiguration == nil || model.prNumber.isEmpty)

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
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
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
