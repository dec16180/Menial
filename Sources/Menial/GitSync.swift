// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import Foundation
import os

/// Keeps a history of the todo file in git. After each change (batched for a few
/// seconds, so typing notes makes one commit) it commits the todo file and its
/// images and files folders — and nothing else in the repository. With sync turned on it also
/// pulls and pushes the current branch.
@MainActor
final class GitSync: ObservableObject {
    /// Top-level folder of the repository the todo file lives in, if any.
    @Published private(set) var repoRoot: URL?
    @Published private(set) var hasRemote = false
    @Published private(set) var working = false
    @Published private(set) var lastCommit: Date?
    /// The last git failure, shown in Settings.
    @Published private(set) var lastError: String?
    /// macOS privacy protection kept git out of the todo folder (common for
    /// cloud-storage folders, and again after the app is renamed or re-signed).
    @Published private(set) var accessDenied = false

    private var file: URL?
    private var folders: [URL] = []
    /// Commit message lines waiting for the next commit. Entries with a key are
    /// replaced rather than repeated, so a burst of edits reads as one change.
    private var pendingChanges: [(key: String?, text: String)] = []
    private var debounce: Task<Void, Never>?
    private var queue: Task<Void, Never>?
    private var pullTimer: Timer?
    private var lastRefresh = Date.distantPast

    static let commitDelay: Duration = .seconds(3)
    static let pullInterval: TimeInterval = 5 * 60

    var displayRoot: String? {
        repoRoot.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    init() {
        let timer = Timer(timeInterval: Self.pullInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pullIfSyncing() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pullTimer = timer
    }

    // MARK: - Public

    func configure(file: URL, folders: [URL]) {
        self.file = file
        self.folders = folders
        pendingChanges = []
        lastRefresh = Date()
        enqueue { [weak self] in
            await self?.detectRepository()
            self?.pullIfSyncing()
        }
    }

    /// Looks for the repository again, e.g. after access was granted in System
    /// Settings. Called when the popover or Settings opens; cheap and throttled.
    func refresh() {
        guard file != nil, Date().timeIntervalSince(lastRefresh) > 5 else { return }
        lastRefresh = Date()
        enqueue { [weak self] in await self?.detectRepository() }
    }

    /// Notes a change; a commit follows once things are quiet for a moment.
    func record(_ change: String, replacing key: String? = nil) {
        guard Prefs.gitAutoCommit, repoRoot != nil else { return }
        if let key, let i = pendingChanges.firstIndex(where: { $0.key == key }) {
            pendingChanges[i].text = change
        } else if pendingChanges.last?.text != change {
            pendingChanges.append((key, change))
        }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            self?.commitNow()
        }
    }

    func commitNow() {
        debounce?.cancel()
        let changes = pendingChanges.map(\.text)
        pendingChanges = []
        enqueue { [weak self] in await self?.commit(changes) }
    }

    /// Commits anything still pending; used before quitting.
    func flush() async {
        if !pendingChanges.isEmpty { commitNow() }
        await queue?.value
    }

    /// `git init` in the todo file's folder, then commits the current state.
    func createRepository() {
        guard let folder = file?.deletingLastPathComponent() else { return }
        enqueue { [weak self] in
            guard let self else { return }
            let result = await self.run(["init"], in: folder)
            guard result.ok else { return self.fail("git init failed", result) }
            await self.detectRepository()
            await self.commit(["Start todo history"])
        }
    }

    func syncNow() {
        enqueue { [weak self] in
            guard let self, let root = self.repoRoot else { return }
            await self.pull(root)
            await self.push(root)
        }
    }

    // MARK: - Steps

    private func enqueue(_ step: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor [weak self] in
            await previous?.value
            self?.working = true
            await step()
            self?.working = false
        }
    }

    private func detectRepository() async {
        guard let folder = file?.deletingLastPathComponent(),
              FileManager.default.fileExists(atPath: folder.path) else {
            repoRoot = nil
            return
        }
        let top = await run(["rev-parse", "--show-toplevel"], in: folder)
        let wasFound = repoRoot != nil
        repoRoot = top.ok ? URL(fileURLWithPath: top.out, isDirectory: true) : nil
        accessDenied = !top.ok && top.err.contains("Operation not permitted")
        if top.ok || accessDenied {
            if lastError?.hasPrefix("Couldn't check") == true { lastError = nil }
        } else if !top.err.lowercased().contains("not a git repository") {
            // "Not a git repository" is the normal answer for a plain folder; anything
            // else (ownership, a broken git…) is shown in Settings.
            fail("Couldn't check for a git repository", top)
        }
        guard let repoRoot else {
            hasRemote = false
            return
        }
        hasRemote = await !run(["remote"], in: repoRoot).out.isEmpty
        // Changes made while git was out of reach (or while the app wasn't running)
        // weren't committed; pick them up now. A no-op when nothing changed.
        if !wasFound, Prefs.gitAutoCommit {
            await commit(["Save uncommitted changes"])
        }
    }

    private func commit(_ changes: [String]) async {
        guard let root = repoRoot, let file else { return }
        var paths = [file.path]
        paths += folders.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }

        let add = await run(["add", "-A", "--"] + paths, in: root)
        guard add.ok else { return fail("git add failed", add) }
        // Only name paths with staged changes: `git commit -- <path>` fails for a path
        // git doesn't know, such as an images folder that is empty or not tracked yet.
        var changed: [String] = []
        for path in paths {
            let diff = await run(["diff", "--cached", "--name-only", "--", path], in: root)
            guard diff.ok else { return fail("git diff failed", diff) }
            if !diff.out.isEmpty { changed.append(path) }
        }
        if !changed.isEmpty {
            paths = changed
            var args = await identityArgs(root) + ["commit", "--quiet", "-m", Self.subject(changes)]
            if changes.count > 1 {
                args += ["-m", changes.map { "- \($0)" }.joined(separator: "\n")]
            }
            // Committing only these paths leaves anything else you staged alone.
            let commit = await run(args + ["--"] + paths, in: root)
            guard commit.ok else { return fail("git commit failed", commit) }
            lastCommit = Date()
            lastError = nil
        }
        if Prefs.gitSync, hasRemote {
            await pull(root)
            await push(root)
        }
    }

    private func pullIfSyncing() {
        guard Prefs.gitSync, hasRemote else { return }
        enqueue { [weak self] in
            guard let self, let root = self.repoRoot else { return }
            await self.pull(root)
        }
    }

    private func pull(_ root: URL) async {
        guard await run(["rev-parse", "--abbrev-ref", "@{upstream}"], in: root).ok else { return }
        let pull = await run(await identityArgs(root) + ["pull", "--rebase", "--autostash", "--quiet"], in: root)
        if !pull.ok {
            _ = await run(["rebase", "--abort"], in: root)
            fail("git pull failed", pull)
        }
    }

    private func push(_ root: URL) async {
        let hasUpstream = await run(["rev-parse", "--abbrev-ref", "@{upstream}"], in: root).ok
        var args = ["push", "--quiet"]
        if !hasUpstream {
            // First push: publish the current branch to the first remote.
            guard let remote = await run(["remote"], in: root).out.split(separator: "\n").first else { return }
            args += ["--set-upstream", String(remote), "HEAD"]
        }
        let push = await run(args, in: root)
        if push.ok { lastError = nil } else { fail("git push failed", push) }
    }

    /// Supplies a fallback author when git has no user.name / user.email set up.
    private func identityArgs(_ root: URL) async -> [String] {
        let email = await run(["config", "user.email"], in: root)
        if email.ok, !email.out.isEmpty { return [] }
        return ["-c", "user.name=Menial", "-c", "user.email=menial@localhost"]
    }

    private static func subject(_ changes: [String]) -> String {
        switch changes.count {
        case 0: return "Update todos"
        case 1: return changes[0]
        default: return "\(changes[0]) and \(changes.count - 1) more change\(changes.count == 2 ? "" : "s")"
        }
    }

    private func fail(_ what: String, _ result: GitResult) {
        let detail = result.err.isEmpty ? result.out : result.err
        lastError = detail.isEmpty ? what : "\(what): \(detail)"
    }

    // MARK: - Running git

    struct GitResult {
        var status: Int32
        var out: String
        var err: String
        var ok: Bool { status == 0 }
    }

    private static let executable: String? = {
        ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a minimal PATH; credential helpers live in these.
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
            .joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"   // fail instead of waiting for a password nobody can type
        return env
    }()

    private static let log = Logger(subsystem: "local.menial.app", category: "git")

    private func run(_ args: [String], in directory: URL) async -> GitResult {
        let result = await execute(args, in: directory)
        if !result.ok {
            Self.log.error("git \(args.joined(separator: " "), privacy: .public) in \(directory.path, privacy: .public) failed (\(result.status)): \(result.err, privacy: .public)")
        }
        return result
    }

    private func execute(_ args: [String], in directory: URL) async -> GitResult {
        guard let exe = Self.executable else {
            return GitResult(status: -1, out: "", err: "git isn't installed. Run `xcode-select --install`.")
        }
        do {
            let result = try await ProcessRunner.run(
                exe, args: args, environment: Self.environment, directory: directory, timeout: 60
            )
            let trim = { (data: Data) in
                String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if result.timedOut { return GitResult(status: -1, out: "", err: "git timed out") }
            return GitResult(status: result.status, out: trim(result.stdout), err: trim(result.stderr))
        } catch {
            return GitResult(status: -1, out: "", err: error.localizedDescription)
        }
    }
}
