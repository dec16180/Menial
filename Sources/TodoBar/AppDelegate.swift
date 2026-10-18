import AppKit
import Combine
import SwiftUI

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
        NSApp.mainMenu = Self.makeMainMenu()
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

    /// Lets a pending git commit finish before the app quits (Quit button or ⌘Q).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await store.git.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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

    /// No menu bar is visible (menu bar app), but the main menu still provides the
    /// keyboard shortcuts: ⌘C/⌘V/⌘X/⌘A/⌘Z in text fields and ⌘W to close a details window.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Quit TodoBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "TodoBar", action: nil, keyEquivalent: "").submenu = app

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = file

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        return main
    }
}
