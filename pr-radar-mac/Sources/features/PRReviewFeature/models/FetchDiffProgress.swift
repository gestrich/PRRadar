public enum FetchDiffProgress: Sendable {
    case running
    case completed(files: [String])
    case failed(error: String)
}
