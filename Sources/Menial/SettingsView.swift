// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var git: GitSync

    @AppStorage(Prefs.gitAutoCommitKey) private var gitAutoCommit = true
    @AppStorage(Prefs.gitSyncKey) private var gitSync = false

    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var loginError: String?

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings").font(.headline)
                HStack {
                    Button(action: onClose) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                            Text("Todos")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(12)

            Divider()

            Form {
                Section("Todo file") {
                    Text(store.displayPath)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack {
                        Button("Choose…") {
                            if let url = FilePanels.chooseExisting() { store.useFile(url) }
                        }
                        Button("New…") {
                            if let url = FilePanels.createNew() { store.useFile(url) }
                        }
                        Spacer()
                        Button("Show in Finder") { store.revealInFinder() }
                    }
                }

                gitSection

                Section("General") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { setLaunchAtLogin($0) }
                    ))
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(height: 480)
    }

    // MARK: - Git

    private var gitSection: some View {
        Section {
            if let root = git.displayRoot {
                LabeledContent("Repository") {
                    Text(root)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Toggle("Commit changes automatically", isOn: $gitAutoCommit)
                Toggle("Pull and push to remote", isOn: $gitSync)
                    .disabled(!git.hasRemote)
                HStack(spacing: 8) {
                    Button("Commit Now") { git.commitNow() }
                    if gitSync && git.hasRemote {
                        Button("Sync Now") { git.syncNow() }
                    }
                    if git.working { ProgressView().controlSize(.small) }
                    Spacer()
                    if let lastCommit = git.lastCommit {
                        Text("Last commit \(lastCommit, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if git.accessDenied {
                Label("macOS isn't letting Menial's git into “\(folderName)”.", systemImage: "lock.fill")
                    .font(.callout)
                Text("Allow Menial to access this folder — answer the macOS prompt with Allow, or turn Menial on in System Settings → Privacy & Security → Files & Folders. This happens for cloud-storage folders and after the app is renamed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Check Again") { git.refresh() }
                        .disabled(git.working)
                }
            } else {
                Text("\(store.fileURL.lastPathComponent) isn't in a git repository.")
                    .font(.callout)
                Button("Create Repository in “\(folderName)”") { git.createRepository() }
                    .disabled(git.working)
                if isBroadFolder {
                    Text("Tip: put the todo file in its own folder first (New… above), so the repository only holds your todos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error = git.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Git history")
                .onAppear { git.refresh() }
        } footer: {
            Text(git.hasRemote || git.repoRoot == nil
                ? "Only the todo file and its images and files folders are committed; other files in the repository are left alone."
                : "Only the todo file and its images and files folders are committed. Add a remote (git remote add origin …) to sync.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var folderName: String {
        store.fileURL.deletingLastPathComponent().lastPathComponent
    }

    /// Home, Documents, Desktop… — folders where a repository would sit over lots of unrelated files.
    private var isBroadFolder: Bool {
        let folder = store.fileURL.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let broad = [home] + [.documentDirectory, .desktopDirectory, .downloadsDirectory]
            .compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first?.standardizedFileURL }
        return broad.contains { $0.path == folder.path }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum FilePanels {
    private static var markdownTypes: [UTType] {
        [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown"), UTType.plainText].compactMap { $0 }
    }

    @MainActor
    static func chooseExisting() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose your todo file"
        panel.message = "Pick a Markdown file. Menial reads and writes its checklist items."
        panel.allowedContentTypes = markdownTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func createNew() -> URL? {
        let panel = NSSavePanel()
        panel.title = "New todo file"
        panel.nameFieldStringValue = "Todos.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
