import Logging
import PRRadarModels

private let logger = Logger(label: "PRRadar.DiffCommentMapper")

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

        logger.info("map: \(comments.count) comments, \(diffFiles.count) diff files")
        for comment in comments {
            let filePath = comment.filePath

            guard diffFiles.contains(filePath) else {
                logger.debug("  noFile: \(comment.debugSummary)")
                unmatchedNoFile.append(comment)
                continue
            }

            guard let lineNumber = comment.lineNumber else {
                logger.debug("  unmatchedByFile (no line): \(comment.debugSummary)")
                unmatchedByFile[filePath, default: []].append(comment)
                continue
            }

            if diff.findHunk(containingLine: lineNumber, inFile: filePath) != nil {
                byFileAndLine[filePath, default: [:]][lineNumber, default: []].append(comment)
            } else {
                logger.debug("  unmatchedByFile (line \(lineNumber) not in hunk): \(comment.debugSummary)")
                unmatchedByFile[filePath, default: []].append(comment)
            }
        }

        // Sort within each line: postedOnly first, then redetected, then new
        for (file, lineMap) in byFileAndLine {
            for (line, lineComments) in lineMap {
                byFileAndLine[file]![line] = lineComments.sortedByDisplayOrder()
            }
        }

        return DiffCommentMapping(
            byFileAndLine: byFileAndLine,
            unmatchedByFile: unmatchedByFile,
            unmatchedNoFile: unmatchedNoFile
        )
    }
}
