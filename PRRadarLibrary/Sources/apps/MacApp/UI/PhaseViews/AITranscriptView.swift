import PRRadarConfigService
import PRRadarModels
import SwiftUI

struct AITranscriptView: View {

    let transcriptsByPhase: [PRRadarPhase: [BridgeTranscript]]

    @State private var selectedPhase: PRRadarPhase = .focusAreas
    @State private var selectedTranscriptId: String?

    private var phases: [PRRadarPhase] {
        [.focusAreas, .evaluations].filter { transcriptsByPhase[$0] != nil }
    }

    private var transcripts: [BridgeTranscript] {
        transcriptsByPhase[selectedPhase] ?? []
    }

    private var selectedTranscript: BridgeTranscript? {
        if let id = selectedTranscriptId {
            return transcripts.first { $0.identifier == id }
        }
        return transcripts.first
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
        }
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
        List(transcripts, id: \.identifier, selection: $selectedTranscriptId) { transcript in
            VStack(alignment: .leading, spacing: 2) {
                Text(transcript.identifier)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(displayName(forModelId: transcript.model))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(String(format: "$%.4f", transcript.costUsd))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
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
    private func transcriptHeader(_ transcript: BridgeTranscript) -> some View {
        HStack(spacing: 16) {
            headerItem("Model", displayName(forModelId: transcript.model))
            headerItem("Duration", "\(transcript.durationMs)ms")
            headerItem("Cost", String(format: "$%.4f", transcript.costUsd))
            headerItem("Started", transcript.startedAt)
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
    private func transcriptEvents(_ transcript: BridgeTranscript) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(transcript.events.enumerated()), id: \.offset) { _, event in
                    transcriptEventView(event)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func transcriptEventView(_ event: BridgeTranscriptEvent) -> some View {
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
