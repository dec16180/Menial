// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import AppKit
import Combine
import UserNotifications

/// Quick choices for setting a reminder; "tomorrow" and "next week" mean 9:00.
enum ReminderPreset: CaseIterable {
    case inAnHour, tomorrow, nextWeek

    var label: String {
        switch self {
        case .inAnHour: return "In 1 Hour"
        case .tomorrow: return "Tomorrow"
        case .nextWeek: return "Next Week"
        }
    }

    func date(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        func morning(inDays days: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        switch self {
        case .inAnHour: return calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        case .tomorrow: return morning(inDays: 1)
        case .nextWeek: return morning(inDays: 7)
        }
    }
}

/// Turns the reminders in the todo file into macOS notifications. The file is the
/// source of truth: whenever the reminders change, in Menial or in another app,
/// everything still to come is scheduled again.
@MainActor
final class ReminderScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    /// Notifications are turned off for Menial, shown in the details window.
    @Published private(set) var notificationsDenied = false

    private struct Entry: Equatable {
        var id: UUID
        var text: String
        var date: Date
    }

    /// The most notifications macOS keeps scheduled for one app; the soonest go first.
    private static let scheduleLimit = 64

    private weak var store: TodoStore?
    private var entries: [Entry] = []
    private var watches: Set<AnyCancellable> = []

    /// Using the notification center without an app bundle crashes, e.g. under `swift run`.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func watch(_ store: TodoStore) {
        self.store = store
        center?.delegate = self

        store.$items
            .map { items in
                items.compactMap { item in
                    item.isDone ? nil : item.reminder.map { Entry(id: item.id, text: item.text, date: $0) }
                }
            }
            .removeDuplicates()
            // Titles save on every keystroke.
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] entries in
                self?.entries = entries
                self?.reschedule()
            }
            .store(in: &watches)

        // Notifications may have been turned on in System Settings in the meantime.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &watches)
    }

    private func reschedule() {
        guard let center else { return }
        Task { @MainActor in
            // Asks the first time there's a reminder, not at launch; answers from memory after that.
            if !entries.isEmpty {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                notificationsDenied = !granted
            }
            // Reads `entries` after the wait, so an older run can't bring back old reminders.
            center.removeAllPendingNotificationRequests()
            let now = Date()
            let upcoming = entries.filter { $0.date > now }.sorted { $0.date < $1.date }
            upcoming.prefix(Self.scheduleLimit).forEach { schedule($0, in: center) }
        }
    }

    private func schedule(_ entry: Entry, in center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = entry.text
        content.sound = .default
        content.userInfo = ["id": entry.id.uuidString, "text": entry.text]
        // A calendar date rather than a countdown, so sleep and clock changes don't shift it.
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows the banner even while Menial is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Clicking a notification opens the todo's details.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let id = (info["id"] as? String).flatMap(UUID.init(uuidString:))
        let text = info["text"] as? String
        Task { @MainActor in self.openTodo(id: id, text: text) }
        completionHandler()
    }

    /// IDs only last until the app quits, so a notification from before then is matched by title.
    private func openTodo(id: UUID?, text: String?) {
        guard let store else { return }
        let item = id.flatMap(store.item) ?? store.items.first { !$0.isDone && $0.text == text }
        if let item { DetailWindows.shared.open(item.id, store: store) }
    }
}
