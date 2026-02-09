import Foundation

/// Returns a short human-readable display name for a Claude model API identifier.
///
/// Known models are mapped to friendly names (e.g. `"claude-sonnet-4-20250514"` → `"Sonnet 4"`).
/// Unknown identifiers are returned as-is.
public func displayName(forModelId modelId: String) -> String {
    let patterns: [(prefix: String, name: String)] = [
        ("claude-opus-4", "Opus 4"),
        ("claude-sonnet-4-5", "Sonnet 4.5"),
        ("claude-sonnet-4", "Sonnet 4"),
        ("claude-haiku-4-5", "Haiku 4.5"),
        ("claude-haiku-4", "Haiku 4"),
        ("claude-3-5-sonnet", "Sonnet 3.5"),
        ("claude-3-5-haiku", "Haiku 3.5"),
        ("claude-3-opus", "Opus 3"),
        ("claude-3-sonnet", "Sonnet 3"),
        ("claude-3-haiku", "Haiku 3"),
    ]

    for pattern in patterns {
        if modelId.hasPrefix(pattern.prefix) {
            return pattern.name
        }
    }

    return modelId
}
