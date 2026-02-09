import Testing
@testable import PRRadarModels

// MARK: - Helpers

private func makeRemoved(_ filePath: String, _ lineNumber: Int, _ content: String, hunkIndex: Int = 0) -> TaggedLine {
    TaggedLine(
        content: content,
        normalized: content.trimmingCharacters(in: .whitespaces),
        filePath: filePath,
        lineNumber: lineNumber,
        hunkIndex: hunkIndex,
        lineType: .removed
    )
}

private func makeAdded(_ filePath: String, _ lineNumber: Int, _ content: String, hunkIndex: Int = 1) -> TaggedLine {
    TaggedLine(
        content: content,
        normalized: content.trimmingCharacters(in: .whitespaces),
        filePath: filePath,
        lineNumber: lineNumber,
        hunkIndex: hunkIndex,
        lineType: .added
    )
}

private func makeMatch(_ removed: TaggedLine, _ added: TaggedLine, distance: Int? = nil) -> LineMatch {
    let d = distance ?? abs(removed.hunkIndex - added.hunkIndex)
    return LineMatch(removed: removed, added: added, distance: d, similarity: 1.0)
}

// MARK: - Tests: computeSizeFactor

@Suite struct SizeFactorTests {

    @Test func belowMinimumReturnsZero() {
        let block = (1...2).map { makeMatch(makeRemoved("a.py", $0, "l\($0)"), makeAdded("b.py", $0, "l\($0)")) }
        #expect(computeSizeFactor(block, minBlockSize: 3) == 0.0)
    }

    @Test func atMinimumReturnsBaseline() {
        let block = (1...3).map { makeMatch(makeRemoved("a.py", $0, "l\($0)"), makeAdded("b.py", $0, "l\($0)")) }
        let factor = computeSizeFactor(block, minBlockSize: 3)
        #expect(factor > 0.0)
        #expect(factor < 1.0)
    }

    @Test func largeBlockReturnsOne() {
        let block = (1...14).map { makeMatch(makeRemoved("a.py", $0, "l\($0)"), makeAdded("b.py", $0, "l\($0)")) }
        #expect(computeSizeFactor(block, minBlockSize: 3) == 1.0)
    }

    @Test func tenLinesReturnsOne() {
        let block = (1...10).map { makeMatch(makeRemoved("a.py", $0, "l\($0)"), makeAdded("b.py", $0, "l\($0)")) }
        #expect(computeSizeFactor(block, minBlockSize: 3) == 1.0)
    }

    @Test func monotonicallyIncreasing() {
        var factors: [Double] = []
        for size in 3...11 {
            let block = (1...size).map { makeMatch(makeRemoved("a.py", $0, "l\($0)"), makeAdded("b.py", $0, "l\($0)")) }
            factors.append(computeSizeFactor(block, minBlockSize: 3))
        }
        for i in 1..<factors.count {
            #expect(factors[i] >= factors[i - 1])
        }
    }

    @Test func emptyBlockReturnsZero() {
        #expect(computeSizeFactor([], minBlockSize: 3) == 0.0)
    }

    @Test func singleLineReturnsZero() {
        let block = [makeMatch(makeRemoved("a.py", 1, "x"), makeAdded("b.py", 1, "x"))]
        #expect(computeSizeFactor(block, minBlockSize: 3) == 0.0)
    }
}

// MARK: - Tests: computeLineUniqueness

@Suite struct LineUniquenessTests {

    @Test func uniqueLinesScoreOne() {
        let addedPool = (1...3).map { makeAdded("b.py", $0, "unique_line_\($0)") }
        let block = (0..<3).map { makeMatch(makeRemoved("a.py", $0 + 1, "unique_line_\($0 + 1)"), addedPool[$0]) }
        let uniqueness = computeLineUniqueness(block, allAddedLines: addedPool)
        #expect(abs(uniqueness - 1.0) < 0.001)
    }

    @Test func duplicateLinesReduceUniqueness() {
        let addedPool = (1...3).map { makeAdded("b.py", $0, "return None") }
        let block = [makeMatch(makeRemoved("a.py", 1, "return None"), addedPool[0])]
        let uniqueness = computeLineUniqueness(block, allAddedLines: addedPool)
        #expect(abs(uniqueness - 1.0 / 3.0) < 0.001)
    }

    @Test func mixedUniqueness() {
        let addedPool = [
            makeAdded("b.py", 1, "unique_domain_logic"),
            makeAdded("b.py", 2, "return None"),
            makeAdded("b.py", 3, "return None"),
        ]
        let block = [
            makeMatch(makeRemoved("a.py", 1, "unique_domain_logic"), addedPool[0]),
            makeMatch(makeRemoved("a.py", 2, "return None"), addedPool[1]),
        ]
        let uniqueness = computeLineUniqueness(block, allAddedLines: addedPool)
        let expected = (1.0 + 0.5) / 2.0
        #expect(abs(uniqueness - expected) < 0.001)
    }

    @Test func emptyBlockReturnsZero() {
        #expect(computeLineUniqueness([], allAddedLines: []) == 0.0)
    }

    @Test func largePoolLowersCommonLineScore() {
        let addedPool = (1...10).map { makeAdded("b.py", $0, "return None") }
        let block = [makeMatch(makeRemoved("a.py", 1, "return None"), addedPool[0])]
        let uniqueness = computeLineUniqueness(block, allAddedLines: addedPool)
        #expect(abs(uniqueness - 0.1) < 0.001)
    }
}

// MARK: - Tests: computeMatchConsistency

@Suite struct MatchConsistencyTests {

    @Test func perfectlyConsecutiveTargetsHighConsistency() {
        let block = (1...5).map { makeMatch(makeRemoved("a.py", $0, "l\($0)"), makeAdded("b.py", $0, "l\($0)")) }
        let consistency = computeMatchConsistency(block)
        #expect(consistency >= 0.9)
    }

    @Test func singleMatchReturnsOne() {
        let block = [makeMatch(makeRemoved("a.py", 1, "x"), makeAdded("b.py", 1, "x"))]
        #expect(computeMatchConsistency(block) == 1.0)
    }

    @Test func scatteredTargetsLowerConsistency() {
        let block = [
            makeMatch(makeRemoved("a.py", 1, "l1"), makeAdded("b.py", 1, "l1")),
            makeMatch(makeRemoved("a.py", 2, "l2"), makeAdded("b.py", 50, "l2")),
            makeMatch(makeRemoved("a.py", 3, "l3"), makeAdded("b.py", 100, "l3")),
        ]
        let consistency = computeMatchConsistency(block)
        #expect(consistency < 1.0)
    }

    @Test func consecutiveBetterThanScattered() {
        let consecutive = (1...5).map {
            makeMatch(makeRemoved("a.py", $0, "l\($0)"), makeAdded("b.py", $0 + 10, "l\($0)"))
        }
        let scattered = [
            makeMatch(makeRemoved("a.py", 1, "l1"), makeAdded("b.py", 1, "l1")),
            makeMatch(makeRemoved("a.py", 2, "l2"), makeAdded("b.py", 20, "l2")),
            makeMatch(makeRemoved("a.py", 3, "l3"), makeAdded("b.py", 5, "l3")),
            makeMatch(makeRemoved("a.py", 4, "l4"), makeAdded("b.py", 40, "l4")),
            makeMatch(makeRemoved("a.py", 5, "l5"), makeAdded("b.py", 10, "l5")),
        ]
        #expect(computeMatchConsistency(consecutive) > computeMatchConsistency(scattered))
    }
}

// MARK: - Tests: computeDistanceFactor

@Suite struct DistanceFactorTests {

    @Test func distanceZeroReturnsZero() {
        let block = [makeMatch(makeRemoved("a.py", 1, "x", hunkIndex: 0), makeAdded("a.py", 1, "x", hunkIndex: 0), distance: 0)]
        #expect(computeDistanceFactor(block) == 0.0)
    }

    @Test func distanceOneReturnsHalf() {
        let block = [makeMatch(makeRemoved("a.py", 1, "x", hunkIndex: 0), makeAdded("b.py", 1, "x", hunkIndex: 1), distance: 1)]
        #expect(abs(computeDistanceFactor(block) - 0.5) < 0.001)
    }

    @Test func distanceTwoReturnsOne() {
        let block = [makeMatch(makeRemoved("a.py", 1, "x", hunkIndex: 0), makeAdded("b.py", 1, "x", hunkIndex: 2), distance: 2)]
        #expect(abs(computeDistanceFactor(block) - 1.0) < 0.001)
    }

    @Test func largeDistanceCappedAtOne() {
        let block = [makeMatch(makeRemoved("a.py", 1, "x", hunkIndex: 0), makeAdded("b.py", 1, "x", hunkIndex: 10), distance: 10)]
        #expect(computeDistanceFactor(block) == 1.0)
    }
}

// MARK: - Tests: scoreBlock (composite)

@Suite struct ScoreBlockTests {

    @Test func goodBlockScoresPositive() {
        let addedPool = (1...5).map { makeAdded("b.py", $0, "unique_line_\($0)") }
        let block = (0..<5).map { makeMatch(makeRemoved("a.py", $0 + 1, "unique_line_\($0 + 1)"), addedPool[$0]) }
        let score = scoreBlock(block, allAddedLines: addedPool)
        #expect(score > 0)
    }

    @Test func tinyBlockScoresZero() {
        let addedPool = [makeAdded("b.py", 1, "x"), makeAdded("b.py", 2, "y")]
        let block = [
            makeMatch(makeRemoved("a.py", 1, "x"), addedPool[0]),
            makeMatch(makeRemoved("a.py", 2, "y"), addedPool[1]),
        ]
        #expect(scoreBlock(block, allAddedLines: addedPool) == 0.0)
    }

    @Test func genericLinesScoreLowerThanUnique() {
        let genericPool = (1...19).map { makeAdded("b.py", $0, "return None") }
        let genericBlock = (0..<5).map { makeMatch(makeRemoved("a.py", $0 + 1, "return None"), genericPool[$0]) }

        let uniquePool = (1...5).map { makeAdded("d.py", $0, "domain_logic_\($0)") }
        let uniqueBlock = (0..<5).map { makeMatch(makeRemoved("c.py", $0 + 1, "domain_logic_\($0 + 1)"), uniquePool[$0]) }

        let genericScore = scoreBlock(genericBlock, allAddedLines: genericPool)
        let uniqueScore = scoreBlock(uniqueBlock, allAddedLines: uniquePool)
        #expect(uniqueScore > genericScore)
    }

    @Test func largerBlockScoresHigher() {
        let smallPool = (1...3).map { makeAdded("b.py", $0, "line_\($0)") }
        let smallBlock = (0..<3).map { makeMatch(makeRemoved("a.py", $0 + 1, "line_\($0 + 1)"), smallPool[$0]) }

        let largePool = (1...10).map { makeAdded("b.py", $0, "line_\($0)") }
        let largeBlock = (0..<10).map { makeMatch(makeRemoved("a.py", $0 + 1, "line_\($0 + 1)"), largePool[$0]) }

        #expect(scoreBlock(largeBlock, allAddedLines: largePool) > scoreBlock(smallBlock, allAddedLines: smallPool))
    }

    @Test func allFactorsContribute() {
        let addedPool = (1...5).map { makeAdded("b.py", $0, "unique_\($0)") }
        let block = (0..<5).map { makeMatch(makeRemoved("a.py", $0 + 1, "unique_\($0 + 1)"), addedPool[$0]) }
        let score = scoreBlock(block, allAddedLines: addedPool)

        let size = computeSizeFactor(block)
        let uniqueness = computeLineUniqueness(block, allAddedLines: addedPool)
        let consistency = computeMatchConsistency(block)
        let distance = computeDistanceFactor(block)

        #expect(abs(score - size * uniqueness * consistency * distance) < 0.001)
    }
}
