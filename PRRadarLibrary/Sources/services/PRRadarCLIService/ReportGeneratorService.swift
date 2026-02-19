import Foundation
import PRRadarConfigService
import PRRadarModels

public struct ReportGeneratorService: Sendable {
    public init() {}

    /// Generate a complete review report from evaluation results.
    ///
    /// - Parameters:
    ///   - prNumber: PR number
    ///   - minScore: Minimum violation score to include
    ///   - evalsDir: Directory containing evaluation result files
    ///   - tasksDir: Directory containing task files
    ///   - focusAreasDir: Directory containing focus area files
    public func generateReport(
        prNumber: Int,
        minScore: Int,
        evalsDir: String,
        tasksDir: String,
        focusAreasDir: String
    ) throws -> ReviewReport {
        let (violations, totalTasks, totalCost, modelsUsed) = loadViolations(
            evaluationsDir: evalsDir,
            tasksDir: tasksDir,
            minScore: minScore
        )

        let focusAreaCost = loadFocusAreaGenerationCost(focusAreasDir: focusAreasDir)
        let combinedCost = totalCost + focusAreaCost

        let summary = calculateSummary(violations: violations, totalTasks: totalTasks, totalCost: combinedCost, modelsUsed: modelsUsed)

        let sortedViolations = violations.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.filePath < $1.filePath
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return ReviewReport(
            prNumber: prNumber,
            generatedAt: formatter.string(from: Date()),
            minScoreThreshold: minScore,
            summary: summary,
            violations: sortedViolations
        )
    }

    /// Save report to JSON and markdown files.
    public func saveReport(report: ReviewReport, reportDir: String) throws -> (jsonPath: String, mdPath: String) {
        try FileManager.default.createDirectory(atPath: reportDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(report)

        let jsonPath = "\(reportDir)/\(DataPathsService.summaryJSONFilename)"
        try jsonData.write(to: URL(fileURLWithPath: jsonPath))

        let mdPath = "\(reportDir)/\(DataPathsService.summaryMarkdownFilename)"
        try report.toMarkdown().write(toFile: mdPath, atomically: true, encoding: .utf8)

        return (jsonPath, mdPath)
    }

    // MARK: - Private

    private func loadViolations(
        evaluationsDir: String,
        tasksDir: String,
        minScore: Int
    ) -> ([ViolationRecord], Int, Double, [String]) {
        let fm = FileManager.default
        var violations: [ViolationRecord] = []
        var totalTasks = 0
        var totalCost = 0.0
        var modelSet = Set<String>()

        let taskMetadata = loadTaskMetadata(tasksDir: tasksDir)

        guard let evalFiles = try? fm.contentsOfDirectory(atPath: evaluationsDir) else {
            return (violations, totalTasks, totalCost, [])
        }

        for file in evalFiles where file.hasPrefix(DataPathsService.dataFilePrefix) {
            let path = "\(evaluationsDir)/\(file)"
            guard let data = fm.contents(atPath: path) else { continue }

            guard let result = try? JSONDecoder().decode(RuleEvaluationResult.self, from: data) else { continue }
            totalTasks += 1
            modelSet.insert(result.modelUsed)

            if let cost = result.costUsd {
                totalCost += cost
            }

            guard let v = result.violation, v.evaluation.score >= minScore else { continue }

            let filePath = v.filePath.isEmpty ? v.evaluation.filePath : v.filePath

            let documentationLink: String?
            let relevantClaudeSkill: String?
            let methodName: String?

            if let taskData = taskMetadata[v.taskId] {
                documentationLink = taskData.rule.documentationLink
                relevantClaudeSkill = nil
                methodName = taskData.focusArea.description
            } else {
                documentationLink = nil
                relevantClaudeSkill = nil
                methodName = nil
            }

            violations.append(ViolationRecord(
                ruleName: v.ruleName,
                score: v.evaluation.score,
                filePath: filePath,
                lineNumber: v.evaluation.lineNumber,
                comment: v.evaluation.comment,
                methodName: methodName,
                documentationLink: documentationLink,
                relevantClaudeSkill: relevantClaudeSkill
            ))
        }

        return (violations, totalTasks, totalCost, modelSet.sorted())
    }

    private func loadFocusAreaGenerationCost(focusAreasDir: String) -> Double {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: focusAreasDir) else { return 0.0 }

        var total = 0.0
        for file in files where file.hasPrefix(DataPathsService.dataFilePrefix) {
            let path = "\(focusAreasDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let typeOutput = try? JSONDecoder().decode(FocusAreaTypeOutput.self, from: data) else { continue }
            total += typeOutput.generationCostUsd
        }
        return total
    }

    private func loadTaskMetadata(tasksDir: String) -> [String: AnalysisTaskOutput] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: tasksDir) else { return [:] }

        var metadata: [String: AnalysisTaskOutput] = [:]
        for file in files where file.hasPrefix(DataPathsService.dataFilePrefix) {
            let path = "\(tasksDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let task = try? JSONDecoder().decode(AnalysisTaskOutput.self, from: data) else { continue }
            metadata[task.taskId] = task
        }
        return metadata
    }

    private func calculateSummary(
        violations: [ViolationRecord],
        totalTasks: Int,
        totalCost: Double,
        modelsUsed: [String]
    ) -> ReportSummary {
        let highestSeverity = violations.map(\.score).max() ?? 0

        var bySeverity: [String: Int] = [:]
        for v in violations {
            let level: String
            if v.score >= 8 {
                level = "Severe (8-10)"
            } else if v.score >= 5 {
                level = "Moderate (5-7)"
            } else {
                level = "Minor (1-4)"
            }
            bySeverity[level, default: 0] += 1
        }

        var byFile: [String: Int] = [:]
        for v in violations {
            byFile[v.filePath, default: 0] += 1
        }

        var byRule: [String: Int] = [:]
        for v in violations {
            byRule[v.ruleName, default: 0] += 1
        }

        var byMethod: [String: [String: [[String: AnyCodableValue]]]] = [:]
        for v in violations {
            let methodKey = v.methodName ?? "(unknown)"
            var fileDict = byMethod[v.filePath] ?? [:]
            var methodList = fileDict[methodKey] ?? []
            methodList.append([
                "rule": .string(v.ruleName),
                "score": .int(v.score),
            ])
            fileDict[methodKey] = methodList
            byMethod[v.filePath] = fileDict
        }

        return ReportSummary(
            totalTasksEvaluated: totalTasks,
            violationsFound: violations.count,
            highestSeverity: highestSeverity,
            totalCostUsd: totalCost,
            bySeverity: bySeverity,
            byFile: byFile,
            byRule: byRule,
            byMethod: byMethod.isEmpty ? nil : byMethod,
            modelsUsed: modelsUsed
        )
    }
}
