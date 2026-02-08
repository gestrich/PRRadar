import AppKit
import PRRadarModels
import SwiftUI

// MARK: - Data Models

struct DiffLineData: Identifiable {
    let id: String
    let content: String
    let oldLine: Int?
    let newLine: Int?
}

// MARK: - Views

struct DiffLineRowView: View {
    let lineContent: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let searchQuery: String

    init(
        lineContent: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        searchQuery: String = ""
    ) {
        self.lineContent = lineContent
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.searchQuery = searchQuery
    }

    @State private var isHovering = false

    private var lineType: DisplayDiffLineType {
        if lineContent.hasPrefix("+") {
            return .addition
        } else if lineContent.hasPrefix("-") {
            return .deletion
        } else {
            return .context
        }
    }

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
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

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
            .background(backgroundColor)
        }
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

    private var backgroundColor: Color {
        switch lineType {
        case .addition:
            return Color.green.opacity(0.15)
        case .deletion:
            return Color.red.opacity(0.15)
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

struct HunkContentView: View {
    let hunk: Hunk
    let searchQuery: String

    init(hunk: Hunk, searchQuery: String = "") {
        self.hunk = hunk
        self.searchQuery = searchQuery
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diffLineData) { line in
                DiffLineRowView(
                    lineContent: line.content,
                    oldLineNumber: line.oldLine,
                    newLineNumber: line.newLine,
                    searchQuery: searchQuery
                )
            }
        }
    }

    private var diffLineData: [DiffLineData] {
        HunkLineParser.parse(hunk: hunk)
    }
}

struct HunkHeaderView: View {
    let hunk: Hunk

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                Text("@@ -\(hunk.oldStart),\(hunk.oldLength) +\(hunk.newStart),\(hunk.newLength) @@")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            Divider()
        }
    }
}

struct RichDiffContentView: View {
    let diff: GitDiff
    let searchQuery: String

    init(diff: GitDiff, searchQuery: String = "") {
        self.diff = diff
        self.searchQuery = searchQuery
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diff.changedFiles, id: \.self) { filePath in
                    Text(filePath)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))

                    ForEach(diff.getHunks(byFilePath: filePath)) { hunk in
                        HunkHeaderView(hunk: hunk)
                        HunkContentView(hunk: hunk, searchQuery: searchQuery)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Annotated Views (with inline comments)

struct AnnotatedHunkContentView: View {
    let hunk: Hunk
    let commentsAtLine: [Int: [PRComment]]
    let searchQuery: String
    var prModel: PRModel? = nil

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diffLineData) { line in
                DiffLineRowView(
                    lineContent: line.content,
                    oldLineNumber: line.oldLine,
                    newLineNumber: line.newLine,
                    searchQuery: searchQuery
                )

                if let newLine = line.newLine,
                   let comments = commentsAtLine[newLine],
                   let prModel {
                    ForEach(comments) { comment in
                        InlineCommentView(comment: comment, prModel: prModel)
                    }
                }
            }
        }
    }

    private var diffLineData: [DiffLineData] {
        HunkLineParser.parse(hunk: hunk)
    }
}

struct AnnotatedDiffContentView: View {
    let diff: GitDiff
    let commentMapping: DiffCommentMapping
    let searchQuery: String
    var prModel: PRModel? = nil

    init(
        diff: GitDiff,
        commentMapping: DiffCommentMapping,
        searchQuery: String = "",
        prModel: PRModel? = nil
    ) {
        self.diff = diff
        self.commentMapping = commentMapping
        self.searchQuery = searchQuery
        self.prModel = prModel
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !commentMapping.unmatchedNoFile.isEmpty {
                    unmatchedSection(commentMapping.unmatchedNoFile, title: "General Comments")
                }

                ForEach(diff.changedFiles, id: \.self) { filePath in
                    Text(filePath)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))

                    if let unmatched = commentMapping.unmatchedByFile[filePath] {
                        unmatchedSection(unmatched, title: "File-level comments")
                    }

                    ForEach(diff.getHunks(byFilePath: filePath)) { hunk in
                        HunkHeaderView(hunk: hunk)
                        AnnotatedHunkContentView(
                            hunk: hunk,
                            commentsAtLine: commentMapping.commentsByFileAndLine[filePath] ?? [:],
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
    private func unmatchedSection(_ comments: [PRComment], title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))

            if let prModel {
                ForEach(comments) { comment in
                    InlineCommentView(comment: comment, prModel: prModel)
                }
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

            if lineContent.hasPrefix("+") {
                oldNum = nil
                newNum = newLine
                newLine += 1
            } else if lineContent.hasPrefix("-") {
                oldNum = oldLine
                newNum = nil
                oldLine += 1
            } else {
                oldNum = oldLine
                newNum = newLine
                oldLine += 1
                newLine += 1
            }

            lines.append(DiffLineData(
                id: "\(hunk.id)_\(lineIndex)",
                content: lineContent,
                oldLine: oldNum,
                newLine: newNum
            ))
        }

        return lines
    }
}
