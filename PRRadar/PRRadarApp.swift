import MacApp
import SwiftUI

@main
struct PRRadarApp: App {
    @State private var settingsModel: SettingsModel
    @State private var appModel: AppModel

    init() {
        let agentScriptPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PRRadar/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("PRRadarLibrary/claude-agent/claude_agent.py")
            .path
        let settings = SettingsModel()
        _settingsModel = State(initialValue: settings)
        _appModel = State(initialValue: AppModel(agentScriptPath: agentScriptPath, settingsModel: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(settingsModel)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
