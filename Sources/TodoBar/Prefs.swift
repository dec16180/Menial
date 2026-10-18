import Foundation

/// UserDefaults keys and their defaults. Views bind to the same keys with
/// @AppStorage, so the default values here must match the ones in SettingsView.
enum Prefs {
    static let filePathKey = "todoFilePath"
    static let gitAutoCommitKey = "gitAutoCommit"
    static let gitSyncKey = "gitSync"

    static let defaultFilePath = "~/Documents/Todos.md"

    private static var defaults: UserDefaults { .standard }

    static var fileURL: URL {
        let raw = defaults.string(forKey: filePathKey) ?? defaultFilePath
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    /// Commit the todo file after changes when it's inside a git repository.
    static var gitAutoCommit: Bool { defaults.object(forKey: gitAutoCommitKey) as? Bool ?? true }

    /// Also pull and push the repository's current branch.
    static var gitSync: Bool { defaults.object(forKey: gitSyncKey) as? Bool ?? false }
}
