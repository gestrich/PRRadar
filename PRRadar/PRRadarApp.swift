import MacApp
import SwiftUI

@main
struct PRRadarApp: App {
    @State private var appModel: AppModel

    init() {
        let agentScriptPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PRRadar/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("PRRadarLibrary/claude-agent/claude_agent.py")
            .path
        _appModel = State(initialValue: AppModel(agentScriptPath: agentScriptPath))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
