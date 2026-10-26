// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

@MainActor
struct TodoRow: View {
    @EnvironmentObject private var store: TodoStore
    let item: TodoItem

    @ViewState private var hovering = false
    @ViewState private var editing = false
    @ViewState private var editText = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { store.toggle(item.id) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: item.priority == nil ? .regular : .semibold))
                    .foregroundStyle(checkColor)
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as open" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                title
                if item.hasDetails {
                    detailsSummary
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hovering ? 0.05 : 0))
                .padding(.horizontal, 6)
        )
        .overlay(alignment: .leading) {
            if let priority = item.priority, !item.isDone {
                Capsule()
                    .fill(priority.color)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.leading, 3)
                    .help("Priority \(priority.rawValue) · \(priority.label)")
            }
        }
        .contentShape(Rectangle())
        // A click anywhere on the row opens the details; the checkbox and the
        // trailing buttons handle their own clicks. Off while editing inline,
        // so clicks reach the text field.
        .gesture(TapGesture().onEnded { openDetails() }, including: editing ? .subviews : .all)
        .onHover { hovering = $0 }
        .contextMenu { menu }
        // Closing the popover keeps an inline edit instead of dropping it.
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willCloseNotification)) { _ in
            commitEdit()
        }
    }

    private var checkColor: Color {
        if item.isDone { return item.priority?.color ?? .accentColor }
        return item.priority?.color ?? .secondary
    }

    // MARK: - Title / inline editing

    @ViewBuilder
    private var title: some View {
        if editing {
            TextField("Todo", text: $editText)
                .textFieldStyle(.plain)
                .focused($editFocused)
                .onSubmit(commitEdit)
                .onExitCommand { editing = false }
                .onChange(of: editFocused) { focused in
                    if !focused && editing { commitEdit() }
                }
        } else {
            Text(item.text)
                .strikethrough(item.isDone, color: .secondary)
                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .help("Click to open details")
        }
    }

    private func beginEdit() {
        editText = item.text
        editing = true
        Task { @MainActor in editFocused = true }
    }

    private func commitEdit() {
        guard editing else { return }
        editing = false
        if editText != item.text { store.rename(item.id, to: editText) }
    }

    // MARK: - Details

    /// Small icons for what's inside the details window.
    private var detailsSummary: some View {
        HStack(spacing: 10) {
            if !item.subtasks.isEmpty {
                let done = item.subtasks.filter(\.isDone).count
                badge("checklist", "\(done)/\(item.subtasks.count)")
            }
            if !item.notes.isEmpty {
                badge("note.text", nil)
            }
            if !item.images.isEmpty {
                badge("photo", "\(item.images.count)")
            }
            if !item.attachments.isEmpty {
                badge("paperclip", "\(item.attachments.count)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func badge(_ systemName: String, _ text: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
            if let text { Text(text) }
        }
    }

    private func openDetails() {
        DetailWindows.shared.open(item.id, store: store)
    }

    // MARK: - Trailing actions

    private var trailing: some View {
        HStack(spacing: 0) {
            IconButton("square.and.pencil", help: "Open details: notes, subtasks, images, files", size: 11) {
                openDetails()
            }
            IconButton("trash", help: "Delete", size: 11) {
                store.delete(item.id)
            }
        }
        .opacity(hovering ? 1 : 0)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open Details…") { openDetails() }
        Button("Edit") { beginEdit() }
        Picker("Priority", selection: Binding(
            get: { item.priority },
            set: { priority in withAnimation(.easeOut(duration: 0.2)) { store.setPriority(item.id, priority) } }
        )) {
            ForEach(Priority.allCases, id: \.self) { priority in
                Text("\(priority.rawValue) · \(priority.label)").tag(Priority?.some(priority))
            }
            Divider()
            Text("None").tag(Priority?.none)
        }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.text, forType: .string)
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(item.id) }
    }
}
