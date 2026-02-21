import PRRadarConfigService
import PRRadarModels
import SwiftUI

struct AITranscriptView: View {

    @Environment(PRModel.self) private var prModel

    let transcriptsByPhase: [PRRadarPhase: [ClaudeAgentTranscript]]
    var isStreaming: Bool = false

    @State private var selectedPhase: PRRadarPhase = .prepare
    @State private var selectedTranscriptId: String?

    private var phases: [PRRadarPhase] {
        [.prepare, .analyze].filter { transcriptsByPhase[$0] != nil }
    }

    private var transcripts: [ClaudeAgentTranscript] {
        transcriptsByPhase[selectedPhase] ?? []
    }

    private var selectedTranscript: ClaudeAgentTranscript? {
        if let id = selectedTranscriptId {
            return transcripts.first { $0.identifier == id }
        }
        return transcripts.first
    }

    // MARK: - File Grouping

    private struct FileGroup: Identifiable {
        let filePath: String
        let transcripts: [ClaudeAgentTranscript]
        var id: String { filePath }

        var displayName: String {
            if filePath.isEmpty { return "Unknown File" }
            return (filePath as NSString).lastPathComponent
        }
    }

    private var fileGroups: [FileGroup] {
        var grouped: [String: [ClaudeAgentTranscript]] = [:]
        var order: [String] = []
        for transcript in transcripts {
            let key = transcript.filePath
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(transcript)
        }
        return order.map { FileGroup(filePath: $0, transcripts: grouped[$0]!) }
    }

    private var useFileGrouping: Bool {
        selectedPhase == .analyze
    }

    // MARK: - Row Label

    private func rowLabel(for transcript: ClaudeAgentTranscript) -> String {
        if useFileGrouping, !transcript.ruleName.isEmpty {
            return transcript.ruleName
        }
        return transcript.identifier
    }

    var body: some View {
        if phases.isEmpty {
            ContentUnavailableView(
                "No AI Transcripts",
                systemImage: "text.bubble",
                description: Text("Run Focus Areas or Evaluations to generate AI transcripts.")
            )
        } else {
            VStack(spacing: 0) {
                if isStreaming {
                    streamingBanner
                    Divider()
                }
                toolbar
                Divider()
                HSplitView {
                    transcriptList
                        .frame(minWidth: 180, maxWidth: 250)
                    transcriptDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                if let first = phases.first {
                    selectedPhase = first
                    selectedTranscriptId = transcriptsByPhase[first]?.first?.identifier
                }
            }
            .onChange(of: transcripts.count) {
                if isStreaming, let last = transcripts.last {
                    selectedTranscriptId = last.identifier
                }
            }
        }
    }

    // MARK: - Streaming Banner

    @ViewBuilder
    private var streamingBanner: some View {
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

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Phase", selection: $selectedPhase) {
                ForEach(phases, id: \.self) { phase in
                    Text(phase.displayName)
                        .tag(phase)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            Text("\(transcripts.count) transcript\(transcripts.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: selectedPhase) {
            selectedTranscriptId = transcripts.first?.identifier
        }
    }

    // MARK: - Transcript List

    @ViewBuilder
    private var transcriptList: some View {
        if useFileGrouping {
            groupedTranscriptList
        } else {
            flatTranscriptList
        }
    }

    @ViewBuilder
    private var flatTranscriptList: some View {
        List(transcripts, id: \.identifier, selection: $selectedTranscriptId) { transcript in
            transcriptRow(transcript)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var groupedTranscriptList: some View {
        List(selection: $selectedTranscriptId) {
            ForEach(fileGroups) { group in
                Section {
                    ForEach(group.transcripts, id: \.identifier) { transcript in
                        transcriptRow(transcript)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text(group.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        if prModel.tasksInFlight.contains(where: { $0.focusArea.filePath == group.filePath }) {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .help(group.filePath)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func transcriptRow(_ transcript: ClaudeAgentTranscript) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rowLabel(for: transcript))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            if isStreaming {
                Text("\(transcript.events.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text(displayName(forModelId: transcript.model))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(String(format: "$%.4f", transcript.costUsd))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Transcript Detail

    @ViewBuilder
    private var transcriptDetail: some View {
        if let transcript = selectedTranscript {
            VStack(spacing: 0) {
                transcriptHeader(transcript)
                Divider()
                transcriptEvents(transcript)
            }
        } else {
            ContentUnavailableView(
                "Select a Transcript",
                systemImage: "text.bubble",
                description: Text("Choose a transcript from the sidebar.")
            )
        }
    }

    @ViewBuilder
    private func transcriptHeader(_ transcript: ClaudeAgentTranscript) -> some View {
        HStack(spacing: 16) {
            if isStreaming {
                headerItem("Events", "\(transcript.events.count)")
                headerItem("Started", transcript.startedAt)
            } else {
                headerItem("Model", displayName(forModelId: transcript.model))
                headerItem("Duration", "\(transcript.durationMs)ms")
                headerItem("Cost", String(format: "$%.4f", transcript.costUsd))
                headerItem("Started", transcript.startedAt)
            }
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func headerItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func transcriptEvents(_ transcript: ClaudeAgentTranscript) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let prompt = transcript.prompt {
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

                    ForEach(Array(transcript.events.enumerated()), id: \.offset) { _, event in
                        transcriptEventView(event)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("transcript-bottom")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: transcript.events.count) {
                if isStreaming {
                    withAnimation {
                        proxy.scrollTo("transcript-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transcriptEventView(_ event: ClaudeAgentTranscriptEvent) -> some View {
        switch event.type {
        case .text:
            if let content = event.content {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        case .toolUse:
            DisclosureGroup {
                if let content = event.content {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } label: {
                Label(event.toolName ?? "Tool", systemImage: "wrench")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
        case .result:
            if let content = event.content {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Result")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}
