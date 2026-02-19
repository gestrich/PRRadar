import Foundation

public actor InactivityWatchdog {
    private let timeout: TimeInterval
    private let onTimeout: @Sendable () -> Void
    private var lastActivity = Date()
    private var task: Task<Void, Never>?

    public init(timeout: TimeInterval, onTimeout: @escaping @Sendable () -> Void) {
        self.timeout = timeout
        self.onTimeout = onTimeout
    }

    public func start() {
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { return }
                let elapsed = Date().timeIntervalSince(lastActivity)
                if elapsed >= timeout {
                    onTimeout()
                    return
                }
            }
        }
    }

    public func recordActivity() {
        lastActivity = Date()
    }

    public func cancel() {
        task?.cancel()
    }
}
