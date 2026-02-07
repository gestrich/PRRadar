import PRRadarModels
import SwiftUI

struct EffectiveDiffView: View {

    let fullDiff: GitDiff
    let effectiveDiff: GitDiff
    let moveReport: MoveReport?

    @State private var selectedTab = 1  // Default to effective diff
    @State private var selectedFile: String?
    @State private var selectedMoveIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                leftPanel
                    .frame(minWidth: 200, idealWidth: 240)

                diffContent
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                Text("Full Diff").tag(0)
                Text("Effective Diff").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            let activeDiff = selectedTab == 0 ? fullDiff : effectiveDiff
            Text("\(activeDiff.changedFiles.count) files, \(activeDiff.hunks.count) hunks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Left Panel

    @ViewBuilder
    private var leftPanel: some View {
        List {
            Section("Changed Files") {
                let activeDiff = selectedTab == 0 ? fullDiff : effectiveDiff
                ForEach(activeDiff.changedFiles, id: \.self) { file in
                    let hunkCount = activeDiff.getHunks(byFilePath: file).count
                    HStack {
                        Text(URL(fileURLWithPath: file).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Text("\(hunkCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFile = (selectedFile == file) ? nil : file
                        selectedMoveIndex = nil
                    }
                    .listRowBackground(
                        selectedFile == file
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            }

            if let report = moveReport, !report.moves.isEmpty {
                Section("Code Moves (\(report.moves.count))") {
                    ForEach(Array(report.moves.enumerated()), id: \.offset) { index, move in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(move.matchedLines) lines")
                                    .font(.caption)
                                    .bold()
                                Spacer()
                                Text(String(format: "%.0f%%", move.score * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(URL(fileURLWithPath: move.sourceFile).lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("→ \(URL(fileURLWithPath: move.targetFile).lastPathComponent)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMoveIndex = (selectedMoveIndex == index) ? nil : index
                            selectedFile = nil
                        }
                        .listRowBackground(
                            selectedMoveIndex == index
                                ? Color.orange.opacity(0.15)
                                : Color.clear
                        )
                    }
                }
            }

            if let report = moveReport {
                Section("Summary") {
                    LabeledContent("Moves Detected", value: "\(report.movesDetected)")
                        .font(.caption)
                    LabeledContent("Lines Moved", value: "\(report.totalLinesMoved)")
                        .font(.caption)
                    LabeledContent("Effective Changes", value: "\(report.totalLinesEffectivelyChanged)")
                        .font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Diff Content

    @ViewBuilder
    private var diffContent: some View {
        let activeDiff = selectedTab == 0 ? fullDiff : effectiveDiff

        let displayDiff: GitDiff = {
            if let file = selectedFile {
                let hunks = activeDiff.getHunks(byFilePath: file)
                let raw = hunks.map(\.content).joined(separator: "\n")
                return GitDiff(rawContent: raw, hunks: hunks, commitHash: activeDiff.commitHash)
            }
            if let moveIndex = selectedMoveIndex, let report = moveReport {
                let move = report.moves[moveIndex]
                let sourceHunks = activeDiff.getHunks(byFilePath: move.sourceFile)
                let targetHunks = activeDiff.getHunks(byFilePath: move.targetFile)
                let hunks = sourceHunks + targetHunks
                let raw = hunks.map(\.content).joined(separator: "\n")
                return GitDiff(rawContent: raw, hunks: hunks, commitHash: activeDiff.commitHash)
            }
            return activeDiff
        }()

        ScrollView {
            Text(displayDiff.rawContent)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
