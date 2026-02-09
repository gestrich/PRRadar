import PRRadarModels
import SwiftUI

struct ReportPhaseView: View {

    let report: ReviewReport
    let markdownContent: String

    @State private var showRawMarkdown = false

    var body: some View {
        VStack(spacing: 0) {
            summaryCards
            breakdownTables
        }
        .sheet(isPresented: $showRawMarkdown) {
            markdownSheet
        }
    }

    // MARK: - Summary Cards

    @ViewBuilder
    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard("Total Tasks", "\(report.summary.totalTasksEvaluated)")
            summaryCard("Violations", "\(report.summary.violationsFound)")
            summaryCard("Highest Severity", "\(report.summary.highestSeverity)")
            summaryCard("Cost", String(format: "$%.4f", report.summary.totalCostUsd))
            if !report.summary.modelsUsed.isEmpty {
                let modelNames = report.summary.modelsUsed.map { displayName(forModelId: $0) }.joined(separator: ", ")
                summaryCard("Model", modelNames)
            }

            Spacer()

            Button("View Markdown") {
                showRawMarkdown = true
            }
        }
        .padding()
    }

    @ViewBuilder
    private func summaryCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 100)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Breakdown Tables

    @ViewBuilder
    private var breakdownTables: some View {
        List {
            if !report.summary.bySeverity.isEmpty {
                Section("By Severity") {
                    ForEach(report.summary.bySeverity.sorted(by: { $0.key < $1.key }), id: \.key) { severity, count in
                        HStack {
                            Text("Score \(severity)")
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !report.summary.byFile.isEmpty {
                Section("By File") {
                    ForEach(report.summary.byFile.sorted(by: { $0.value > $1.value }), id: \.key) { file, count in
                        HStack {
                            Text(URL(fileURLWithPath: file).lastPathComponent)
                                .help(file)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !report.summary.byRule.isEmpty {
                Section("By Rule") {
                    ForEach(report.summary.byRule.sorted(by: { $0.value > $1.value }), id: \.key) { rule, count in
                        HStack {
                            Text(rule)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Violations") {
                ForEach(Array(report.violations.enumerated()), id: \.offset) { _, violation in
                    ViolationCard(violation: violation)
                }
            }
        }
    }

    // MARK: - Markdown Sheet

    @ViewBuilder
    private var markdownSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Report Markdown")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { showRawMarkdown = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                Text(markdownContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
