import PRRadarModels

struct DiffCommentMapping {
    let byFileAndLine: [String: [Int: [ReviewComment]]]
    let unmatchedByFile: [String: [ReviewComment]]
    let unmatchedNoFile: [ReviewComment]

    static let empty = DiffCommentMapping(
        byFileAndLine: [:],
        unmatchedByFile: [:],
        unmatchedNoFile: []
    )
}

enum DiffCommentMapper {

    static func map(
        diff: GitDiff,
        comments: [ReviewComment]
    ) -> DiffCommentMapping {
        let diffFiles = Set(diff.changedFiles)

        var byFileAndLine: [String: [Int: [ReviewComment]]] = [:]
        var unmatchedByFile: [String: [ReviewComment]] = [:]
        var unmatchedNoFile: [ReviewComment] = []

        for comment in comments {
            let filePath = comment.filePath

            guard diffFiles.contains(filePath) else {
                unmatchedNoFile.append(comment)
                continue
            }

            guard let lineNumber = comment.lineNumber else {
                unmatchedByFile[filePath, default: []].append(comment)
                continue
            }

            if diff.findHunk(containingLine: lineNumber, inFile: filePath) != nil {
                byFileAndLine[filePath, default: [:]][lineNumber, default: []].append(comment)
            } else {
                unmatchedByFile[filePath, default: []].append(comment)
            }
        }

        // Sort within each line: postedOnly first, then redetected, then new
        for (file, lineMap) in byFileAndLine {
            for (line, lineComments) in lineMap {
                byFileAndLine[file]![line] = lineComments.sorted { a, b in
                    a.state.sortOrder < b.state.sortOrder
                }
            }
        }

        return DiffCommentMapping(
            byFileAndLine: byFileAndLine,
            unmatchedByFile: unmatchedByFile,
            unmatchedNoFile: unmatchedNoFile
        )
    }
}

private extension ReviewComment.State {
    var sortOrder: Int {
        switch self {
        case .postedOnly: 0
        case .redetected: 1
        case .new: 2
        }
    }
}
