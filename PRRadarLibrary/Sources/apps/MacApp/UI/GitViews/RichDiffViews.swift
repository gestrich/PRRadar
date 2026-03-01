import AppKit
import PRRadarModels
import SwiftUI

// MARK: - Data Models

struct DiffLineData: Identifiable {
    let id: String
    let content: String
    let oldLine: Int?
    let newLine: Int?
    let lineType: DisplayDiffLineType
}

enum DiffLayout {
    static let gutterWidth: CGFloat = 112
}

// MARK: - Moved Line Lookup

struct MovedLineInfo {
    let move: MoveDetail
    let isSource: Bool
}

struct MovedLineLookup {
    private let sourceRanges: [(filePath: String, range: ClosedRange<Int>, move: MoveDetail)]
    private let targetRanges: [(filePath: String, range: ClosedRange<Int>, move: MoveDetail)]

    static let empty = MovedLineLookup(moveReport: nil)

    init(moveReport: MoveReport?) {
        guard let report = moveReport else {
            sourceRanges = []
            targetRanges = []
            return
        }
        var src: [(filePath: String, range: ClosedRange<Int>, move: MoveDetail)] = []
        var tgt: [(filePath: String, range: ClosedRange<Int>, move: MoveDetail)] = []
        for move in report.moves {
            if move.sourceLines.count == 2 {
                src.append((filePath: move.sourceFile, range: move.sourceLines[0]...move.sourceLines[1], move: move))
            }
            if move.targetLines.count == 2 {
                tgt.append((filePath: move.targetFile, range: move.targetLines[0]...move.targetLines[1], move: move))
            }
        }
        sourceRanges = src
        targetRanges = tgt
    }

    func lookup(filePath: String, oldLine: Int?, newLine: Int?, lineType: DisplayDiffLineType) -> MovedLineInfo? {
        switch lineType {
        case .deletion:
            guard let line = oldLine else { return nil }
            for entry in sourceRanges where entry.filePath == filePath && entry.range.contains(line) {
                return MovedLineInfo(move: entry.move, isSource: true)
            }
        case .addition:
            guard let line = newLine else { return nil }
            for entry in targetRanges where entry.filePath == filePath && entry.range.contains(line) {
                return MovedLineInfo(move: entry.move, isSource: false)
            }
        case .context:
            return nil
        }
        return nil
    }
}

// MARK: - Inline Comment Card

struct InlineCommentCard<Content: View>: View {
    let accentColor: Color
    var lineBackground: Color = .clear
    var gutterBackground: Color = Color.gray.opacity(0.1)
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

// MARK: - Views

struct DiffLineRowView: View {
    let lineContent: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let lineType: DisplayDiffLineType
    let searchQuery: String
    var isMoved: Bool
    var onAddComment: (() -> Void)?
    var onMoveTapped: (() -> Void)?

    init(
        lineContent: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        lineType: DisplayDiffLineType,
        searchQuery: String = "",
        isMoved: Bool = false,
        onAddComment: (() -> Void)? = nil,
        onMoveTapped: (() -> Void)? = nil
    ) {
        self.lineContent = lineContent
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.lineType = lineType
        self.searchQuery = searchQuery
        self.isMoved = isMoved
        self.onAddComment = onAddComment
        self.onMoveTapped = onMoveTapped
    }

    @State private var isHovering = false

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

                Text(newLineNumber.map { String($0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .background(gutterBackground)
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

            if isMoved, let onMoveTapped {
                Button(action: onMoveTapped) {
                    Image(systemName: "arrow.right.arrow.left")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .frame(width: 16)
                .help("View moved code")
            } else {
                Color.clear.frame(width: 16)
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
        case .addition, .deletion:
            return Color.white
        case .context:
            return Color.primary
        }
    }

    private var gutterBackground: Color {
        switch lineType {
        case .addition:
            return Color.green.opacity(0.15)
        case .deletion:
            return Color.red.opacity(0.15)
        case .context:
            return Color.gray.opacity(0.1)
        }
    }

    private var backgroundColor: Color {
        switch lineType {
        case .addition:
            return Color.green.opacity(0.08)
        case .deletion:
            return Color.red.opacity(0.08)
        case .context:
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
    let hunk: Hunk
    let commentsAtLine: [Int: [ReviewComment]]
    let searchQuery: String
    var prModel: PRModel
    var movedLineLookup: MovedLineLookup = .empty
    var onMoveTapped: ((MoveDetail) -> Void)?

    @State private var composingCommentLine: (filePath: String, lineNumber: Int)?

    private var imageURLMap: [String: String]? { prModel.imageURLMap.isEmpty ? nil : prModel.imageURLMap }
    private var imageBaseDir: String? { prModel.imageBaseDir }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diffLineData) { line in
                let moveInfo = movedLineLookup.lookup(
                    filePath: hunk.filePath,
                    oldLine: line.oldLine,
                    newLine: line.newLine,
                    lineType: line.lineType
                )
                DiffLineRowView(
                    lineContent: line.content,
                    oldLineNumber: line.oldLine,
                    newLineNumber: line.newLine,
                    lineType: line.lineType,
                    searchQuery: searchQuery,
                    isMoved: moveInfo != nil,
                    onAddComment: line.newLine != nil ? {
                        composingCommentLine = (filePath: hunk.filePath, lineNumber: line.newLine!)
                    } : nil,
                    onMoveTapped: moveInfo.map { info in { onMoveTapped?(info.move) } }
                )

                if let newLine = line.newLine,
                   let comments = commentsAtLine[newLine] {
                    let lineBg = lineBackground(for: line.lineType)
                    let gutterBg = gutterBackground(for: line.lineType)
                    ForEach(comments) { rc in
                        switch rc.state {
                        case .new:
                            if let pending = rc.pending {
                                InlineCommentView(comment: pending, prModel: prModel, lineBackground: lineBg, gutterBackground: gutterBg)
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

                if let newLine = line.newLine,
                   let compose = composingCommentLine,
                   compose.filePath == hunk.filePath,
                   compose.lineNumber == newLine {
                    InlineCommentComposeView(
                        filePath: compose.filePath,
                        lineNumber: compose.lineNumber,
                        prModel: prModel,
                        lineBackground: lineBackground(for: line.lineType),
                        gutterBackground: gutterBackground(for: line.lineType),
                        onCancel: { composingCommentLine = nil }
                    )
                }
            }
        }
    }

    private var diffLineData: [DiffLineData] {
        HunkLineParser.parse(hunk: hunk)
    }

    private func lineBackground(for lineType: DisplayDiffLineType) -> Color {
        switch lineType {
        case .addition: Color.green.opacity(0.08)
        case .deletion: Color.red.opacity(0.08)
        case .context: .clear
        }
    }

    private func gutterBackground(for lineType: DisplayDiffLineType) -> Color {
        switch lineType {
        case .addition: Color.green.opacity(0.15)
        case .deletion: Color.red.opacity(0.15)
        case .context: Color.gray.opacity(0.1)
        }
    }
}

struct AnnotatedDiffContentView: View {
    let diff: GitDiff
    let commentMapping: DiffCommentMapping
    let searchQuery: String
    var prModel: PRModel
    var movedLineLookup: MovedLineLookup
    var onMoveTapped: ((MoveDetail) -> Void)?

    init(
        diff: GitDiff,
        commentMapping: DiffCommentMapping,
        searchQuery: String = "",
        prModel: PRModel,
        movedLineLookup: MovedLineLookup = .empty,
        onMoveTapped: ((MoveDetail) -> Void)? = nil
    ) {
        self.diff = diff
        self.commentMapping = commentMapping
        self.searchQuery = searchQuery
        self.prModel = prModel
        self.movedLineLookup = movedLineLookup
        self.onMoveTapped = onMoveTapped
    }

    private var tasks: [RuleRequest] { prModel.preparation?.tasks ?? [] }
    private var imageURLMap: [String: String]? { prModel.imageURLMap.isEmpty ? nil : prModel.imageURLMap }
    private var imageBaseDir: String? { prModel.imageBaseDir }

    private var canRunSelectiveEvaluation: Bool {
        !tasks.isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !commentMapping.unmatchedNoFile.isEmpty {
                    fileLevelSection(commentMapping.unmatchedNoFile, title: "General Comments")
                }

                ForEach(diff.changedFiles, id: \.self) { filePath in
                    let hunks = diff.getHunks(byFilePath: filePath)
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
                        AnnotatedHunkContentView(
                            hunk: hunk,
                            commentsAtLine: commentMapping.byFileAndLine[filePath] ?? [:],
                            searchQuery: searchQuery,
                            prModel: prModel,
                            movedLineLookup: movedLineLookup,
                            onMoveTapped: onMoveTapped
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                        InlineCommentView(comment: pending, prModel: prModel)
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
                    let rules = tasks.filter { $0.focusArea.focusId == area.focusId }
                        .map(\.rule.name)
                    let uniqueRules = Array(Set(rules)).sorted()

                    Button {
                        prModel.startSelectiveAnalysis(
                            filter: RuleFilter(focusAreaId: area.focusId)
                        )
                    } label: {
                        Label("Run All Rules", systemImage: "play.fill")
                    }

                    if uniqueRules.count > 1 {
                        Menu("Run Rule\u{2026}") {
                            ForEach(uniqueRules, id: \.self) { rule in
                                Button(rule) {
                                    prModel.startSelectiveAnalysis(
                                        filter: RuleFilter(focusAreaId: area.focusId, ruleNames: [rule])
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                Menu {
                    ForEach(matchingFocusAreas, id: \.focusId) { area in
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

// MARK: - Shared Line Parsing

enum HunkLineParser {
    static func parse(hunk: Hunk) -> [DiffLineData] {
        let hunkLines = hunk.diffLines
        var oldLine = hunk.oldStart
        var newLine = hunk.newStart
        var lines: [DiffLineData] = []

        for (lineIndex, lineContent) in hunkLines.enumerated() {
            let oldNum: Int?
            let newNum: Int?

            let type: DisplayDiffLineType

            if lineContent.hasPrefix("+") {
                oldNum = nil
                newNum = newLine
                newLine += 1
                type = .addition
            } else if lineContent.hasPrefix("-") {
                oldNum = oldLine
                newNum = nil
                oldLine += 1
                type = .deletion
            } else {
                oldNum = oldLine
                newNum = newLine
                oldLine += 1
                newLine += 1
                type = .context
            }

            lines.append(DiffLineData(
                id: "\(hunk.id)_\(lineIndex)",
                content: lineContent,
                oldLine: oldNum,
                newLine: newNum,
                lineType: type
            ))
        }

        return lines
    }
}
