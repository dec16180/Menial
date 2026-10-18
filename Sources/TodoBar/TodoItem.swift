import Foundation

/// A checklist entry inside a todo, stored as an indented `- [ ]` line.
struct Subtask: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var isDone: Bool = false
}

/// A file attached to a todo, stored as an indented `- [name](path)` line.
struct Attachment: Hashable {
    var name: String
    /// As written in the Markdown file, usually relative to the todo file.
    var path: String
}

/// 1 is the most urgent. Stored as a trailing `!1`, `!2` or `!3` on the todo line.
enum Priority: Int, CaseIterable, Comparable {
    case high = 1, medium, low

    var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
}

/// One todo as it lives in the Markdown file.
struct TodoItem: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var isDone: Bool = false
    var priority: Priority? = nil
    var subtasks: [Subtask] = []
    /// Image paths as written in `  ![](path)` lines, usually relative to the todo file.
    var images: [String] = []
    var attachments: [Attachment] = []
    /// Any other indented text under the todo (your notes), without its indentation.
    var notes: String = ""

    var hasDetails: Bool {
        !subtasks.isEmpty || !images.isEmpty || !attachments.isEmpty || !notes.isEmpty
    }
}

/// Reads and writes the todo file. The format is plain GitHub-style Markdown:
///
///     # Todos
///
///     - [ ] Book a dentist appointment for a cleaning !1
///     - [ ] Draft the Q4 budget proposal !2
///       - [x] Export last year's numbers
///       - [ ] List what changed
///
///       ![](Todos-images/1a2b3c4d.png)
///       - [Budget 2025.xlsx](<Todos-files/Budget 2025.xlsx>)
///
///       Notes you write in the details window go here.
///
///     ## Done
///
///     - [x] Renew passport
///
enum MarkdownCodec {
    static func parse(_ markdown: String) -> [TodoItem] {
        var items: [TodoItem] = []
        var current: TodoItem?
        /// Blank lines seen since the last note line, kept so paragraphs in notes survive.
        var pendingBlanks = 0

        func finish() {
            if let item = current { items.append(item) }
            current = nil
            pendingBlanks = 0
        }

        func appendNote(_ line: String) {
            let content = dedent(line)
            if let notes = current?.notes, !notes.isEmpty {
                current?.notes = notes + String(repeating: "\n", count: 1 + pendingBlanks) + content
            } else {
                current?.notes = content
            }
            pendingBlanks = 0
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let indented = line.first == " " || line.first == "\t"
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !indented, let task = parseTask(line) {
                finish()
                let split = splitPriority(task.text)
                current = TodoItem(text: split.text, isDone: task.done, priority: split.priority)
            } else if trimmed.isEmpty {
                if current != nil { pendingBlanks += 1 }
            } else if indented, current != nil {
                // Checked before subtasks: a file named "x" would otherwise read as "- [x]".
                if let attachment = parseAttachment(trimmed) {
                    current?.attachments.append(attachment)
                } else if let sub = parseTask(trimmed) {
                    current?.subtasks.append(Subtask(text: sub.text, isDone: sub.done))
                } else if let image = parseImage(trimmed) {
                    current?.images.append(image)
                } else {
                    appendNote(line)
                }
            } else {
                // A heading or other top-level text ends the current todo.
                finish()
            }
        }
        finish()
        return items
    }

    static func serialize(_ items: [TodoItem]) -> String {
        var lines = ["# Todos", ""]

        func append(_ item: TodoItem) {
            let tag = item.priority.map { " !\($0.rawValue)" } ?? ""
            lines.append("- [\(item.isDone ? "x" : " ")] \(singleLine(item.text))\(tag)")
            for sub in item.subtasks {
                lines.append("  - [\(sub.isDone ? "x" : " ")] \(singleLine(sub.text))")
            }
            // Images and notes get a blank line first so Markdown doesn't fold
            // them into the paragraph above.
            if !item.images.isEmpty {
                lines.append("")
                for image in item.images { lines.append("  ![](\(imageLink(image)))") }
            }
            if !item.attachments.isEmpty {
                if item.images.isEmpty { lines.append("") }
                for file in item.attachments {
                    lines.append("  - [\(linkText(file.name))](\(imageLink(file.path)))")
                }
            }
            let notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                lines.append("")
                for line in notes.components(separatedBy: "\n") {
                    lines.append(line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "  " + line)
                }
            }
        }

        byPriority(items.filter { !$0.isDone }).forEach(append)

        let done = items.filter { $0.isDone }
        if !done.isEmpty {
            if lines.last != "" { lines.append("") }
            lines.append("## Done")
            lines.append("")
            done.forEach(append)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `- [ ] text`, `* [x] text`, `+ [X] text` → (done, text)
    static func parseTask(_ line: String) -> (done: Bool, text: String)? {
        var rest = line[...]
        guard let bullet = rest.first, bullet == "-" || bullet == "*" || bullet == "+" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " || rest.first == "\t" else { return nil }
        rest = rest.drop(while: { $0 == " " || $0 == "\t" })
        guard rest.hasPrefix("[ ]") || rest.hasPrefix("[x]") || rest.hasPrefix("[X]") else { return nil }
        let done = !rest.hasPrefix("[ ]")
        let text = rest.dropFirst(3).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (done, text)
    }

    /// "Pay rent !1" → ("Pay rent", .high). Text without a tag comes back unchanged.
    static func splitPriority(_ text: String) -> (text: String, priority: Priority?) {
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count > 1, let last = parts.last, last.count == 2, last.first == "!",
              let digit = Int(String(last.dropFirst())), let priority = Priority(rawValue: digit) else {
            return (text, nil)
        }
        let rest = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? (text, nil) : (rest, priority)
    }

    /// Priority 1, 2, 3, then todos without one; the existing order is kept within each group.
    static func byPriority(_ items: [TodoItem]) -> [TodoItem] {
        items.enumerated()
            .sorted { a, b in
                let ra = a.element.priority?.rawValue ?? 4
                let rb = b.element.priority?.rawValue ?? 4
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// `![alt](path)` or `![alt](<path with spaces>)` → path
    static func parseImage(_ line: String) -> String? {
        guard line.hasPrefix("!["), line.hasSuffix(")"), let mid = line.range(of: "](") else { return nil }
        var path = line[mid.upperBound..<line.index(before: line.endIndex)].trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("<"), path.hasSuffix(">") { path = String(path.dropFirst().dropLast()) }
        return path.isEmpty ? nil : path
    }

    /// `- [name](path)` → attachment. Web links stay part of the notes.
    static func parseAttachment(_ line: String) -> Attachment? {
        guard line.hasPrefix("- ["), line.hasSuffix(")"),
              let close = line.range(of: "]("),
              !line[line.index(line.startIndex, offsetBy: 3)..<close.lowerBound].contains("]") else { return nil }
        let name = String(line[line.index(line.startIndex, offsetBy: 3)..<close.lowerBound])
        var path = line[close.upperBound..<line.index(before: line.endIndex)].trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("<"), path.hasSuffix(">") { path = String(path.dropFirst().dropLast()) }
        guard !name.isEmpty, !path.isEmpty, !path.contains("://"), !path.hasPrefix("mailto:") else { return nil }
        return Attachment(name: name, path: path)
    }

    static func linkText(_ name: String) -> String {
        singleLine(name).replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    static func imageLink(_ path: String) -> String {
        path.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) ? "<\(path)>" : path
    }

    /// Strips the indentation that marks a line as belonging to a todo.
    static func dedent(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
        return line.hasPrefix(" ") ? String(line.dropFirst()) : line
    }

    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
