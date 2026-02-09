import MacApp
import SwiftUI

@main
struct PRRadarApp: App {
    @State private var appModel: AppModel

    init() {
        let bridgePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PRRadar/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("PRRadarLibrary/bridge/claude_bridge.py")
            .path
        _appModel = State(initialValue: AppModel(bridgeScriptPath: bridgePath))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
