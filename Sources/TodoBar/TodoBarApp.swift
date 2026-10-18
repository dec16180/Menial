import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct TodoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI lives in the status item's popover (see AppDelegate).
        Settings { EmptyView() }
    }
}

/// Owns the menu bar icon and its popover. An NSPopover is used instead of
/// SwiftUI's MenuBarExtra because it always resizes to fit its content, so
/// there's no oversized, see-through window around the list.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TodoStore()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var iconWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(
            rootView: ContentView()
                .environmentObject(store)
                .environmentObject(store.git)
        )
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        iconWatch = store.$items.sink { [weak self] items in
            let allDone = !items.contains { !$0.isDone }
            Task { @MainActor in self?.setIcon(allDone ? "checklist.checked" : "checklist") }
        }
    }

    private func setIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Todos")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
