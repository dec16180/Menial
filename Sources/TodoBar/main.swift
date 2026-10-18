import AppKit

// Plain AppKit entry point. A SwiftUI `App` needs at least one scene, and its
// placeholder Settings scene would pop up as an empty window when the app activates.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
