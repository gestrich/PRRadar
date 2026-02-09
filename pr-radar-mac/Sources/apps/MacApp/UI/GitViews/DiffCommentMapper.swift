import PRRadarModels

struct DiffCommentMapping {
    let commentsByFileAndLine: [String: [Int: [PRComment]]]
    let unmatchedByFile: [String: [PRComment]]
    let unmatchedNoFile: [PRComment]
    let postedByFileAndLine: [String: [Int: [GitHubReviewComment]]]
    let postedUnmatchedByFile: [String: [GitHubReviewComment]]

    static let empty = DiffCommentMapping(
        commentsByFileAndLine: [:],
        unmatchedByFile: [:],
        unmatchedNoFile: [],
        postedByFileAndLine: [:],
        postedUnmatchedByFile: [:]
    )
}

enum DiffCommentMapper {

    static func map(
        diff: GitDiff,
        comments: [PRComment],
        postedReviewComments: [GitHubReviewComment] = []
    ) -> DiffCommentMapping {
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

        var postedByFileAndLine: [String: [Int: [GitHubReviewComment]]] = [:]
        var postedUnmatchedByFile: [String: [GitHubReviewComment]] = [:]

        for reviewComment in postedReviewComments {
            let filePath = reviewComment.path

            guard diffFiles.contains(filePath) else {
                continue
            }

            guard let lineNumber = reviewComment.line else {
                postedUnmatchedByFile[filePath, default: []].append(reviewComment)
                continue
            }

            if diff.findHunk(containingLine: lineNumber, inFile: filePath) != nil {
                postedByFileAndLine[filePath, default: [:]][lineNumber, default: []].append(reviewComment)
            } else {
                postedUnmatchedByFile[filePath, default: []].append(reviewComment)
            }
        }

        return DiffCommentMapping(
            commentsByFileAndLine: byFileAndLine,
            unmatchedByFile: unmatchedByFile,
            unmatchedNoFile: unmatchedNoFile,
            postedByFileAndLine: postedByFileAndLine,
            postedUnmatchedByFile: postedUnmatchedByFile
        )
    }
}
