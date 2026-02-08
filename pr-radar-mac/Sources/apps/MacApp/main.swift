import AppKit
import PRRadarConfigService
import SwiftUI

@main
struct PRRadarMacApp: App {
    @State private var allPRs: AllPRsModel

    init() {
        let bridgeScriptPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // main.swift → MacApp/
            .deletingLastPathComponent() // → apps/
            .deletingLastPathComponent() // → Sources/
            .deletingLastPathComponent() // → pr-radar-mac/
            .appendingPathComponent("bridge/claude_bridge.py")
            .path

        let settingsService = SettingsService()
        let settings = settingsService.load()
        let defaultConfig = settings.defaultConfiguration ?? settings.configurations.first ?? RepoConfiguration(name: "Default", repoPath: "")

        let config = PRRadarConfig(
            repoPath: defaultConfig.repoPath,
            outputDir: defaultConfig.outputDir,
            bridgeScriptPath: bridgeScriptPath,
            githubToken: defaultConfig.githubToken
        )

        _allPRs = State(initialValue: AllPRsModel(
            config: config,
            repoConfig: defaultConfig,
            settingsService: settingsService
        ))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(allPRs)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
