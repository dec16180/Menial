// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import SwiftUI

extension Priority {
    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

/// Row of 1 / 2 / 3 chips in their colors; clicking the selected one clears it.
@MainActor
struct PriorityPicker: View {
    let selection: Priority?
    let onChange: (Priority?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Priority")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Priority.allCases, id: \.self) { priority in
                let selected = selection == priority
                Button {
                    onChange(selected ? nil : priority)
                } label: {
                    Text("\(priority.rawValue) · \(priority.label)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(selected ? Color.white : priority.color)
                        .background(Capsule().fill(priority.color.opacity(selected ? 1 : 0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(selected ? "Clear priority" : "Set priority \(priority.rawValue)")
            }
        }
    }
}
