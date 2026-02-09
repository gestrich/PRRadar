import Testing
@testable import PRRadarModels

@Suite("Model Display Name")
struct ModelDisplayNameTests {

    @Test("Maps Sonnet 4 model ID to display name")
    func sonnet4() {
        // Arrange
        let modelId = "claude-sonnet-4-20250514"

        // Act
        let name = displayName(forModelId: modelId)

        // Assert
        #expect(name == "Sonnet 4")
    }

    @Test("Maps Sonnet 4.5 model ID to display name")
    func sonnet45() {
        // Arrange
        let modelId = "claude-sonnet-4-5-20250929"

        // Act
        let name = displayName(forModelId: modelId)

        // Assert
        #expect(name == "Sonnet 4.5")
    }

    @Test("Maps Haiku 4.5 model ID to display name")
    func haiku45() {
        // Arrange
        let modelId = "claude-haiku-4-5-20251001"

        // Act
        let name = displayName(forModelId: modelId)

        // Assert
        #expect(name == "Haiku 4.5")
    }

    @Test("Maps Opus 4 model ID to display name")
    func opus4() {
        // Arrange
        let modelId = "claude-opus-4-20250514"

        // Act
        let name = displayName(forModelId: modelId)

        // Assert
        #expect(name == "Opus 4")
    }

    @Test("Maps Sonnet 3.5 model ID to display name")
    func sonnet35() {
        // Arrange
        let modelId = "claude-3-5-sonnet-20241022"

        // Act
        let name = displayName(forModelId: modelId)

        // Assert
        #expect(name == "Sonnet 3.5")
    }

    @Test("Returns raw ID for unknown model")
    func unknownModel() {
        // Arrange
        let modelId = "some-future-model-v99"

        // Act
        let name = displayName(forModelId: modelId)

        // Assert
        #expect(name == "some-future-model-v99")
    }
}
