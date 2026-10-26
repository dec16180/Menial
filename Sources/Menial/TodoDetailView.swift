// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The details window for one todo: notes, subtasks, images and attached files.
@MainActor
struct TodoDetailView: View {
    @EnvironmentObject private var store: TodoStore
    let itemID: UUID

    @ViewState private var newSubtask = ""
    @ViewState private var dropTargeted = false

    var body: some View {
        Group {
            if let item = store.item(itemID) {
                content(item)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "trash").font(.title2).foregroundStyle(.secondary)
                    Text("This todo was deleted.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 380, minHeight: 360)
    }

    private func content(_ item: TodoItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(item)
                notes
                subtasks(item)
                images(item)
                attachments(item)
            }
            .padding(20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .opacity(dropTargeted ? 1 : 0)
                .padding(4)
        )
        // Dropped images go to Images, any other file to Attachments.
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted, perform: handleDrop)
    }

    // MARK: - Header

    private func header(_ item: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                store.toggle(item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(item.priority?.color ?? (item.isDone ? Color.accentColor : Color.secondary))
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as open" : "Mark as done")

            VStack(alignment: .leading, spacing: 8) {
                CommitField(text: item.text, placeholder: "Todo") { store.rename(item.id, to: $0) }
                    .font(.title3.weight(.semibold))
                    .strikethrough(item.isDone, color: .secondary)
                PriorityPicker(selection: item.priority) { store.setPriority(item.id, $0) }
            }
        }
    }

    // MARK: - Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Notes", systemImage: "note.text")
            TextEditor(text: Binding(
                get: { store.item(itemID)?.notes ?? "" },
                set: { store.setNotes(itemID, $0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    // MARK: - Subtasks

    private func subtasks(_ item: TodoItem) -> some View {
        let done = item.subtasks.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                item.subtasks.isEmpty ? "Subtasks" : "Subtasks (\(done)/\(item.subtasks.count))",
                systemImage: "checklist"
            )
            ForEach(item.subtasks) { sub in
                SubtaskRow(itemID: item.id, subtask: sub)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 18)
                TextField("Add a subtask", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        store.addSubtask(itemID, newSubtask)
                        newSubtask = ""
                    }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Images

    private func images(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Images", systemImage: "photo")
                Spacer()
                Button("Paste") { pasteImages() }
                    .help("Attach a screenshot or copied files from the clipboard")
                Button("Add Images…") { chooseImages() }
            }
            .buttonStyle(.link)
            .font(.callout)

            if item.images.isEmpty {
                Text("Drop images here, paste a screenshot, or click Add Images…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.tertiary)
                    )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(item.images, id: \.self) { path in
                        ImageThumb(url: store.imageURL(path)) { store.removeImage(item.id, path) }
                    }
                }
            }
        }
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose images to attach to this todo"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { store.addImages(itemID, from: panel.urls) }
    }

    // MARK: - Attachments

    private func attachments(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Attachments", systemImage: "paperclip")
                Spacer()
                Button("Add Files…") { chooseFiles() }
                    .buttonStyle(.link)
                    .font(.callout)
            }

            if item.attachments.isEmpty {
                Text("Drop any file here, or click Add Files…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.tertiary)
                    )
            } else {
                VStack(spacing: 2) {
                    ForEach(item.attachments, id: \.self) { file in
                        AttachmentRow(name: file.name, url: store.imageURL(file.path)) {
                            store.removeAttachment(item.id, file)
                        }
                    }
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose files to attach to this todo"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { store.addAttachments(itemID, from: panel.urls) }
    }

    private func addFiles(_ urls: [URL]) {
        let images = urls.filter(Self.isImageFile)
        let others = urls.filter { !Self.isImageFile($0) }
        if !images.isEmpty { store.addImages(itemID, from: images) }
        if !others.isEmpty { store.addAttachments(itemID, from: others) }
    }

    private func pasteImages() {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            addFiles(urls)
        } else if let image = NSImage(pasteboard: pasteboard), let png = image.pngData {
            store.addImage(itemID, pngData: png)
        } else {
            NSSound.beep()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let store = store
        let id = itemID
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let isImage = Self.isImageFile(url)
                    Task { @MainActor in
                        if isImage {
                            store.addImages(id, from: [url])
                        } else {
                            store.addAttachments(id, from: [url])
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let png = (image as? NSImage)?.pngData else { return }
                    Task { @MainActor in store.addImage(id, pngData: png) }
                }
            }
        }
        return handled
    }

    nonisolated private static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Pieces

/// A plain text field that saves as you type — no Return needed, closing the
/// window is enough — and follows outside changes while you're not typing in it.
@MainActor
private struct CommitField: View {
    let text: String
    let placeholder: String
    let onCommit: (String) -> Void

    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { draft = text }
            .onChange(of: text) { newValue in
                if !focused { draft = newValue }
            }
            .onChange(of: draft) { newValue in
                // Empty text isn't saved; it snaps back when you leave the field.
                if focused, !MarkdownCodec.singleLine(newValue).isEmpty, newValue != text {
                    onCommit(newValue)
                }
            }
            .onChange(of: focused) { isFocused in
                if !isFocused { finish() }
            }
            .onSubmit(finish)
            .onDisappear(perform: finish)
    }

    private func finish() {
        if !MarkdownCodec.singleLine(draft).isEmpty, draft != text { onCommit(draft) }
        // Show what was stored, e.g. "Pay rent" after typing "Pay rent !1".
        draft = text
    }
}

@MainActor
private struct SubtaskRow: View {
    @EnvironmentObject private var store: TodoStore
    let itemID: UUID
    let subtask: Subtask

    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.toggleSubtask(itemID, subtask.id)
            } label: {
                Image(systemName: subtask.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(subtask.isDone ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            CommitField(text: subtask.text, placeholder: "Subtask") {
                store.renameSubtask(itemID, subtask.id, to: $0)
            }
            .strikethrough(subtask.isDone, color: .secondary)
            .foregroundStyle(subtask.isDone ? Color.secondary : Color.primary)

            IconButton("xmark", help: "Delete subtask", size: 10) {
                store.deleteSubtask(itemID, subtask.id)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

@MainActor
private struct ImageThumb: View {
    let url: URL
    let onRemove: () -> Void

    @ViewState private var image: CGImage?
    @ViewState private var failed = false
    @ViewState private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The whole image, scaled to fit: cropping to a square made wide
            // screenshots unrecognisable.
            thumbnail
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture { if !failed { ImagePreviewWindows.shared.show(url) } }
                .help(failed ? "Missing: \(url.path)" : "Click to preview \(url.lastPathComponent)")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(4)
            .opacity(hovering ? 1 : 0)
            .help("Remove image")
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Preview") { ImagePreviewWindows.shared.show(url) }
            Button("Open in Preview") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
        .task(id: url) {
            let loaded = await Task.detached { Self.loadThumbnail(url) }.value
            image = loaded
            failed = loaded == nil
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(decorative: image, scale: 2)
                .resizable()
                .scaledToFit()
                .padding(4)
        } else {
            Color.clear
                .overlay(
                    Image(systemName: failed ? "exclamationmark.triangle" : "photo")
                        .foregroundStyle(.secondary)
                )
        }
    }

    nonisolated private static func loadThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

@MainActor
private struct AttachmentRow: View {
    let name: String
    let url: URL
    let onRemove: () -> Void

    @ViewState private var hovering = false

    private var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
                .opacity(exists ? 1 : 0.4)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(exists ? Color.primary : Color.secondary)
            Spacer(minLength: 4)
            Text(exists ? sizeText : "Missing")
                .font(.caption)
                .foregroundStyle(.secondary)
            IconButton("xmark", help: "Remove attachment", size: 10, action: onRemove)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onHover { hovering = $0 }
        .help(exists ? "Click to open \(name)" : "Missing: \(url.path)")
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private var sizeText: String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return "Folder" }
        return ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
