import AppKit
import PRRadarModels
import SwiftUI

enum DiffLayout {
    static let gutterWidth: CGFloat = 96
}

// MARK: - Inline Comment Card

struct InlineCommentCard<Content: View>: View {
    let accentColor: Color
    var lineBackground: Color = .clear
    var gutterBackground: Color = Color.gray.opacity(0.1)
    var highlightOpacity: Double = 0
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)

            content
                .padding(12)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(highlightOpacity)
        )
        .frame(maxWidth: 720, alignment: .leading)
        .padding(.leading, DiffLayout.gutterWidth)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                lineBackground
                gutterBackground.frame(width: DiffLayout.gutterWidth)
            }
        }
    }
}

// MARK: - Line Info Popover

struct LineInfoPopoverView: View {
    let line: PRLine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                    Text("Line Classification Info")
                        .font(.headline)
                }

                // Classification
                LineInfoSection(title: "Classification") {
                    LineInfoRow(
                        label: "Content Change",
                        description: "What happened to this line's content relative to the base branch.",
                        value: line.contentChange.displayName,
                        valueColor: line.contentChange.displayColor,
                        badge: line.contentChange.rawValue
                    )
                    LineInfoRow(
                        label: "Diff Type",
                        description: "How this line appears in the raw diff output (+, -, or context).",
                        value: line.diffType.displayName,
                        valueColor: line.diffType.displayColor
                    )
                    if line.isSurroundingWhitespaceOnlyChange {
                        LineInfoRow(
                            label: "Whitespace-Only Change",
                            description: "This paired line differs from its counterpart only in leading/trailing whitespace. PRRadar skips it for regex and script rules to avoid false positives.",
                            value: "Yes — leading/trailing whitespace only",
                            valueColor: .orange
                        )
                    }
                }

                // Pairing / Move
                LineInfoSection(title: "Pairing & Move Detection") {
                    if let pairing = line.pairing {
                        LineInfoRow(
                            label: "Paired",
                            description: "This line is linked to a counterpart — either as part of a code move or an in-place edit where a removed line was matched with an added line.",
                            value: pairing.role == .before ? "Before (old/removed side)" : "After (new/added side)",
                            valueColor: pairing.role == .before ? .red.opacity(0.8) : .green.opacity(0.8)
                        )
                        LineInfoRow(
                            label: "Counterpart",
                            description: "The line this is paired with. For moves, this is in a different location. For in-place edits, it's the same file at a nearby line.",
                            value: counterpartDescription(pairing.counterpart),
                            badge: pairing.counterpart.filePath != line.filePath ? "cross-file" : "same file"
                        )
                        if let moveFiles = line.crossFileMoveFiles {
                            LineInfoRow(
                                label: "Cross-File Move",
                                description: "Code moved between files. PRRadar detected the source and destination.",
                                value: "\(moveFiles.source)  →  \(moveFiles.target)",
                                valueColor: .orange
                            )
                        }
                    } else {
                        LineInfoRow(
                            label: "Paired",
                            description: "Whether this line is linked to a counterpart from a move or in-place edit.",
                            value: "No — standalone line",
                            valueColor: .secondary
                        )
                    }
                }

                // Location
                LineInfoSection(title: "Location") {
                    LineInfoRow(
                        label: "File",
                        description: nil,
                        value: line.filePath
                    )
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Old Line #")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(line.oldLineNumber.map(String.init) ?? "—")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.oldLineNumber != nil ? .primary : .tertiary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New Line #")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(line.newLineNumber.map(String.init) ?? "—")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.newLineNumber != nil ? .primary : .tertiary)
                        }
                    }
                    .padding(.top, 2)
                }

                // Inline character-level changes
                if let spans = line.inlineChanges, !spans.isEmpty {
                    LineInfoSection(title: "Inline Character Changes") {
                        Text("Character-level diff detected within this line:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                            HStack(spacing: 8) {
                                Image(systemName: span.kind == .added ? "plus.circle.fill" : "minus.circle.fill")
                                    .foregroundStyle(span.kind == .added ? Color.green : Color.red)
                                    .font(.caption)
                                Text("chars \(span.range.lowerBound)–\(span.range.upperBound - 1)")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }

                // Raw line
                LineInfoSection(title: "Raw Diff Line") {
                    Text("The original line from the diff output, including the +/- prefix.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(line.rawLine)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)
        }
        .frame(minWidth: 360, maxWidth: 480, maxHeight: 560)
    }

    private func counterpartDescription(_ counterpart: Counterpart) -> String {
        let file = counterpart.filePath == line.filePath
            ? "(same file)"
            : counterpart.filePath
        return "\(file) : \(counterpart.lineNumber)"
    }
}

// MARK: - Line Info Helpers

private struct LineInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct LineInfoRow: View {
    let label: String
    let description: String?
    let value: String
    var valueColor: Color = .primary
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: label + description
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 80, maxWidth: 120, alignment: .leading)

            // Right: value + optional badge
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension ContentChange {
    var displayName: String {
        switch self {
        case .added:     return "Added — genuinely new line, no base branch counterpart"
        case .deleted:   return "Deleted — line removed with no replacement"
        case .modified:  return "Modified — in-place edit of an existing line"
        case .unchanged: return "Unchanged — content identical to base branch"
        }
    }

    var displayColor: Color {
        switch self {
        case .added:     return .green
        case .deleted:   return .red
        case .modified:  return .orange
        case .unchanged: return .secondary
        }
    }
}

private extension DiffLineType {
    var displayName: String {
        switch self {
        case .added:   return "+ (added line in diff)"
        case .removed: return "- (removed line in diff)"
        case .context: return "  (context / unchanged)"
        case .header:  return "  (hunk header)"
        }
    }

    var displayColor: Color {
        switch self {
        case .added:           return .green
        case .removed:         return .red
        case .context, .header: return .secondary
        }
    }
}

// MARK: - Views

struct DiffLineRowView: View {
    let lineContent: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let lineType: DiffLineType
    let searchQuery: String
    var isMoved: Bool
    var prLine: PRLine?
    var onAddComment: (() -> Void)?
    var onMoveTapped: (() -> Void)?
    var onSelectRules: (() -> Void)?

    init(
        lineContent: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        lineType: DiffLineType,
        searchQuery: String = "",
        isMoved: Bool = false,
        prLine: PRLine? = nil,
        onAddComment: (() -> Void)? = nil,
        onMoveTapped: (() -> Void)? = nil,
        onSelectRules: (() -> Void)? = nil
    ) {
        self.lineContent = lineContent
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.lineType = lineType
        self.searchQuery = searchQuery
        self.isMoved = isMoved
        self.prLine = prLine
        self.onAddComment = onAddComment
        self.onMoveTapped = onMoveTapped
        self.onSelectRules = onSelectRules
    }

    @State private var isHovering = false
    @State private var showLineInfo = false

    private var matchesSearch: Bool {
        guard !searchQuery.isEmpty else { return false }
        return lineContent.lowercased().contains(searchQuery.lowercased())
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(oldLineNumber.map { String($0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Color.clear
                    .frame(width: 4, height: 16)
                    .overlay {
                        if isMoved, let onMoveTapped {
                            Button(action: onMoveTapped) {
                                Image(systemName: "arrow.right.arrow.left")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("View moved code")
                        }
                    }

                Text(newLineNumber.map { String($0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .background(gutterBackground)
            .contextMenu {
                if prLine != nil {
                    Button("Line Info") {
                        showLineInfo = true
                    }
                }
                if let onSelectRules {
                    Button {
                        onSelectRules()
                    } label: {
                        Label("Select Rules & Analyze\u{2026}", systemImage: "sparkles")
                    }
                }
            }
            .popover(isPresented: $showLineInfo) {
                if let line = prLine {
                    LineInfoPopoverView(line: line)
                }
            }
            .overlay(alignment: .trailing) {
                if isHovering, let onAddComment, newLineNumber != nil {
                    Button(action: onAddComment) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.accentColor.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 12)
                }
            }

            HStack(spacing: 0) {
                if matchesSearch {
                    Text(highlightedContent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                } else {
                    Text(lineContent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
            }
        }
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white.opacity(isHovering ? 0.15 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var textColor: Color {
        switch lineType {
        case .added, .removed:
            return Color.white
        case .context, .header:
            return Color.primary
        }
    }

    private var gutterBackground: Color {
        switch lineType {
        case .added:
            return Color.green.opacity(0.15)
        case .removed:
            return Color.red.opacity(0.15)
        case .context, .header:
            return Color.gray.opacity(0.1)
        }
    }

    private var backgroundColor: Color {
        switch lineType {
        case .added:
            return Color.green.opacity(0.08)
        case .removed:
            return Color.red.opacity(0.08)
        case .context, .header:
            return Color.clear
        }
    }

    private var highlightedContent: AttributedString {
        var attributedString = AttributedString(lineContent)
        if let range = attributedString.range(of: searchQuery, options: .caseInsensitive) {
            attributedString[range].backgroundColor = .yellow.opacity(0.5)
            attributedString[range].foregroundColor = .black
        }
        return attributedString
    }
}

struct HunkHeaderView<TrailingContent: View>: View {
    let hunk: Hunk
    let trailingContent: TrailingContent

    init(hunk: Hunk) where TrailingContent == EmptyView {
        self.hunk = hunk
        self.trailingContent = EmptyView()
    }

    init(hunk: Hunk, @ViewBuilder trailing: () -> TrailingContent) {
        self.hunk = hunk
        self.trailingContent = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                Text("@@ -\(hunk.oldStart),\(hunk.oldLength) +\(hunk.newStart),\(hunk.newLength) @@")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                trailingContent
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            Divider()
        }
    }
}

// MARK: - Rename Views

struct RenameFileHeaderView: View {
    let oldPath: String
    let newPath: String

    var body: some View {
        HStack(spacing: 0) {
            Text(oldPath)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(" \u{2192} ")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .fixedSize()
            Text(newPath)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PureRenameContentView: View {
    var body: some View {
        Text("File renamed without changes.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Annotated Views (with inline comments)

struct AnnotatedHunkContentView: View {
    let hunk: PRHunk
    let moves: [MoveDetail]
    let commentsAtLine: [Int: [ReviewComment]]
    let searchQuery: String
    var prModel: PRModel
    var highlightedCommentID: String?
    var onMoveTapped: ((MoveDetail) -> Void)?
    var onSelectRules: (() -> Void)?

    @State private var composingCommentLine: (filePath: String, lineNumber: Int)?

    private var imageURLMap: [String: String]? { prModel.imageURLMap.isEmpty ? nil : prModel.imageURLMap }
    private var imageBaseDir: String? { prModel.imageBaseDir }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hunk.lines.enumerated()), id: \.element.stableID) { _, line in
                let displayType = line.diffType
                let moveDetail = findMoveDetail(for: line)
                DiffLineRowView(
                    lineContent: line.rawLine,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    lineType: displayType,
                    searchQuery: searchQuery,
                    isMoved: line.pairing != nil,
                    prLine: line,
                    onAddComment: line.newLineNumber != nil ? {
                        composingCommentLine = (filePath: hunk.filePath, lineNumber: line.newLineNumber!)
                    } : nil,
                    onMoveTapped: moveDetail.map { detail in { onMoveTapped?(detail) } },
                    onSelectRules: onSelectRules
                )

                if let newLine = line.newLineNumber,
                   let comments = commentsAtLine[newLine] {
                    let lineBg = lineBackground(for: displayType)
                    let gutterBg = gutterBackground(for: displayType)
                    ForEach(comments) { rc in
                        switch rc.state {
                        case .new:
                            if let pending = rc.pending {
                                InlineCommentView(comment: pending, prModel: prModel, lineBackground: lineBg, gutterBackground: gutterBg, isHighlighted: rc.id == highlightedCommentID)
                                    .id(rc.id)
                            }
                        case .redetected:
                            if let posted = rc.posted {
                                InlinePostedCommentView(
                                    comment: posted,
                                    isRedetected: true,
                                    imageURLMap: imageURLMap,
                                    imageBaseDir: imageBaseDir,
                                    lineBackground: lineBg,
                                    gutterBackground: gutterBg
                                )
                            }
                        case .postedOnly:
                            if let posted = rc.posted {
                                InlinePostedCommentView(
                                    comment: posted,
                                    imageURLMap: imageURLMap,
                                    imageBaseDir: imageBaseDir,
                                    lineBackground: lineBg,
                                    gutterBackground: gutterBg
                                )
                            }
                        }
                    }
                }

                if let newLine = line.newLineNumber,
                   let compose = composingCommentLine,
                   compose.filePath == hunk.filePath,
                   compose.lineNumber == newLine {
                    InlineCommentComposeView(
                        filePath: compose.filePath,
                        lineNumber: compose.lineNumber,
                        prModel: prModel,
                        lineBackground: lineBackground(for: displayType),
                        gutterBackground: gutterBackground(for: displayType),
                        onCancel: { composingCommentLine = nil }
                    )
                }
            }
        }
    }

    private func findMoveDetail(for line: PRLine) -> MoveDetail? {
        guard let moveFiles = line.crossFileMoveFiles else { return nil }
        return moves.first { $0.sourceFile == moveFiles.source && $0.targetFile == moveFiles.target }
    }

    private func lineBackground(for lineType: DiffLineType) -> Color {
        switch lineType {
        case .added: Color.green.opacity(0.08)
        case .removed: Color.red.opacity(0.08)
        case .context, .header: .clear
        }
    }

    private func gutterBackground(for lineType: DiffLineType) -> Color {
        switch lineType {
        case .added: Color.green.opacity(0.15)
        case .removed: Color.red.opacity(0.15)
        case .context, .header: Color.gray.opacity(0.1)
        }
    }
}

struct AnnotatedDiffContentView: View {
    let prDiff: PRDiff
    let displayDiff: GitDiff
    let commentMapping: DiffCommentMapping
    let searchQuery: String
    var prModel: PRModel
    @Binding var scrollToCommentID: String?
    var highlightedCommentID: String?
    var onMoveTapped: ((MoveDetail) -> Void)?
    var onSelectRulesForFile: ((String) -> Void)?

    init(
        prDiff: PRDiff,
        displayDiff: GitDiff,
        commentMapping: DiffCommentMapping,
        searchQuery: String = "",
        prModel: PRModel,
        scrollToCommentID: Binding<String?> = .constant(nil),
        highlightedCommentID: String? = nil,
        onMoveTapped: ((MoveDetail) -> Void)? = nil,
        onSelectRulesForFile: ((String) -> Void)? = nil
    ) {
        self.prDiff = prDiff
        self.displayDiff = displayDiff
        self.commentMapping = commentMapping
        self.searchQuery = searchQuery
        self.prModel = prModel
        self._scrollToCommentID = scrollToCommentID
        self.highlightedCommentID = highlightedCommentID
        self.onMoveTapped = onMoveTapped
        self.onSelectRulesForFile = onSelectRulesForFile
    }

    private var tasks: [RuleRequest] { prModel.preparation?.tasks ?? [] }
    private var imageURLMap: [String: String]? { prModel.imageURLMap.isEmpty ? nil : prModel.imageURLMap }
    private var imageBaseDir: String? { prModel.imageBaseDir }

    private var canRunSelectiveEvaluation: Bool {
        !tasks.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !commentMapping.unmatchedNoFile.isEmpty {
                        fileLevelSection(commentMapping.unmatchedNoFile, title: "General Comments")
                    }

                    ForEach(displayDiff.changedFiles, id: \.self) { filePath in
                        let hunks = displayDiff.getHunks(byFilePath: filePath)
                        let oldPath = hunks.first(where: { $0.renameFrom != nil })?.renameFrom

                        if let oldPath {
                            RenameFileHeaderView(oldPath: oldPath, newPath: filePath)
                        } else {
                            Text(filePath)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .windowBackgroundColor))
                        }

                        if hunks.allSatisfy({ $0.diffLines.isEmpty }) && oldPath != nil {
                            PureRenameContentView()
                        }

                        if let fileLevel = commentMapping.unmatchedByFile[filePath], !fileLevel.isEmpty {
                            fileLevelSection(fileLevel)
                        }

                        ForEach(hunks.filter { !$0.diffLines.isEmpty }) { hunk in
                            HunkHeaderView(hunk: hunk) {
                                hunkActions(for: hunk)
                            }
                            let prHunk = findPRHunk(for: hunk)
                                ?? PRHunk.fromHunk(hunk)
                            AnnotatedHunkContentView(
                                hunk: prHunk,
                                moves: prDiff.moves,
                                commentsAtLine: commentMapping.byFileAndLine[filePath] ?? [:],
                                searchQuery: searchQuery,
                                prModel: prModel,
                                highlightedCommentID: highlightedCommentID,
                                onMoveTapped: onMoveTapped,
                                onSelectRules: onSelectRulesForFile.map { callback in { callback(filePath) } }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .task(id: scrollToCommentID) {
                guard let id = scrollToCommentID else { return }
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                scrollToCommentID = nil
            }
        }
    }

    @ViewBuilder
    private func fileLevelSection(_ comments: [ReviewComment], title: String = "File-level comments") -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))

            ForEach(comments) { rc in
                switch rc.state {
                case .new:
                    if let pending = rc.pending {
                        InlineCommentView(comment: pending, prModel: prModel, isHighlighted: rc.id == highlightedCommentID)
                            .id(rc.id)
                    }
                case .redetected:
                    if let posted = rc.posted {
                        InlinePostedCommentView(
                            comment: posted,
                            isRedetected: true,
                            imageURLMap: imageURLMap,
                            imageBaseDir: imageBaseDir
                        )
                    }
                case .postedOnly:
                    if let posted = rc.posted {
                        InlinePostedCommentView(
                            comment: posted,
                            imageURLMap: imageURLMap,
                            imageBaseDir: imageBaseDir
                        )
                    }
                }
            }
        }
    }

    private func findPRHunk(for hunk: Hunk) -> PRHunk? {
        prDiff.hunks.first {
            $0.filePath == hunk.filePath
                && $0.oldStart == hunk.oldStart
                && $0.newStart == hunk.newStart
        }
    }

    // MARK: - Hunk Actions

    private func focusAreasForHunk(_ hunk: Hunk) -> [FocusArea] {
        let fileTasks = tasks.filter { $0.focusArea.filePath == hunk.filePath }
        let hunkNewEnd = hunk.newStart + hunk.newLength - 1
        let matching = fileTasks.filter { task in
            task.focusArea.startLine <= hunkNewEnd && task.focusArea.endLine >= hunk.newStart
        }
        var seen = Set<String>()
        return matching.compactMap { task in
            guard seen.insert(task.focusArea.focusId).inserted else { return nil }
            return task.focusArea
        }
    }

    @ViewBuilder
    private func hunkActions(for hunk: Hunk) -> some View {
        let matchingFocusAreas = focusAreasForHunk(hunk)
        if canRunSelectiveEvaluation && !matchingFocusAreas.isEmpty {
            let inFlight = matchingFocusAreas.contains { area in
                prModel.isFocusAreaStreaming(area.focusId)
            }

            if inFlight {
                ProgressView()
                    .controlSize(.mini)
            }

            if matchingFocusAreas.count == 1, let area = matchingFocusAreas.first {
                Button {
                    prModel.startSelectiveAnalysis(
                        filter: RuleFilter(focusAreaId: area.focusId)
                    )
                } label: {
                    Label("Run Analysis", systemImage: "play.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .contextMenu {
                    let groups = prModel.ruleGroups(forFocusArea: area.focusId)

                    Button {
                        prModel.startSelectiveAnalysis(
                            filter: RuleFilter(focusAreaId: area.focusId)
                        )
                    } label: {
                        Label("Run All Rules", systemImage: "play.fill")
                    }

                    if groups.count > 1 {
                        Menu("Run Rule\u{2026}") {
                            ForEach(groups) { group in
                                Button(group.displayName) {
                                    prModel.startSelectiveAnalysis(filter: group.filter)
                                }
                            }
                        }
                    }
                }
            } else {
                Menu {
                    ForEach(matchingFocusAreas) { area in
                        Section(area.description) {
                            Button {
                                prModel.startSelectiveAnalysis(
                                    filter: RuleFilter(focusAreaId: area.focusId)
                                )
                            } label: {
                                Label("Run All Rules", systemImage: "play.fill")
                            }
                        }
                    }
                } label: {
                    Label("Run Analysis", systemImage: "play.circle")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}

