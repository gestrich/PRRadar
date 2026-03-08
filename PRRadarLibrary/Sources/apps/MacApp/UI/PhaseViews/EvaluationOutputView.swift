import PRRadarConfigService
import PRRadarModels
import SwiftUI

struct EvaluationOutputView: View {

    @Environment(PRModel.self) private var prModel

    let outputsByPhase: [PRRadarPhase: [EvaluationOutput]]
    var isStreaming: Bool = false
    var initialOutputId: String?

    @State private var selectedPhase: PRRadarPhase = .prepare
    @State private var selectedOutputId: String?

    private var phases: [PRRadarPhase] {
        [.prepare, .analyze].filter { outputsByPhase[$0] != nil }
    }

    private var outputs: [EvaluationOutput] {
        outputsByPhase[selectedPhase] ?? []
    }

    private var selectedOutput: EvaluationOutput? {
        if let id = selectedOutputId {
            return outputs.first { $0.identifier == id }
        }
        return outputs.first
    }

    // MARK: - File Grouping

    private struct FileGroup: Identifiable {
        let filePath: String
        let outputs: [EvaluationOutput]
        var id: String { filePath }

        var displayName: String {
            if filePath.isEmpty { return "Unknown File" }
            return (filePath as NSString).lastPathComponent
        }
    }

    private var fileGroups: [FileGroup] {
        var grouped: [String: [EvaluationOutput]] = [:]
        var order: [String] = []
        for output in outputs {
            let key = output.filePath
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(output)
        }
        return order.map { FileGroup(filePath: $0, outputs: grouped[$0]!) }
    }

    private var useFileGrouping: Bool {
        selectedPhase == .analyze
    }

    // MARK: - Row Label

    private func rowLabel(for output: EvaluationOutput) -> String {
        if useFileGrouping, !output.ruleName.isEmpty {
            return output.ruleName
        }
        return output.identifier
    }

    private func modelName(for output: EvaluationOutput) -> String? {
        if case .ai(let model, _) = output.source {
            return displayName(forModelId: model)
        }
        return nil
    }

    private func modeBadgeLabel(for output: EvaluationOutput) -> String {
        switch output.mode {
        case .ai: "AI"
        case .regex: "Regex"
        case .script: "Script"
        }
    }

    private func modeBadgeColor(for output: EvaluationOutput) -> Color {
        switch output.mode {
        case .ai: .blue
        case .regex: .purple
        case .script: .orange
        }
    }

    var body: some View {
        if phases.isEmpty {
            ContentUnavailableView(
                "No Evaluation Output",
                systemImage: "text.bubble",
                description: Text("Run Focus Areas or Evaluations to generate output.")
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
                    outputList
                        .frame(minWidth: 180, maxWidth: 250)
                    outputDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                if let initialOutputId,
                   let phase = prModel.phaseForOutput(identifier: initialOutputId) {
                    selectedPhase = phase
                    selectedOutputId = initialOutputId
                } else if let first = phases.first {
                    selectedPhase = first
                    selectedOutputId = outputsByPhase[first]?.first?.identifier
                }
            }
            .onChange(of: outputs.count) {
                if isStreaming, let last = outputs.last {
                    selectedOutputId = last.identifier
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
            Text("Evaluating...")
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

            Text("\(outputs.count) output\(outputs.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: selectedPhase) {
            selectedOutputId = outputs.first?.identifier
        }
    }

    // MARK: - Output List

    @ViewBuilder
    private var outputList: some View {
        if useFileGrouping {
            groupedOutputList
        } else {
            flatOutputList
        }
    }

    @ViewBuilder
    private var flatOutputList: some View {
        List(outputs, id: \.identifier, selection: $selectedOutputId) { output in
            outputRow(output)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var groupedOutputList: some View {
        List(selection: $selectedOutputId) {
            ForEach(fileGroups) { group in
                Section {
                    ForEach(group.outputs, id: \.identifier) { output in
                        outputRow(output)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text(group.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        if prModel.isFileStreaming(group.filePath) {
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
    private func outputRow(_ output: EvaluationOutput) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(rowLabel(for: output))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                Text(modeBadgeLabel(for: output))
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(modeBadgeColor(for: output).opacity(0.15))
                    .foregroundStyle(modeBadgeColor(for: output))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if isStreaming {
                Text("\(output.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text(DurationFormatter.format(milliseconds: output.durationMs))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let model = modelName(for: output) {
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if output.costUsd > 0 {
                        Text(String(format: "$%.4f", output.costUsd))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Output Detail

    @ViewBuilder
    private var outputDetail: some View {
        if let output = selectedOutput {
            VStack(spacing: 0) {
                outputHeader(output)
                Divider()
                outputEntries(output)
            }
        } else {
            ContentUnavailableView(
                "Select an Output",
                systemImage: "text.bubble",
                description: Text("Choose an output from the sidebar.")
            )
        }
    }

    @ViewBuilder
    private func outputHeader(_ output: EvaluationOutput) -> some View {
        HStack(spacing: 16) {
            if isStreaming {
                headerItem("Entries", "\(output.entries.count)")
                headerItem("Started", output.startedAt)
            } else {
                headerItem("Mode", modeBadgeLabel(for: output))

                switch output.source {
                case .ai(let model, _):
                    headerItem("Model", displayName(forModelId: model))
                case .regex(let pattern):
                    headerItem("Pattern", pattern)
                case .script(let path):
                    headerItem("Script", (path as NSString).lastPathComponent)
                }

                headerItem("Duration", DurationFormatter.format(milliseconds: output.durationMs))

                if output.costUsd > 0 {
                    headerItem("Cost", String(format: "$%.4f", output.costUsd))
                }

                headerItem("Started", output.startedAt)
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
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func outputEntries(_ output: EvaluationOutput) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if case .ai(_, let prompt) = output.source, let prompt {
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

                    ForEach(Array(output.entries.enumerated()), id: \.offset) { _, entry in
                        outputEntryView(entry)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("output-bottom")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: output.entries.count) {
                if isStreaming {
                    withAnimation {
                        proxy.scrollTo("output-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func outputEntryView(_ entry: OutputEntry) -> some View {
        switch entry.type {
        case .text:
            if let content = entry.content {
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
                if let content = entry.content {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } label: {
                Label(entry.label ?? "Tool", systemImage: "wrench")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
        case .result:
            if let content = entry.content {
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
        case .error:
            if let content = entry.content {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
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
