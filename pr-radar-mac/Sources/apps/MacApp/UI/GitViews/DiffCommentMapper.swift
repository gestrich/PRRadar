import PRRadarModels

struct DiffCommentMapping {
    let commentsByFileAndLine: [String: [Int: [PRComment]]]
    let unmatchedByFile: [String: [PRComment]]
    let unmatchedNoFile: [PRComment]

    static let empty = DiffCommentMapping(
        commentsByFileAndLine: [:],
        unmatchedByFile: [:],
        unmatchedNoFile: []
    )
}

enum DiffCommentMapper {

    static func map(diff: GitDiff, comments: [PRComment]) -> DiffCommentMapping {
        let diffFiles = Set(diff.changedFiles)

        var byFileAndLine: [String: [Int: [PRComment]]] = [:]
        var unmatchedByFile: [String: [PRComment]] = [:]
        var unmatchedNoFile: [PRComment] = []

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

        return DiffCommentMapping(
            commentsByFileAndLine: byFileAndLine,
            unmatchedByFile: unmatchedByFile,
            unmatchedNoFile: unmatchedNoFile
        )
    }
}
