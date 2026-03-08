import Testing
@testable import PRRadarModels

@Suite("DurationFormatter")
struct DurationFormatterTests {

    // MARK: - Sub-second

    @Test("Formats zero milliseconds")
    func zeroMs() {
        #expect(DurationFormatter.format(milliseconds: 0) == "0.0s")
    }

    @Test("Formats sub-second durations")
    func subSecond() {
        #expect(DurationFormatter.format(milliseconds: 500) == "0.5s")
        #expect(DurationFormatter.format(milliseconds: 100) == "0.1s")
        #expect(DurationFormatter.format(milliseconds: 999) == "1.0s")
    }

    // MARK: - Seconds

    @Test("Formats durations under one minute")
    func seconds() {
        #expect(DurationFormatter.format(milliseconds: 1000) == "1.0s")
        #expect(DurationFormatter.format(milliseconds: 12300) == "12.3s")
        #expect(DurationFormatter.format(milliseconds: 59999) == "60.0s")
    }

    // MARK: - Minutes

    @Test("Formats durations in minutes")
    func minutes() {
        #expect(DurationFormatter.format(milliseconds: 60000) == "1m 00s")
        #expect(DurationFormatter.format(milliseconds: 125000) == "2m 05s")
        #expect(DurationFormatter.format(milliseconds: 3599000) == "59m 59s")
    }

    // MARK: - Hours

    @Test("Formats durations in hours")
    func hours() {
        #expect(DurationFormatter.format(milliseconds: 3600000) == "1h 00m 00s")
        #expect(DurationFormatter.format(milliseconds: 3661000) == "1h 01m 01s")
        #expect(DurationFormatter.format(milliseconds: 7200000) == "2h 00m 00s")
    }
}
