import AppKit
import PRRadarConfigService
import SwiftUI

@main
struct PRRadarMacApp: App {
    @State private var model: PRReviewModel

    init() {
        let bridgeScriptPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // main.swift → MacApp/
            .deletingLastPathComponent() // → apps/
            .deletingLastPathComponent() // → Sources/
            .deletingLastPathComponent() // → pr-radar-mac/
            .appendingPathComponent("bridge/claude_bridge.py")
            .path
        _model = State(initialValue: PRReviewModel(
            bridgeScriptPath: bridgeScriptPath
        ))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
