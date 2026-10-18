import AppKit
import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published var errorMessage: String?
    @Published private(set) var fileURL: URL

    /// Commits the todo file, its images and attachments to git after changes.
    let git = GitSync()

    private var knownModificationDate: Date?
    private var loadFailed = false
    private var watchTimer: Timer?
    private var renameBursts: [UUID: (origin: String, last: Date)] = [:]

    var openItems: [TodoItem] { MarkdownCodec.byPriority(items.filter { !$0.isDone }) }
    var doneItems: [TodoItem] { items.filter { $0.isDone } }
    var displayPath: String { (fileURL.path as NSString).abbreviatingWithTildeInPath }

    init() {
        fileURL = Prefs.fileURL
        load()
        startWatching()
        configureGit()
    }

    // MARK: - Editing

    func add(_ raw: String) {
        // Typing "Pay rent !1" sets the priority.
        let (text, priority) = MarkdownCodec.splitPriority(MarkdownCodec.singleLine(raw))
        guard !text.isEmpty else { return }
        items.insert(TodoItem(text: text, priority: priority), at: 0)
        save("Add “\(text)”")
    }

    func toggle(_ id: UUID) {
        mutate(id, item(id)?.isDone == true ? "Reopen" : "Complete") { $0.isDone.toggle() }
    }

    func rename(_ id: UUID, to raw: String) {
        let (text, priority) = MarkdownCodec.splitPriority(MarkdownCodec.singleLine(raw))
        guard !text.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }

        // Titles save on every keystroke; remember the title from before this burst
        // of typing so the commit says "Rename “old” to “new”" once.
        let now = Date()
        var burst = renameBursts[id] ?? (origin: items[i].text, last: now)
        if now.timeIntervalSince(burst.last) > 10 { burst.origin = items[i].text }
        burst.last = now
        renameBursts[id] = burst

        items[i].text = text
        if let priority { items[i].priority = priority }
        save("Rename “\(burst.origin)” to “\(text)”", replacing: "rename:\(id)")
    }

    func setPriority(_ id: UUID, _ priority: Priority?) {
        guard let item = item(id), item.priority != priority else { return }
        mutate(id, priority.map { "Set priority \($0.rawValue) for" } ?? "Clear priority of") { $0.priority = priority }
    }

    func delete(_ id: UUID) {
        guard let item = item(id) else { return }
        items.removeAll { $0.id == id }
        save("Delete “\(item.text)”")
        deleteFilesIfUnused(item.images + item.attachments.map(\.path))
    }

    func clearDone() {
        let done = doneItems
        guard !done.isEmpty else { return }
        items.removeAll { $0.isDone }
        save("Clear \(done.count) done todo\(done.count == 1 ? "" : "s")")
        deleteFilesIfUnused(done.flatMap { $0.images + $0.attachments.map(\.path) })
    }

    func item(_ id: UUID) -> TodoItem? {
        items.first { $0.id == id }
    }

    // MARK: - Details

    func setNotes(_ id: UUID, _ notes: String) {
        guard item(id)?.notes != notes else { return }
        mutate(id, "Edit notes of") { $0.notes = notes }
    }

    func addSubtask(_ id: UUID, _ raw: String) {
        let text = MarkdownCodec.singleLine(raw)
        guard !text.isEmpty else { return }
        mutate(id, "Add subtask to") { $0.subtasks.append(Subtask(text: text)) }
    }

    func toggleSubtask(_ id: UUID, _ subID: UUID) {
        mutateSubtask(id, subID, "Check off subtask of") { $0.isDone.toggle() }
    }

    func renameSubtask(_ id: UUID, _ subID: UUID, to raw: String) {
        let text = MarkdownCodec.singleLine(raw)
        guard !text.isEmpty else { return }
        mutateSubtask(id, subID, "Edit subtask of") { $0.text = text }
    }

    func deleteSubtask(_ id: UUID, _ subID: UUID) {
        mutate(id, "Delete subtask of") { $0.subtasks.removeAll { $0.id == subID } }
    }

    private func mutateSubtask(_ id: UUID, _ subID: UUID, _ change: String, _ edit: (inout Subtask) -> Void) {
        mutate(id, change) { item in
            guard let i = item.subtasks.firstIndex(where: { $0.id == subID }) else { return }
            edit(&item.subtasks[i])
        }
    }

    // MARK: - Images and attachments

    /// Folders next to the todo file that hold copied-in images and files,
    /// e.g. `Todos-images` and `Todos-files`.
    private var imagesFolderName: String { folderName("images") }
    private var filesFolderName: String { folderName("files") }

    private func folderName(_ suffix: String) -> String {
        fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "-") + "-" + suffix
    }

    private var fileDirectory: URL {
        fileURL.resolvingSymlinksInPath().deletingLastPathComponent()
    }

    private var imagesDirectory: URL {
        fileDirectory.appendingPathComponent(imagesFolderName, isDirectory: true)
    }

    private var filesDirectory: URL {
        fileDirectory.appendingPathComponent(filesFolderName, isDirectory: true)
    }

    /// Resolves a path from the Markdown file (relative to the file, absolute, or `~/…`).
    func imageURL(_ path: String) -> URL {
        let decoded = path.removingPercentEncoding ?? path
        let expanded = (decoded as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return fileDirectory.appendingPathComponent(expanded)
    }

    /// Copies the files into the images folder and attaches them.
    func addImages(_ id: UUID, from urls: [URL]) {
        let paths = urls.compactMap { url in
            storeImage(ext: url.pathExtension) { try FileManager.default.copyItem(at: url, to: $0) }
        }
        guard !paths.isEmpty else { return }
        mutate(id, "Add image to") { $0.images.append(contentsOf: paths) }
    }

    func addImage(_ id: UUID, pngData: Data) {
        guard let path = storeImage(ext: "png", write: { try pngData.write(to: $0) }) else { return }
        mutate(id, "Add image to") { $0.images.append(path) }
    }

    func removeImage(_ id: UUID, _ path: String) {
        mutate(id, "Remove image from") { $0.images.removeAll { $0 == path } }
        deleteFilesIfUnused([path])
    }

    /// Copies any files (or folders) into the files folder, keeping their names.
    func addAttachments(_ id: UUID, from urls: [URL]) {
        let fm = FileManager.default
        var added: [Attachment] = []
        for url in urls {
            do {
                try fm.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
                let target = uniqueURL(for: url.lastPathComponent, in: filesDirectory)
                try fm.copyItem(at: url, to: target)
                added.append(Attachment(name: url.lastPathComponent, path: "\(filesFolderName)/\(target.lastPathComponent)"))
            } catch {
                errorMessage = "Couldn't attach \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        guard !added.isEmpty else { return }
        let label = added.count == 1 ? "“\(added[0].name)”" : "\(added.count) files"
        mutate(id, "Attach \(label) to") { $0.attachments.append(contentsOf: added) }
    }

    func removeAttachment(_ id: UUID, _ attachment: Attachment) {
        mutate(id, "Remove “\(attachment.name)” from") { $0.attachments.removeAll { $0 == attachment } }
        deleteFilesIfUnused([attachment.path])
    }

    /// "Report.pdf", then "Report 2.pdf", "Report 3.pdf"… if the name is taken.
    private func uniqueURL(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    private func storeImage(ext: String, write: (URL) throws -> Void) -> String? {
        let name = UUID().uuidString.prefix(8).lowercased() + "." + (ext.isEmpty ? "png" : ext.lowercased())
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try write(imagesDirectory.appendingPathComponent(name))
            return "\(imagesFolderName)/\(name)"
        } catch {
            errorMessage = "Couldn't add the image: \(error.localizedDescription)"
            return nil
        }
    }

    /// Removes images and files TodoBar copied in, once no todo refers to them any more.
    /// Anything outside its own folders (files you linked by hand) is never touched.
    private func deleteFilesIfUnused(_ paths: [String]) {
        let folders = Set([imagesDirectory, filesDirectory].map { $0.standardizedFileURL.path })
        let stillUsed = Set(
            items.flatMap { $0.images + $0.attachments.map(\.path) }.map { imageURL($0).standardizedFileURL.path }
        )
        for path in paths {
            let url = imageURL(path).standardizedFileURL
            guard folders.contains(url.deletingLastPathComponent().path), !stillUsed.contains(url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - File

    func useFile(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Prefs.filePathKey)
        fileURL = url
        load()
        if !FileManager.default.fileExists(atPath: url.path) { save("Create todo file") }
        configureGit()
    }

    func openInEditor() {
        if !FileManager.default.fileExists(atPath: fileURL.path) { save("Create todo file") }
        NSWorkspace.shared.open(fileURL)
    }

    func revealInFinder() {
        if !FileManager.default.fileExists(atPath: fileURL.path) { save("Create todo file") }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func configureGit() {
        git.configure(file: fileURL.resolvingSymlinksInPath(), folders: [imagesDirectory, filesDirectory])
    }

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            items = []
            loadFailed = false
            knownModificationDate = nil
            return
        }
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            items = carryOverIDs(MarkdownCodec.parse(text))
            loadFailed = false
            knownModificationDate = modificationDate()
        } catch {
            // Never overwrite a file we couldn't read.
            loadFailed = true
            knownModificationDate = modificationDate()
            errorMessage = "Couldn't read \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Writes the file and queues a git commit described by `change`.
    private func save(_ change: String, replacing key: String? = nil) {
        guard !loadFailed else {
            errorMessage = "Not saving, because \(fileURL.lastPathComponent) couldn't be read. Choose another file in Settings."
            return
        }
        let target = fileURL.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try MarkdownCodec.serialize(items).write(to: target, atomically: true, encoding: .utf8)
            knownModificationDate = modificationDate()
            git.record(change, replacing: key)
        } catch {
            errorMessage = "Couldn't save \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Picks up edits you make to the file in another app (Obsidian, an editor, sync, git pull…).
    private func startWatching() {
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChangedOnDisk() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func reloadIfChangedOnDisk() {
        guard modificationDate() != knownModificationDate else { return }
        load()
        // Commits edits made in other apps; a no-op when git itself changed the file.
        git.record("Edit outside TodoBar")
    }

    private func modificationDate() -> Date? {
        let path = fileURL.resolvingSymlinksInPath().path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Applies `edit` to one todo and saves; `change` becomes "<change> “<todo>”" in the commit message.
    private func mutate(_ id: UUID, _ change: String, _ edit: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let before = items[i].text
        edit(&items[i])
        save("\(change) “\(before)”")
    }

    /// Keeps IDs stable across reloads so open details windows stay attached.
    private func carryOverIDs(_ parsed: [TodoItem]) -> [TodoItem] {
        var pool = items
        return parsed.map { item in
            var item = item
            if let match = pool.firstIndex(where: { $0.text == item.text }) {
                item.id = pool[match].id
                pool.remove(at: match)
            }
            return item
        }
    }
}
