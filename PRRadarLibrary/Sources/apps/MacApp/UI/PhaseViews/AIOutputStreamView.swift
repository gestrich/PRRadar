import SwiftUI

struct AIOutputStreamView: View {

    let text: String
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isRunning {
                runningBanner
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "Waiting for AI output..." : text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .padding()
                        .id("bottom")
                }
                .onChange(of: text) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var runningBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("AI is running...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
