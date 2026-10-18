import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @ViewState private var draft = ""
    @ViewState private var showSettings = false
    @ViewState private var showDone = false
    @ViewState private var listHeight: CGFloat = 0
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        Group {
            if showSettings {
                SettingsView { showSettings = false }
            } else {
                mainView
            }
        }
        .frame(width: 320)
        // Solid background: the menu bar panel is translucent by default and
        // lets windows underneath show through.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            addField
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            Divider()
            list
            if let message = store.errorMessage {
                errorBanner(message)
            }
            Divider()
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Todos").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                IconButton("doc.text", help: "Open the Markdown file") {
                    store.openInEditor()
                }
                IconButton("gearshape", help: "Settings") {
                    showSettings = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let open = store.openItems.count
        let done = store.doneItems.count
        if open == 0 && done == 0 { return "Nothing here yet" }
        if open == 0 { return "All done · \(done) completed" }
        return "\(open) open" + (done > 0 ? " · \(done) done" : "")
    }

    // MARK: - Add field

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.accentColor)
            TextField("Add a todo (!1–!3 = priority)", text: $draft)
                .textFieldStyle(.plain)
                .focused($addFieldFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .onAppear {
            Task { @MainActor in addFieldFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didShowNotification)) { _ in
            addFieldFocused = true
        }
    }

    private func submit() {
        store.add(draft)
        draft = ""
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.openItems.isEmpty {
                    emptyState
                } else {
                    ForEach(store.openItems) { item in
                        TodoRow(item: item)
                    }
                }
                if !store.doneItems.isEmpty {
                    doneSection
                }
            }
            .padding(.vertical, 6)
            .animation(.easeOut(duration: 0.2), value: store.openItems.map(\.id))
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(height: min(max(listHeight, 70), 340))
        .onPreferenceChange(ContentHeightKey.self) { listHeight = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(store.doneItems.isEmpty ? "Nothing to do" : "You're all caught up")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showDone.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showDone ? 90 : 0))
                        Text("Done (\(store.doneItems.count))")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if showDone {
                    Button("Clear") { store.clearDone() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Remove all completed todos from the file")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if showDone {
                ForEach(store.doneItems) { item in
                    TodoRow(item: item)
                }
            }
        }
    }

    // MARK: - Error + footer

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                store.errorMessage = nil
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.revealInFinder()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                    Text(store.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Show the todo file in Finder")

            Spacer()

            Button("Quit") {
                // Let a pending git commit finish first.
                Task { @MainActor in
                    await store.git.flush()
                    NSApp.terminate(nil)
                }
            }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Small borderless icon button with a hover highlight.
struct IconButton: View {
    let systemName: String
    let help: String
    var size: CGFloat = 13
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    init(_ systemName: String, help: String, size: CGFloat = 13, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 13, height: size + 11)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(hovering && isEnabled ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
        .onHover { hovering = $0 }
    }
}
