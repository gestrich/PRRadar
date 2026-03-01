import Foundation
import Testing
@testable import PRRadarModels

// MARK: - Helpers

private func loadFixture(_ name: String) throws -> String {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "EffectiveDiffFixtures")!
    return try String(contentsOf: url, encoding: .utf8)
}

private func gitRediff(_ oldText: String, _ newText: String, _ oldLabel: String, _ newLabel: String) async throws -> String {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let oldPath = tmpDir.appendingPathComponent("old.txt")
    let newPath = tmpDir.appendingPathComponent("new.txt")
    try oldText.write(to: oldPath, atomically: true, encoding: .utf8)
    try newText.write(to: newPath, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["diff", "--no-index", "--no-color", oldPath.path, newPath.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    var raw = String(data: data, encoding: .utf8) ?? ""

    if raw.isEmpty { return "" }

    let oldRel = String(oldPath.path.dropFirst())
    let newRel = String(newPath.path.dropFirst())
    raw = raw.replacingOccurrences(of: "a/\(oldRel)", with: "a/\(oldLabel)")
    raw = raw.replacingOccurrences(of: "b/\(newRel)", with: "b/\(newLabel)")

    return raw
}

private func runPipeline(
    diffText: String,
    oldFiles: [String: String],
    newFiles: [String: String]
) async throws -> (effectiveDiff: GitDiff, report: EffectiveDiffMoveReport) {
    let result = try await runEffectiveDiffPipeline(
        gitDiff: GitDiff.fromDiffContent(diffText, commitHash: ""),
        oldFiles: oldFiles,
        newFiles: newFiles,
        rediff: gitRediff
    )
    return (result.effectiveDiff, result.moveReport)
}

private func getChangedLines(_ diff: GitDiff) -> [String] {
    var lines: [String] = []
    for hunk in diff.hunks {
        for dl in hunk.getDiffLines() {
            if dl.lineType == .added || dl.lineType == .removed {
                lines.append(dl.rawLine)
            }
        }
    }
    return lines
}

// MARK: - End-to-End Tests

@Suite struct EffectiveDiffEndToEndTests {

    // Fixture 1: Pure move, no changes

    @Test func pureMoveProducesEmptyEffectiveDiff() async throws {
        let diffText = try loadFixture("pure_move.diff")
        let oldFiles = [
            "utils.py": "def calculate_total(items):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n"
        ]
        let newFiles = [
            "helpers.py": "def calculate_total(items):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(effectiveDiff.hunks.count == 0, "Pure move should produce no effective hunks")
        #expect(report.movesDetected == 1)
        #expect(report.totalLinesMoved > 0)
        #expect(report.totalLinesEffectivelyChanged == 0)
    }

    // Fixture 2: Move with signature change

    @Test func moveWithSignatureChangeShowsOnlySignature() async throws {
        let diffText = try loadFixture("move_with_signature_change.diff")
        let oldFiles = [
            "utils.py": "def calc_total(items):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n"
        ]
        let newFiles = [
            "helpers.py": "def calculate_total(items, tax=0):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(report.movesDetected == 1)
        #expect(report.totalLinesEffectivelyChanged > 0)

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("calc_total") }, "Should contain old signature")
        #expect(changed.contains { $0.contains("calculate_total") }, "Should contain new signature")
        #expect(!changed.contains { $0.contains("total += item.price") }, "Body lines should not appear in effective diff")
    }

    // Fixture 3: Move with interior gap

    @Test func moveWithInteriorGapShowsOnlyChangedLine() async throws {
        let diffText = try loadFixture("move_with_interior_gap.diff")
        let oldFiles = [
            "services.py": "def process_order(order):\n    validate(order)\n    total = sum(order.items)\n    tax = total * 0.08\n    order.total = total + tax\n    order.save()\n    return order\n"
        ]
        let newFiles = [
            "handlers.py": "def process_order(order):\n    validate(order)\n    total = sum(order.line_items)\n    tax = total * 0.08\n    order.total = total + tax\n    order.save()\n    return order\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(report.movesDetected == 1)
        #expect(report.totalLinesEffectivelyChanged > 0)

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("order.items") }, "Should contain old line")
        #expect(changed.contains { $0.contains("order.line_items") }, "Should contain new line")
        #expect(!changed.contains { $0.contains("order.save()") }, "Unchanged lines should not appear as changes")
    }

    // Fixture 4: Move with added comments

    @Test func moveWithAddedCommentsShowsOnlyDocstring() async throws {
        let diffText = try loadFixture("move_with_added_comments.diff")
        let oldFiles = [
            "utils.py": "def validate(order):\n    if not order.items:\n        raise ValueError()\n    return True\n"
        ]
        let newFiles = [
            "helpers.py": "def validate(order):\n    \"\"\"Validate order has items.\"\"\"\n    if not order.items:\n        raise ValueError()\n    return True\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(report.movesDetected == 1)
        #expect(report.totalLinesEffectivelyChanged > 0)

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("Validate order has items") }, "Should contain the added docstring")
        #expect(!changed.contains { $0.contains("raise ValueError") }, "Existing body lines should not be in effective diff")
    }

    // Fixture 5: Same-file method swap

    @Test func sameFileSwapProducesNoExtraHunks() async throws {
        let diffText = try loadFixture("same_file_swap.diff")
        let oldFiles = [
            "services.py": "def method_a():\n    return \"a\"\n\ndef method_b():\n    return \"b\"\n"
        ]
        let newFiles = [
            "services.py": "def method_b():\n    return \"b\"\n\ndef method_a():\n    return \"a\"\n"
        ]

        let (effectiveDiff, _) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(effectiveDiff.hunks.count <= 1)
    }

    // Fixture 6: Same-file swap with change

    @Test func sameFileSwapWithChangeShowsRealChange() async throws {
        let diffText = try loadFixture("same_file_swap_with_change.diff")
        let oldFiles = [
            "services.py": "def method_a():\n    return \"a\"\n\ndef method_b():\n    return \"b\"\n"
        ]
        let newFiles = [
            "services.py": "def method_b():\n    return \"b\"\n\ndef method_a():\n    return \"a_modified\"\n"
        ]

        let (effectiveDiff, _) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("a_modified") }, "Should contain the modified return value")
    }

    // Fixture 7: Move with multiple interior gaps

    @Test func moveWithMultipleGapsShowsAllChanges() async throws {
        let diffText = try loadFixture("move_with_multiple_gaps.diff")
        let oldFiles = [
            "processor.py": "def process(data):\n    step1(data)\n    x = transform(data)\n    validate(x)\n    y = compute(x)\n    log(y)\n    z = finalize(y)\n    if z.ready:\n        emit(z)\n    cleanup()\n"
        ]
        let newFiles = [
            "handler.py": "def process(data):\n    step1(data)\n    x = transform_v2(data)\n    validate(x)\n    y = compute(x)\n    log(y)\n    z = finalize(y)\n    if z.ready:\n        emit_async(z)\n    cleanup()\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(report.movesDetected == 1)
        #expect(report.totalLinesEffectivelyChanged > 0)

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("transform(data)") && !$0.contains("transform_v2") }, "Should show old transform line")
        #expect(changed.contains { $0.contains("transform_v2") }, "Should show new transform_v2 line")
        #expect(changed.contains { $0.contains("emit(z)") && !$0.contains("emit_async") }, "Should show old emit line")
        #expect(changed.contains { $0.contains("emit_async") }, "Should show new emit_async line")
    }

    // Fixture 8: Partial move

    @Test func partialMovePreservesNonMovedChanges() async throws {
        let diffText = try loadFixture("partial_move.diff")
        let oldFiles = [
            "big_module.py": "def func_a():\n    return \"a1\"\n    return \"a2\"\n    return \"a3\"\n\ndef func_b():\n    return \"b1\"\n    return \"b2\"\n    return \"b3\"\n\ndef func_c():\n    return \"c1\"\n    return \"c2\"\n    return \"c3\"\n\ndef func_d():\n    return \"d1\"\n"
        ]
        let newFiles = [
            "big_module.py": "def func_c():\n    return \"c1_modified\"\n    return \"c2\"\n    return \"c3\"\n\ndef func_d():\n    return \"d1\"\n",
            "small_module.py": "def func_a():\n    return \"a1\"\n    return \"a2\"\n    return \"a3\"\n\ndef func_b():\n    return \"b1\"\n    return \"b2\"\n    return \"b3\"\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(report.movesDetected > 0, "Should detect at least one move")

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("c1_modified") }, "Change to func_c should be in effective diff")
        #expect(effectiveDiff.hunks.count > 0, "Should have at least one hunk for func_c change")
    }

    // Fixture 9: Move with indentation change

    @Test func moveWithIndentationChangeDetected() async throws {
        let diffText = try loadFixture("move_with_indentation.diff")
        let oldFiles = [
            "utils.py": "def save(data):\n    db.insert(data)\n    return True\n"
        ]
        let newFiles = [
            "models.py": "class DataManager:\n    def save(self, data):\n        db.insert(data)\n        return True\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        if report.movesDetected > 0 {
            let changed = getChangedLines(effectiveDiff)
            #expect(changed.contains { $0.contains("self") }, "Should show the signature change adding self")
        } else {
            #expect(effectiveDiff.hunks.count > 0)
        }
    }

    // Fixture 10: Small block not a move

    @Test func smallBlockNotClassifiedAsMove() async throws {
        let diffText = try loadFixture("small_block_not_a_move.diff")
        let oldFiles = [
            "file_a.py": "def do_something():\n    x = compute()\n    return None\n    log(\"done\")\n    finish()\n"
        ]
        let newFiles = [
            "file_a.py": "def do_something():\n    x = compute()\n    log(\"done\")\n    finish()\n",
            "file_b.py": "def do_other():\n    y = prepare()\n    return None\n    process(y)\n    cleanup()\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(report.movesDetected == 0, "Single generic line should not be a move")
        #expect(effectiveDiff.hunks.count > 0, "Original hunks should survive")

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("return None") }, "return None should remain as a normal change")
    }

    // Fixture 11: Move adjacent to new code

    @Test func moveAdjacentToNewCodePreservesNewCode() async throws {
        let diffText = try loadFixture("move_adjacent_to_new_code.diff")
        let oldFiles = [
            "utils.py": "def calculate_total(items):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n"
        ]
        let newFiles = [
            "handlers.py": "def brand_new_function():\n    do_new_stuff()\n    return \"new\"\n\ndef calculate_total(items):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n\ndef another_new_function():\n    do_other_stuff()\n    return \"other\"\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(report.movesDetected == 1, "calculate_total should be detected as move")

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("brand_new_function") }, "brand_new_function should be in effective diff")
        #expect(changed.contains { $0.contains("another_new_function") }, "another_new_function should be in effective diff")

        let movedBodyAsChange = changed.filter { $0.contains("total += item.price") }
        #expect(movedBodyAsChange.count == 0, "Moved method body should be context, not changes")
    }

    // Fixture 12: Move with whitespace-only changes

    @Test func whitespaceOnlyMoveIsPure() async throws {
        let diffText = try loadFixture("move_whitespace_only.diff")
        let oldFiles = [
            "utils.py": "def process(data):\n    step1(data)\n    step2(data)\n    step3(data)\n    return data\n"
        ]
        let newFiles = [
            "helpers.py": "def process(data):\n    step1(data)\n    step2(data)\n    step3(data)\n    return data\n"
        ]

        let (effectiveDiff, report) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        #expect(effectiveDiff.hunks.count == 0, "Pure move should produce no effective hunks")
        #expect(report.movesDetected == 1)
        #expect(report.totalLinesEffectivelyChanged == 0)
    }

    // Fixture 13: Large file reorganization

    @Test func largeReorgIsolatesOnlyRealChange() async throws {
        let diffText = try loadFixture("large_reorg.diff")
        let oldFiles = [
            "services.py": "def method_one():\n    return \"one_a\"\n    return \"one_b\"\n    return \"one_c\"\n\ndef method_two():\n    return \"two_a\"\n    return \"two_b\"\n    return \"two_c\"\n\ndef method_three():\n    return \"three_a\"\n    return \"three_b\"\n    return \"three_c\"\n\ndef method_four():\n    return \"four_a\"\n    return \"four_b\"\n    return \"four_c\"\n\ndef method_five():\n    return \"five_a\"\n    return \"five_b\"\n    return \"five_c\"\n"
        ]
        let newFiles = [
            "services.py": "def method_five():\n    return \"five_a\"\n    return \"five_b_changed\"\n    return \"five_c\"\n\ndef method_four():\n    return \"four_a\"\n    return \"four_b\"\n    return \"four_c\"\n\ndef method_three():\n    return \"three_a\"\n    return \"three_b\"\n    return \"three_c\"\n\ndef method_two():\n    return \"two_a\"\n    return \"two_b\"\n    return \"two_c\"\n\ndef method_one():\n    return \"one_a\"\n    return \"one_b\"\n    return \"one_c\"\n"
        ]

        let (effectiveDiff, _) = try await runPipeline(diffText: diffText, oldFiles: oldFiles, newFiles: newFiles)

        let changed = getChangedLines(effectiveDiff)
        #expect(changed.contains { $0.contains("five_b_changed") }, "The real change to method_five should survive")
    }
}
