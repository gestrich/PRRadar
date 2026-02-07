import Foundation

// MARK: - Phase 2: Focus Area Models

public enum FocusType: String, Codable, Sendable {
    case file
    case method
}

/// A focus area identified by the pipeline, matching Python's FocusArea.to_dict()
public struct FocusArea: Codable, Sendable {
    public let focusId: String
    public let filePath: String
    public let startLine: Int
    public let endLine: Int
    public let description: String
    public let hunkIndex: Int
    public let hunkContent: String
    public let focusType: FocusType

    enum CodingKeys: String, CodingKey {
        case focusId = "focus_id"
        case filePath = "file_path"
        case startLine = "start_line"
        case endLine = "end_line"
        case description
        case hunkIndex = "hunk_index"
        case hunkContent = "hunk_content"
        case focusType = "focus_type"
    }
}
