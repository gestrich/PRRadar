import Foundation
import PRRadarModels

// MARK: - Result Model

/// Result of focus area generation for a single focus type.
public struct FocusGenerationResult: Sendable {
    public let prNumber: Int
    public let focusAreas: [FocusArea]
    public let totalHunksProcessed: Int
    public let generationCostUsd: Double

    public init(prNumber: Int, focusAreas: [FocusArea], totalHunksProcessed: Int, generationCostUsd: Double) {
        self.prNumber = prNumber
        self.focusAreas = focusAreas
        self.totalHunksProcessed = totalHunksProcessed
        self.generationCostUsd = generationCostUsd
    }
}

// MARK: - Service

/// Generates focus areas (reviewable units of code) from diff hunks.
///
/// For method-level focus areas, calls Claude Haiku via the bridge script to
/// identify individual methods/functions in each hunk. For file-level focus areas,
/// groups all hunks per file without an AI call.
public struct FocusGeneratorService: Sendable {
    public static let defaultModel = "claude-haiku-4-5-20251001"

    private let bridgeClient: ClaudeBridgeClient
    private let model: String

    public init(bridgeClient: ClaudeBridgeClient, model: String = FocusGeneratorService.defaultModel) {
        self.bridgeClient = bridgeClient
        self.model = model
    }

    /// Generate focus areas for a single hunk via the Claude bridge.
    public func generateFocusAreasForHunk(
        _ hunk: Hunk,
        hunkIndex: Int
    ) async throws -> (focusAreas: [FocusArea], costUsd: Double) {
        let annotatedContent = hunk.getAnnotatedContent()

        let prompt = Self.focusGenerationPrompt
            .replacingOccurrences(of: "{file_path}", with: hunk.filePath)
            .replacingOccurrences(of: "{hunk_index}", with: String(hunkIndex))
            .replacingOccurrences(of: "{hunk_content}", with: annotatedContent)

        let request = BridgeRequest(
            prompt: prompt,
            model: model,
            outputSchema: Self.focusGenerationSchema
        )

        var result: BridgeResult?
        for try await event in bridgeClient.stream(request) {
            switch event {
            case .text(let content):
                for textLine in content.components(separatedBy: "\n") {
                    print("      \(textLine)", terminator: "\n")
                }
            case .toolUse:
                break
            case .result(let bridgeResult):
                result = bridgeResult
            }
        }

        guard let result else {
            throw ClaudeBridgeError.noResult
        }

        guard let output = result.outputAsDictionary(),
              let methods = output["methods"] as? [[String: Any]],
              !methods.isEmpty else {
            return (fallbackFocusArea(hunk: hunk, hunkIndex: hunkIndex, annotatedContent: annotatedContent), result.costUsd)
        }

        var focusAreas: [FocusArea] = []
        for method in methods {
            let methodName = method["method_name"] as? String ?? "hunk \(hunkIndex)"
            let startLine = method["start_line"] as? Int ?? hunk.newStart
            let endLine = method["end_line"] as? Int ?? (hunk.newStart + hunk.newLength - 1)

            let safePath = hunk.filePath.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
            let safeMethod = sanitizeForId(methodName)
            let focusId = "\(safePath)-\(hunkIndex)-\(safeMethod)"

            focusAreas.append(FocusArea(
                focusId: focusId,
                filePath: hunk.filePath,
                startLine: startLine,
                endLine: endLine,
                description: methodName,
                hunkIndex: hunkIndex,
                hunkContent: annotatedContent,
                focusType: .method
            ))
        }

        return (focusAreas, result.costUsd)
    }

    /// Generate file-level focus areas by grouping hunks per file.
    ///
    /// No AI call needed — aggregates all hunks for each file into a single
    /// `FocusArea` with `FocusType.file`.
    public func generateFileFocusAreas(hunks: [Hunk]) -> [FocusArea] {
        var hunksByFile: [String: [(index: Int, hunk: Hunk)]] = [:]
        for (i, hunk) in hunks.enumerated() {
            hunksByFile[hunk.filePath, default: []].append((i, hunk))
        }

        var focusAreas: [FocusArea] = []
        for (filePath, indexedHunks) in hunksByFile {
            var allAnnotated: [String] = []
            var minStart: Int?
            var maxEnd: Int?

            for (_, hunk) in indexedHunks {
                allAnnotated.append(hunk.getAnnotatedContent())
                let hunkEnd = hunk.newStart + hunk.newLength - 1
                if minStart == nil || hunk.newStart < minStart! { minStart = hunk.newStart }
                if maxEnd == nil || hunkEnd > maxEnd! { maxEnd = hunkEnd }
            }

            let safePath = filePath.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")

            focusAreas.append(FocusArea(
                focusId: safePath,
                filePath: filePath,
                startLine: minStart ?? 0,
                endLine: maxEnd ?? 0,
                description: filePath,
                hunkIndex: indexedHunks[0].index,
                hunkContent: allAnnotated.joined(separator: "\n\n"),
                focusType: .file
            ))
        }

        return focusAreas
    }

    /// Generate all focus areas for a diff's hunks.
    ///
    /// - Parameters:
    ///   - hunks: Parsed diff hunks
    ///   - prNumber: PR number being analyzed
    ///   - requestedTypes: Focus types to generate. Defaults to `[.file]`.
    /// - Returns: `FocusGenerationResult` per type requested
    public func generateAllFocusAreas(
        hunks: [Hunk],
        prNumber: Int,
        requestedTypes: Set<FocusType> = [.file]
    ) async throws -> [FocusType: FocusGenerationResult] {
        var results: [FocusType: FocusGenerationResult] = [:]

        if requestedTypes.contains(.method) {
            var methodAreas: [FocusArea] = []
            var totalCost: Double = 0.0

            for (i, hunk) in hunks.enumerated() {
                let (areas, cost) = try await generateFocusAreasForHunk(hunk, hunkIndex: i)
                methodAreas.append(contentsOf: areas)
                totalCost += cost
            }

            results[.method] = FocusGenerationResult(
                prNumber: prNumber,
                focusAreas: methodAreas,
                totalHunksProcessed: hunks.count,
                generationCostUsd: totalCost
            )
        }

        if requestedTypes.contains(.file) {
            let fileAreas = generateFileFocusAreas(hunks: hunks)
            results[.file] = FocusGenerationResult(
                prNumber: prNumber,
                focusAreas: fileAreas,
                totalHunksProcessed: hunks.count,
                generationCostUsd: 0.0
            )
        }

        return results
    }

    // MARK: - Private

    private static let focusGenerationPrompt = """
    Analyze this diff hunk and identify all methods/functions that were added, modified, or removed.

    File: {file_path}
    Hunk index: {hunk_index}

    ```diff
    {hunk_content}
    ```

    For each method/function you identify, provide:
    1. **method_name**: The function/method name and its signature (e.g., "login(username, password)")
    2. **start_line**: First line number in the new file where the method starts
    3. **end_line**: Last line number in the new file where the method ends

    Rules:
    - Only include methods/functions that have added (+) or removed (-) lines
    - If the hunk contains changes outside of any method (e.g., module-level code, imports), create a single entry with method_name describing the change (e.g., "module-level imports")
    - Use the line numbers from the annotated diff (the numbers before the colon)
    - If no distinct methods are found, return a single entry covering the entire hunk with a descriptive name
    """

    nonisolated(unsafe) private static let focusGenerationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "methods": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "method_name": [
                            "type": "string",
                            "description": "Method/function name and signature",
                        ],
                        "start_line": [
                            "type": "integer",
                            "description": "First line number in new file",
                        ],
                        "end_line": [
                            "type": "integer",
                            "description": "Last line number in new file",
                        ],
                    ] as [String: Any],
                    "required": ["method_name", "start_line", "end_line"],
                ] as [String: Any],
            ] as [String: Any],
        ] as [String: Any],
        "required": ["methods"],
    ]

    private func fallbackFocusArea(hunk: Hunk, hunkIndex: Int, annotatedContent: String) -> [FocusArea] {
        let safePath = hunk.filePath.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        return [FocusArea(
            focusId: "\(safePath)-\(hunkIndex)",
            filePath: hunk.filePath,
            startLine: hunk.newStart,
            endLine: hunk.newStart + hunk.newLength - 1,
            description: "hunk \(hunkIndex)",
            hunkIndex: hunkIndex,
            hunkContent: annotatedContent,
            focusType: .method
        )]
    }

    private func sanitizeForId(_ name: String) -> String {
        var sanitized = name.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? name
        sanitized = sanitized.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        sanitized = sanitized.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        let trimmed = String(sanitized.prefix(50))
        return trimmed.isEmpty ? "unknown" : trimmed
    }
}
