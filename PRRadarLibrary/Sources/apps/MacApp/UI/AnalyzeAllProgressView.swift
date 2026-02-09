import SwiftUI

struct AnalyzeAllProgressView: View {

    let model: AllPRsModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logContent
        }
        .frame(width: 700, height: 500)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Analyzing All PRs")
                    .font(.headline)

                if let progressText = model.analyzeAllState.progressText {
                    Text("Progress: \(progressText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if model.analyzeAllState.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding()
    }

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(logsText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("bottom")
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: logsText) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var logsText: String {
        switch model.analyzeAllState {
        case .idle:
            return ""
        case .running(let logs, _, _):
            return logs
        case .completed(let logs):
            return logs
        case .failed(_, let logs):
            return logs
        }
    }
}
