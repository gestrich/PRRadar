import AppKit
import PRRadarModels
import SwiftUI

enum DiffLayout {
    static let gutterWidth: CGFloat = 96
}

// MARK: - Moved Line Lookup

struct MovedLineInfo {
    let move: MoveDetail
    let isSource: Bool
}

struct MovedLineLookup {
    private struct LineKey: Hashable {
        let filePath: String
        let lineNumber: Int
        let side: Side
        enum Side { case old, new }
    }

    private let movedByLine: [LineKey: Bool]
    private let moveDetailRanges: [(filePath: String, range: ClosedRange<Int>, move: MoveDetail, isSource: Bool)]

    static let empty = MovedLineLookup(annotatedDiff: nil)

    init(annotatedDiff: AnnotatedDiff?) {
        var lineMap: [LineKey: Bool] = [:]
        if let hunks = annotatedDiff?.classifiedHunks {
            for hunk in hunks {
                for line in hunk.lines where line.inMovedBlock {
                    if let oldNum = line.oldLineNumber {
                        lineMap[LineKey(filePath: line.filePath, lineNumber: oldNum, side: .old)] = true
                    }
                    if let newNum = line.newLineNumber {
                        lineMap[LineKey(filePath: line.filePath, lineNumber: newNum, side: .new)] = true
                    }
                }
            }
        }
        movedByLine = lineMap

        var ranges: [(filePath: String, range: ClosedRange<Int>, move: MoveDetail, isSource: Bool)] = []
        if let report = annotatedDiff?.moveReport {
            for move in report.moves {
                if move.sourceLines.count == 2 {
                    ranges.append((filePath: move.sourceFile, range: move.sourceLines[0]...move.sourceLines[1], move: move, isSource: true))
                }
                if move.targetLines.count == 2 {
                    ranges.append((filePath: move.targetFile, range: move.targetLines[0]...move.targetLines[1], move: move, isSource: false))
                }
            }
        }
        moveDetailRanges = ranges
    }

    func lookup(filePath: String, oldLine: Int?, newLine: Int?, lineType: DisplayDiffLineType) -> MovedLineInfo? {
        switch lineType {
        case .deletion:
            guard let line = oldLine else { return nil }
            let key = LineKey(filePath: filePath, lineNumber: line, side: .old)
            guard movedByLine[key] == true else { return nil }
            return findMoveDetail(filePath: filePath, lineNumber: line, isSource: true)

        case .addition:
            guard let line = newLine else { return nil }
            let key = LineKey(filePath: filePath, lineNumber: line, side: .new)
            guard movedByLine[key] == true else { return nil }
            return findMoveDetail(filePath: filePath, lineNumber: line, isSource: false)

        case .context:
            return nil
        }
    }

    private func findMoveDetail(filePath: String, lineNumber: Int, isSource: Bool) -> MovedLineInfo? {
        for entry in moveDetailRanges where entry.filePath == filePath && entry.isSource == isSource && entry.range.contains(lineNumber) {
            return MovedLineInfo(move: entry.move, isSource: isSource)
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

// MARK: - Line Info Popover

struct LineInfoPopoverView: View {
    let line: ClassifiedDiffLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Line Info")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Change Kind")
                        .foregroundStyle(.secondary)
                    Text(line.changeKind.rawValue)
                        .fontWeight(.medium)
                }
                GridRow {
                    Text("Line Type")
                        .foregroundStyle(.secondary)
                    Text(line.lineType.rawValue)
                }
                GridRow {
                    Text("In Moved Block")
                        .foregroundStyle(.secondary)
                    Text(line.inMovedBlock ? "Yes" : "No")
                }
                GridRow {
                    Text("Old Line #")
                        .foregroundStyle(.secondary)
                    Text(line.oldLineNumber.map(String.init) ?? "-")
                }
                GridRow {
                    Text("New Line #")
                        .foregroundStyle(.secondary)
                    Text(line.newLineNumber.map(String.init) ?? "-")
                }
                GridRow {
                    Text("File Path")
                        .foregroundStyle(.secondary)
                    Text(line.filePath)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
            }
            .font(.system(.caption, design: .monospaced))

            Divider()

            Text("Raw Line")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(line.rawLine)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(5)
        }
        .padding(12)
        .frame(minWidth: 280, maxWidth: 400)
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
    var classifiedLine: ClassifiedDiffLine?
    var onAddComment: (() -> Void)?
    var onMoveTapped: (() -> Void)?

    init(
        lineContent: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        lineType: DisplayDiffLineType,
        searchQuery: String = "",
        isMoved: Bool = false,
        classifiedLine: ClassifiedDiffLine? = nil,
        onAddComment: (() -> Void)? = nil,
        onMoveTapped: (() -> Void)? = nil
    ) {
        self.lineContent = lineContent
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.lineType = lineType
        self.searchQuery = searchQuery
        self.isMoved = isMoved
        self.classifiedLine = classifiedLine
        self.onAddComment = onAddComment
        self.onMoveTapped = onMoveTapped
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
                if classifiedLine != nil {
                    Button("Line Info") {
                        showLineInfo = true
                    }
                }
            }
            .popover(isPresented: $showLineInfo) {
                if let line = classifiedLine {
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
    let classifiedHunk: ClassifiedHunk
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
            ForEach(Array(classifiedHunk.lines.enumerated()), id: \.offset) { _, line in
                let displayType = line.lineType.displayType
                let moveInfo = line.inMovedBlock ? movedLineLookup.lookup(
                    filePath: classifiedHunk.filePath,
                    oldLine: line.oldLineNumber,
                    newLine: line.newLineNumber,
                    lineType: displayType
                ) : nil
                DiffLineRowView(
                    lineContent: line.rawLine,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    lineType: displayType,
                    searchQuery: searchQuery,
                    isMoved: line.inMovedBlock,
                    classifiedLine: line,
                    onAddComment: line.newLineNumber != nil ? {
                        composingCommentLine = (filePath: classifiedHunk.filePath, lineNumber: line.newLineNumber!)
                    } : nil,
                    onMoveTapped: moveInfo.map { info in { onMoveTapped?(info.move) } }
                )

                if let newLine = line.newLineNumber,
                   let comments = commentsAtLine[newLine] {
                    let lineBg = lineBackground(for: displayType)
                    let gutterBg = gutterBackground(for: displayType)
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

                if let newLine = line.newLineNumber,
                   let compose = composingCommentLine,
                   compose.filePath == classifiedHunk.filePath,
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
    let annotatedDiff: AnnotatedDiff
    let commentMapping: DiffCommentMapping
    let searchQuery: String
    var prModel: PRModel
    var displayDiff: GitDiff?
    var onMoveTapped: ((MoveDetail) -> Void)?

    init(
        annotatedDiff: AnnotatedDiff,
        commentMapping: DiffCommentMapping,
        searchQuery: String = "",
        prModel: PRModel,
        displayDiff: GitDiff? = nil,
        onMoveTapped: ((MoveDetail) -> Void)? = nil
    ) {
        self.annotatedDiff = annotatedDiff
        self.commentMapping = commentMapping
        self.searchQuery = searchQuery
        self.prModel = prModel
        self.displayDiff = displayDiff
        self.onMoveTapped = onMoveTapped
    }

    private var diff: GitDiff { displayDiff ?? annotatedDiff.fullDiff }
    private var movedLineLookup: MovedLineLookup { MovedLineLookup(annotatedDiff: annotatedDiff) }

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
                        let classified = findClassifiedHunk(for: hunk)
                            ?? ClassifiedHunk.fromHunk(hunk)
                        AnnotatedHunkContentView(
                            classifiedHunk: classified,
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

    private func findClassifiedHunk(for hunk: Hunk) -> ClassifiedHunk? {
        annotatedDiff.classifiedHunks.first {
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

