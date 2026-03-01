import Foundation

public enum AnalysisMethod: Sendable, Equatable, Hashable {
    case ai(model: String, costUsd: Double)
    case regex(pattern: String)

    public var displayName: String {
        switch self {
        case .ai(let model, _): PRRadarModels.displayName(forModelId: model)
        case .regex: "Regex"
        }
    }

    public var costUsd: Double {
        switch self {
        case .ai(_, let cost): cost
        case .regex: 0
        }
    }
}

// MARK: - Codable

extension AnalysisMethod: Codable {

    private enum CodingKeys: String, CodingKey {
        case type
        case model
        case costUsd
        case pattern
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ai":
            let model = try container.decode(String.self, forKey: .model)
            let cost = try container.decode(Double.self, forKey: .costUsd)
            self = .ai(model: model, costUsd: cost)
        case "regex":
            let pattern = try container.decode(String.self, forKey: .pattern)
            self = .regex(pattern: pattern)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown analysis method type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ai(let model, let costUsd):
            try container.encode("ai", forKey: .type)
            try container.encode(model, forKey: .model)
            try container.encode(costUsd, forKey: .costUsd)
        case .regex(let pattern):
            try container.encode("regex", forKey: .type)
            try container.encode(pattern, forKey: .pattern)
        }
    }
}
