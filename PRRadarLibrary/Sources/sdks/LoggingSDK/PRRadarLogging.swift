import Foundation
import Logging

public enum PRRadarLogging {
    public static let defaultLogFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PRRadar/prradar.log")
    }()

    public static func bootstrap(logFileURL: URL = defaultLogFileURL) {
        LoggingSystem.bootstrap { label in
            FileLogHandler(label: label, fileURL: logFileURL)
        }
    }
}
