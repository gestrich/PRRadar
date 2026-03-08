import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels

struct PRFilterOptions: ParsableArguments {
    @Option(name: .long, help: "Date in YYYY-MM-DD format (filter by created date)")
    var since: String?

    @Option(name: .long, help: "PRs updated in the last N hours")
    var lookbackHours: Int?

    @Option(name: .long, help: "Date in YYYY-MM-DD format (filter by updated date)")
    var updatedSince: String?

    @Option(name: .long, help: "PRs updated in the last N hours")
    var updatedLookbackHours: Int?

    @Option(name: .long, help: "PR state filter: open, draft, closed, merged, all")
    var state: String?

    @Option(name: .long, help: "Filter by target branch (default: config's defaultBaseBranch, use 'all' to skip)")
    var baseBranch: String?

    @Option(name: .long, help: "Filter by PR author (GitHub login handle)")
    var author: String?

    func buildFilter(config: RepositoryConfiguration) throws -> PRFilter {
        try validateMutualExclusivity()

        let dateFilter: PRDateFilter?
        if let updatedSince {
            guard let date = parseDateString(updatedSince) else {
                throw ValidationError("Invalid date format for --updated-since: \(updatedSince). Use YYYY-MM-DD.")
            }
            dateFilter = .updatedSince(date)
        } else if let hours = updatedLookbackHours {
            dateFilter = .updatedSince(Date.now.addingTimeInterval(-Double(hours) * 3600))
        } else if let since {
            guard let date = parseDateString(since) else {
                throw ValidationError("Invalid date format for --since: \(since). Use YYYY-MM-DD.")
            }
            dateFilter = .createdSince(date)
        } else if let hours = lookbackHours {
            dateFilter = .updatedSince(Date.now.addingTimeInterval(-Double(hours) * 3600))
        } else {
            dateFilter = nil
        }

        let stateFilter: PRState? = try parseStateFilter(state)
        return config.makeFilter(dateFilter: dateFilter, state: stateFilter, baseBranch: baseBranch, authorLogin: author)
    }

    private func validateMutualExclusivity() throws {
        let createdOptions = [since != nil, lookbackHours != nil]
        let updatedOptions = [updatedSince != nil, updatedLookbackHours != nil]

        if createdOptions.filter({ $0 }).count > 1 {
            throw ValidationError("--since and --lookback-hours are mutually exclusive")
        }
        if updatedOptions.filter({ $0 }).count > 1 {
            throw ValidationError("--updated-since and --updated-lookback-hours are mutually exclusive")
        }
        let hasCreated = createdOptions.contains(true)
        let hasUpdated = updatedOptions.contains(true)
        if hasCreated && hasUpdated {
            throw ValidationError("Cannot combine created-date filters (--since/--lookback-hours) with updated-date filters (--updated-since/--updated-lookback-hours)")
        }
    }
}
