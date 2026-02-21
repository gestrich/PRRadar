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
    static let gutterWidth: CGFloat = 96
}

// MARK: - Views

struct DiffLineRowView: View {
    let lineContent: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let lineType: DisplayDiffLineType
    let searchQuery: String

    init(
        lineContent: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        lineType: DisplayDiffLineType,
        searchQuery: String = ""
    ) {
        self.lineContent = lineContent
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.lineType = lineType
        self.searchQuery = searchQuery
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

    private var imageURLMap: [String: String]? { prModel.imageURLMap.isEmpty ? nil : prModel.imageURLMap }
    private var imageBaseDir: String? { prModel.imageBaseDir }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diffLineData) { line in
                DiffLineRowView(
                    lineContent: line.content,
                    oldLineNumber: line.oldLine,
                    newLineNumber: line.newLine,
                    lineType: line.lineType,
                    searchQuery: searchQuery
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

    init(
        diff: GitDiff,
        commentMapping: DiffCommentMapping,
        searchQuery: String = "",
        prModel: PRModel
    ) {
        self.diff = diff
        self.commentMapping = commentMapping
        self.searchQuery = searchQuery
        self.prModel = prModel
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
                            prModel: prModel
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
                let areaTaskIds = Set(tasks.filter { $0.focusArea.focusId == area.focusId }.map(\.taskId))
                return !areaTaskIds.isDisjoint(with: prModel.selectiveAnalysisInFlight)
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
