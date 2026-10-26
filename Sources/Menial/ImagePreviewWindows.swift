// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// Shows an attached image large, in its own window (one per image).
@MainActor
final class ImagePreviewWindows: NSObject, NSWindowDelegate {
    static let shared = ImagePreviewWindows()

    private var windows: [URL: NSWindow] = [:]

    func show(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = windows[url] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let image = NSImage(contentsOf: url) else {
            NSSound.beep()
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: ImagePreview(image: image, url: url)))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = url.lastPathComponent
        window.setContentSize(Self.fittingSize(for: image.size))
        window.contentMinSize = NSSize(width: 200, height: 150)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        windows[url] = window
        window.makeKeyAndOrderFront(nil)
    }

    /// The image's own size, shrunk to at most 80 % of the screen.
    private static func fittingSize(for size: NSSize) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let maxSize = NSSize(width: screen.width * 0.8, height: screen.height * 0.8)
        guard size.width > 0, size.height > 0 else { return NSSize(width: 600, height: 400) }
        let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
        return NSSize(width: max(200, size.width * scale), height: max(150, size.height * scale))
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let url = windows.first(where: { $0.value === window })?.key else { return }
        windows[url] = nil
    }
}

private struct ImagePreview: View {
    let image: NSImage
    let url: URL

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .contextMenu {
                Button("Open in Preview") { NSWorkspace.shared.open(url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
    }
}
