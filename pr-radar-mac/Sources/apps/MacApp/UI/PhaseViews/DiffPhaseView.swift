import PRRadarModels
import SwiftUI

struct DiffPhaseView: View {

    let fullDiff: GitDiff
    let effectiveDiff: GitDiff?
    @State private var selectedTab = 0
    @State private var selectedFile: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Full Diff").tag(0)
                if effectiveDiff != nil {
                    Text("Effective Diff").tag(1)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            let activeDiff = selectedTab == 0 ? fullDiff : (effectiveDiff ?? fullDiff)

            PhaseSummaryBar(items: [
                .init(label: "Files:", value: "\(activeDiff.changedFiles.count)"),
                .init(label: "Hunks:", value: "\(activeDiff.hunks.count)"),
            ])
            .padding(8)

            HSplitView {
                fileList(for: activeDiff)
                    .frame(minWidth: 180, idealWidth: 220)

                diffContent(for: activeDiff)
            }
        }
    }

    @ViewBuilder
    private func fileList(for diff: GitDiff) -> some View {
        List(selection: $selectedFile) {
            Section("Changed Files") {
                ForEach(diff.changedFiles, id: \.self) { file in
                    let hunkCount = diff.getHunks(byFilePath: file).count
                    HStack {
                        Text(URL(fileURLWithPath: file).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Text("\(hunkCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(file)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func diffContent(for diff: GitDiff) -> some View {
        let filtered: GitDiff = {
            if let file = selectedFile {
                let hunks = diff.getHunks(byFilePath: file)
                let raw = hunks.map(\.content).joined(separator: "\n")
                return GitDiff(rawContent: raw, hunks: hunks, commitHash: diff.commitHash)
            }
            return diff
        }()

        RichDiffContentView(diff: filtered)
    }
}
