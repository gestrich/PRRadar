import AppKit
import PRRadarModels
import SwiftUI

/// A code viewer with line numbers and an authors sidebar showing git blame information
public struct CodeView: View {
    let fileContent: String
    let fileBlameData: FileBlameData?
    let highlightedLine: Int?
    let highlightedColumn: Int?
    let fileName: String
    let onClose: (() -> Void)?

    @State private var showAuthors = false
    @State private var selectedSection: BlameSection?
    @State private var hoveredSection: Int?
    @State private var popoverAnchor: CGRect = .zero
    @State private var scrollToLine: Int?

    public init(
        fileContent: String,
        fileBlameData: FileBlameData? = nil,
        fileName: String,
        highlightedLine: Int? = nil,
        highlightedColumn: Int? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.fileContent = fileContent
        self.fileBlameData = fileBlameData
        self.fileName = fileName
        self.highlightedLine = highlightedLine
        self.highlightedColumn = highlightedColumn
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if let fileBlameData, showAuthors {
                codeWithAuthorsView(blameData: fileBlameData)
            } else if let fileBlameData {
                codeScrollView(lines: fileBlameData.lines)
            } else {
                codeScrollView(lines: simpleLines)
            }
        }
    }

    private var simpleLines: [String] {
        fileContent.components(separatedBy: .newlines)
    }

    @ViewBuilder
    private func codeScrollView(lines: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                codeContentColumn(lines: lines)
            }
            .defaultScrollAnchor(.topLeading)
            .onAppear {
                if let line = highlightedLine, line > 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(line - 1, anchor: .center)
                    }
                }
            }
            .onChange(of: scrollToLine) { _, newLine in
                if let line = newLine, line > 0 {
                    Task { @MainActor in
                        let nearbyLine = max(0, line - 10)
                        proxy.scrollTo(nearbyLine, anchor: .top)

                        try? await Task.sleep(nanoseconds: 50_000_000)

                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(line - 1, anchor: .center)
                        }

                        scrollToLine = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func codeWithAuthorsView(blameData: FileBlameData) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(blameData.sections, id: \.startLine) { section in
                        HStack(alignment: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach((section.startLine...section.endLine), id: \.self) { lineNum in
                                    if lineNum <= blameData.lines.count {
                                        CodeLineView(
                                            lineNumber: lineNum,
                                            content: blameData.lines[lineNum - 1],
                                            isHighlighted: highlightedLine == lineNum,
                                            highlightedColumn: highlightedLine == lineNum ? highlightedColumn : nil
                                        )
                                        .id(lineNum)
                                    }
                                }
                            }

                            Rectangle()
                                .fill(Color(NSColor.separatorColor))
                                .frame(width: 1)

                            AuthorSectionView(
                                section: section,
                                selectedSection: $selectedSection,
                                hoveredSection: $hoveredSection
                            )
                            .frame(width: 400, alignment: .top)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        }
                    }
                }
            }
            .defaultScrollAnchor(.topLeading)
            .onAppear {
                if let line = highlightedLine, line > 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(line, anchor: .center)
                    }
                }
            }
            .onChange(of: scrollToLine) { _, newLine in
                if let line = newLine, line > 0 {
                    Task { @MainActor in
                        if let targetSection = blameData.sections.first(where: {
                            line >= $0.startLine && line <= $0.endLine
                        }) {
                            proxy.scrollTo(targetSection.startLine, anchor: .top)

                            try? await Task.sleep(nanoseconds: 50_000_000)

                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(line, anchor: .center)
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(line, anchor: .center)
                            }
                        }

                        scrollToLine = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func codeContentColumn(lines: [String]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
            ForEach(lines.indices, id: \.self) { index in
                CodeLineView(
                    lineNumber: index + 1,
                    content: lines[index],
                    isHighlighted: highlightedLine == index + 1,
                    highlightedColumn: highlightedLine == index + 1 ? highlightedColumn : nil
                )
                .id(index)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var lineHeight: CGFloat { 24 }

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            Text(fileName)
                .font(.headline)

            Spacer()

            if let highlightedLine {
                Button(action: {
                    scrollToLine = highlightedLine
                }) {
                    Label("Jump to Line \(highlightedLine)", systemImage: "arrow.down.to.line")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Jump to highlighted line")
            }

            if fileBlameData != nil {
                Button(action: { showAuthors.toggle() }) {
                    Label(
                        showAuthors ? "Hide Authors" : "Show Authors",
                        systemImage: showAuthors ? "person.fill.xmark" : "person.fill.checkmark"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct CodeLineView: View {
    let lineNumber: Int
    let content: String
    let isHighlighted: Bool
    let highlightedColumn: Int?

    private let columnHighlightEnabled = false

    var body: some View {
        HStack(spacing: 0) {
            Text("\(lineNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isHighlighted ? .white : .secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1)

            Text(content.isEmpty ? " " : content)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(
                    columnHighlightEnabled ? columnHighlightOverlay : nil
                )

            Spacer(minLength: 0)
        }
        .background(
            isHighlighted
                ? Color.yellow.opacity(0.15)
                : Color.clear
        )
        .overlay(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isHighlighted ? Color.accentColor : Color.clear)
                    .frame(width: 77)
                Spacer()
            },
            alignment: .leading
        )
    }

    @ViewBuilder
    private var columnHighlightOverlay: some View {
        if let column = highlightedColumn, column >= 0 {
            GeometryReader { geometry in
                let columnIndex = max(0, column)

                if columnIndex < content.count {
                    let charWidth: CGFloat = 7.2
                    let xPosition = CGFloat(columnIndex) * charWidth

                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.yellow.opacity(0.4))
                            .frame(width: charWidth, height: geometry.size.height)
                            .offset(x: xPosition, y: 0)

                        Path { path in
                            let y = geometry.size.height - 3
                            let startX = xPosition
                            let endX = xPosition + charWidth

                            path.move(to: CGPoint(x: startX, y: y))

                            var goingUp = true
                            for x in stride(from: startX, through: endX, by: 3) {
                                let nextY = goingUp ? y - 1.5 : y + 1.5
                                path.addLine(to: CGPoint(x: x, y: nextY))
                                goingUp.toggle()
                            }
                        }
                        .stroke(Color.orange, lineWidth: 2)
                    }
                }
            }
        }
    }
}

struct AuthorSectionView: View {
    let section: BlameSection
    @Binding var selectedSection: BlameSection?
    @Binding var hoveredSection: Int?
    @State private var showCopiedFeedback = false

    private var isHovered: Bool {
        hoveredSection == section.startLine
    }

    private var isSelected: Bool {
        selectedSection?.startLine == section.startLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                authorInfo
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            hoveredSection = hovering ? section.startLine : nil
        }
        .onTapGesture {
            selectedSection = (selectedSection?.startLine == section.startLine) ? nil : section
        }
        .popover(isPresented: Binding(
            get: { isSelected },
            set: { if !$0 { selectedSection = nil } }
        )) {
            authorDetailPopover
        }
        .help(section.lineCount > 1 ?
              "Lines \(section.startLine)-\(section.endLine): \(section.ownership.summary)" :
              "Line \(section.startLine)")
    }

    @ViewBuilder
    private var authorInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(section.ownership.author.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let date = section.ownership.commitDate {
                    Text(relativeDate(from: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if section.lineCount > 1 {
                Text(section.ownership.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var authorDetailPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(colorForAuthor(section.ownership.author.email))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(initialsForAuthor(section.ownership.author.name))
                            .font(.caption)
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.ownership.author.name)
                        .font(.headline)
                    Text(section.ownership.author.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Commit:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(section.ownership.commitHash.prefix(7)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                }

                if let date = section.ownership.commitDate {
                    HStack {
                        Text("Date:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDate(date))
                            .font(.caption)
                    }
                }

                if section.lineCount > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Message:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(section.ownership.summary)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                }

                HStack {
                    Text("Lines:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(section.startLine)-\(section.endLine) (\(section.lineCount) lines)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            Divider()

            Button(action: {
                copyCommitInfo()
                showCopiedFeedback = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    showCopiedFeedback = false
                }
            }) {
                Label(
                    showCopiedFeedback ? "Copied!" : "Copy Commit Info",
                    systemImage: showCopiedFeedback ? "checkmark.circle" : "doc.on.doc"
                )
                .font(.caption)
                .foregroundStyle(showCopiedFeedback ? .green : .primary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 300)
    }

    private func copyCommitInfo() {
        var commitInfo = ""
        commitInfo += "commit \(section.ownership.commitHash)\n"
        commitInfo += "Author: \(section.ownership.author.name) <\(section.ownership.author.email)>\n"
        if let date = section.ownership.commitDate {
            commitInfo += "Date: \(formatDate(date))\n"
        }
        commitInfo += "\n    \(section.ownership.summary)\n"

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(commitInfo, forType: .string)
    }

    private func colorForAuthor(_ email: String) -> Color {
        let hash = email.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.6)
    }

    private func initialsForAuthor(_ name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap(\.first).map { String($0) }.joined()
        return initials.uppercased()
    }

    private func relativeDate(from dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
