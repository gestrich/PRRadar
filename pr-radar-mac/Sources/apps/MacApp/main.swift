import AppKit
import PRRadarConfigService
import SwiftUI

@main
struct PRRadarMacApp: App {
    let bridgeScriptPath: String

    init() {
        bridgeScriptPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // main.swift → MacApp/
            .deletingLastPathComponent() // → apps/
            .deletingLastPathComponent() // → Sources/
            .deletingLastPathComponent() // → pr-radar-mac/
            .appendingPathComponent("bridge/claude_bridge.py")
            .path

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(bridgeScriptPath: bridgeScriptPath)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
