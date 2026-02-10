import SwiftUI

struct AIOutputStreamView: View {

    let text: String
    var prompt: String = ""
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isRunning {
                runningBanner
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !prompt.isEmpty {
                            DisclosureGroup {
                                Text(prompt)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } label: {
                                Label("Prompt", systemImage: "text.bubble")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.blue)
                            }
                        }

                        Text(text.isEmpty ? "Waiting for AI output..." : text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(text.isEmpty ? .secondary : .primary)
                            .id("bottom")
                    }
                    .padding()
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
