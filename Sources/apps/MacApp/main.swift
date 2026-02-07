// Placeholder — real app entry point will be created in Phase 2
import SwiftUI

@main
struct MacAppMain: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some Scene {
        WindowGroup {
            Text("PRRadar")
        }
        .defaultSize(width: 700, height: 600)
    }
}
