// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import AppKit
import Combine
import SwiftUI

/// Opens one details window per todo and keeps its title in sync with the todo.
@MainActor
final class DetailWindows: NSObject, NSWindowDelegate {
    static let shared = DetailWindows()

    private var windows: [UUID: NSWindow] = [:]
    private var titleWatch: AnyCancellable?

    func open(_ id: UUID, store: TodoStore) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: TodoDetailView(itemID: id).environmentObject(store))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = store.item(id)?.text ?? "Todo"
        window.setContentSize(NSSize(width: 480, height: 620))
        window.contentMinSize = NSSize(width: 380, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let last = windows.values.first(where: \.isVisible) {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else {
            window.center()
        }
        windows[id] = window
        window.makeKeyAndOrderFront(nil)

        if titleWatch == nil {
            titleWatch = store.$items.sink { [weak self] items in
                Task { @MainActor in self?.updateTitles(items) }
            }
        }
    }

    private func updateTitles(_ items: [TodoItem]) {
        for (id, window) in windows {
            if let item = items.first(where: { $0.id == id }), window.title != item.text {
                window.title = item.text
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
    }
}
