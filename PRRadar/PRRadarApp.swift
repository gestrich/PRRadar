import MacApp
import SwiftUI

@main
struct PRRadarApp: App {
    let bridgeScriptPath: String

    init() {
        bridgeScriptPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PRRadar/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("PRRadarLibrary/bridge/claude_bridge.py")
            .path
    }

    var body: some Scene {
        WindowGroup {
            ContentView(bridgeScriptPath: bridgeScriptPath)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
