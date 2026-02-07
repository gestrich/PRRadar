import AppKit
import SwiftUI
import PRRadarConfigService

@main
struct PRRadarMacApp: App {
    @State private var model: PRReviewModel

    init() {
        let venvBinPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // main.swift → MacApp/
            .deletingLastPathComponent() // → apps/
            .deletingLastPathComponent() // → Sources/
            .deletingLastPathComponent() // → pr-radar-mac/
            .deletingLastPathComponent() // → repo root
            .appendingPathComponent(".venv/bin")
            .path
        let environment = PRRadarEnvironment.build(venvBinPath: venvBinPath)
        _model = State(initialValue: PRReviewModel(
            venvBinPath: venvBinPath,
            environment: environment
        ))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 700, height: 600)
    }
}
