import PRRadarModels

struct DiffCommentMapping {
    let commentsByFileAndLine: [String: [Int: [RuleEvaluationResult]]]
    let unmatchedByFile: [String: [RuleEvaluationResult]]
    let unmatchedNoFile: [RuleEvaluationResult]

    static let empty = DiffCommentMapping(
        commentsByFileAndLine: [:],
        unmatchedByFile: [:],
        unmatchedNoFile: []
    )
}

enum DiffCommentMapper {

    static func map(diff: GitDiff, evaluations: [RuleEvaluationResult]) -> DiffCommentMapping {
        let violations = evaluations.filter(\.evaluation.violatesRule)
        let diffFiles = Set(diff.changedFiles)

        var byFileAndLine: [String: [Int: [RuleEvaluationResult]]] = [:]
        var unmatchedByFile: [String: [RuleEvaluationResult]] = [:]
        var unmatchedNoFile: [RuleEvaluationResult] = []

        for violation in violations {
            let filePath = violation.evaluation.filePath

            guard diffFiles.contains(filePath) else {
                unmatchedNoFile.append(violation)
                continue
            }

            guard let lineNumber = violation.evaluation.lineNumber else {
                unmatchedByFile[filePath, default: []].append(violation)
                continue
            }

            if diff.findHunk(containingLine: lineNumber, inFile: filePath) != nil {
                byFileAndLine[filePath, default: [:]][lineNumber, default: []].append(violation)
            } else {
                unmatchedByFile[filePath, default: []].append(violation)
            }
        }

        return DiffCommentMapping(
            commentsByFileAndLine: byFileAndLine,
            unmatchedByFile: unmatchedByFile,
            unmatchedNoFile: unmatchedNoFile
        )
    }
}
