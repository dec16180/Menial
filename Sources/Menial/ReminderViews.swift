// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// The reminder date in a todo's row; turns red once it has passed.
@MainActor
struct ReminderBadge: View {
    let date: Date
    let overdue: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: overdue ? "bell.badge.fill" : "bell")
            Text(date.formatted(date: .abbreviated, time: .shortened))
        }
        .foregroundStyle(overdue ? Color.red : Color.secondary)
    }
}

/// Date and time of a todo's reminder in the details window, or a chip to add one.
@MainActor
struct ReminderPicker: View {
    @EnvironmentObject private var reminders: ReminderScheduler
    let selection: Date?
    let onChange: (Date?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Reminder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = selection {
                    DatePicker(
                        "",
                        selection: Binding(get: { date }, set: { onChange($0) }),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
                    IconButton("xmark", help: "Clear reminder", size: 10) { onChange(nil) }
                } else {
                    Button {
                        onChange(ReminderPreset.tomorrow.date())
                    } label: {
                        Text("Add")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(Color.accentColor)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Remind me tomorrow at 9:00; you can change the date afterwards")
                }
            }
            if selection != nil && reminders.notificationsDenied {
                HStack(spacing: 6) {
                    Text("Notifications are off for Menial.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Open System Settings") { openNotificationSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
