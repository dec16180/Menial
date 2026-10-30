<!--
SPDX-FileCopyrightText: 2026 Christopher De Nicolo

SPDX-License-Identifier: MIT
-->

# Menial

*A menu bar home for your menial tasks.*

A small native macOS menu bar todo list. Your todos live in a plain Markdown file, and every change can be committed to a git repository, so you get a full history and can sync between Macs.

## What it does

- **Menu bar only** — a checklist icon in the top bar, no Dock icon. Click it, type, press Return.
- **Markdown file as the database** — defaults to `~/Documents/Todos.md`. Edit it in any editor (Obsidian, VS Code, iA Writer…); Menial notices changes within a couple of seconds.
- **Priorities 1–3** — 1 (red, high), 2 (orange, medium), 3 (blue, low). Open todos sort themselves: 1 → 2 → 3 → no priority, newest first within each. Set it by ending a todo with `!1`, `!2` or `!3` as you type, via right-click → Priority, or with the chips in the details window (click the selected chip again to clear it).
- **Reminders** — set a date and time in the details window, via right-click → Remind Me, or by ending a todo with `@2026-11-02` (9:00 that day) or `@2026-11-02T14:30` as you type. macOS shows a notification then (it asks for permission the first time); clicking it opens the todo. The date appears in the row. Once it has passed, the todo counts as high priority: it moves to the top and turns red until you check it off, clear the reminder or move it to a later date. Its own priority stays in the file and the details window, and is back after that. Times are local, and a reminder that passed while Menial wasn't running only shows up in red.
- **Search** — click 🔍 in the header (or press ⌘F) and type to filter the list. It searches titles, notes, subtasks and attachment names, ignoring case and accents (`steuererklarung` finds “Steuererklärung”); several words must all match, `!1` finds priority-1 todos and `@2026-11` finds reminders in that month. Matching done todos are shown too. Esc closes the search.
- **Details window per todo** — click a todo (anywhere but its circle) to open a window with:
  - **Notes**: as much free text as you like,
  - **Subtasks**: a checklist of smaller steps,
  - **Images**: drag them in, paste a screenshot, or use Add Images…; thumbnails show the whole image, and a click opens a large preview (right-click → Open in Preview for the Preview app)
  - **Attachments**: any file (PDFs, spreadsheets, documents, even folders) — drag them in or use Add Files…; click one to open it.
  Dropped or pasted images go to Images, everything else to Attachments. The row in the menu shows small icons for what's inside (e.g. ☑ 2/5, 🖼 3, 📎 2); click them to open the window.
- **Git history** — when the todo file is in a git repository, Menial commits it (and its images) after each change, with messages like `Complete “Renew passport”`. Optionally pulls and pushes to a remote.
- Click a todo to open its details (the circle just checks it off). Hover for 🗑 (delete); right-click → Edit renames it right in the list. Titles save as you type — no Return needed.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode isn't needed. This also provides `git`.

## Build & install

```bash
cd Menial
chmod +x build.sh
./build.sh --install
```

That compiles the app, copies `Menial.app` into `/Applications`, and launches it. Use `./build.sh` alone to only build into `build/Menial.app`.

The first time it reads `~/Documents`, macOS asks for permission — allow it (or pick a file elsewhere in Settings).

## The file format

```markdown
# Todos

- [ ] Book a dental cleaning for next week !1
- [ ] Draft the Q4 budget proposal !2 @2026-11-02T09:00
  - [x] Export last year's numbers
  - [ ] List what changed

  ![](Todos-images/1a2b3c4d.png)
  - [Budget 2025.xlsx](<Todos-files/Budget 2025.xlsx>)

  Notes from the details window, as many lines
  and paragraphs as you like.

## Done

- [x] Renew passport
```

- `- [ ]` / `- [x]` lines are todos. Open ones are written under `# Todos`, finished ones under `## Done`.
- A trailing `!1`, `!2` or `!3` is the priority. Menial writes open todos in priority order.
- A trailing `@2026-11-02T09:00` is the reminder, in local time. `@2026-11-02` also works and means 9:00; Menial writes it back in the full form.
- Indented `- [ ]` lines are subtasks.
- Indented `![](path)` lines are images. Menial copies attached images into a `Todos-images` folder next to the file (named after your file) and links them relatively, so Obsidian and other editors show them too. Removing an image or deleting its todo deletes the copy; images you linked by hand from elsewhere are never deleted.
- Indented `- [name](path)` lines are attachments. Files are copied into a `Todos-files` folder next to the todo file under their original name (`Report 2.pdf` if the name is taken). Removing an attachment or deleting its todo deletes the copy. Web links (`https://…`) stay part of the notes.
- Any other indented text under a todo becomes its notes.
- Menial rewrites the headings itself; loose top-level paragraphs outside of todos aren't kept.

## Git

Open Settings (⚙︎) → **Git history**.

- **Already in a repository?** If the todo file sits anywhere inside a git working tree, Menial uses that repository automatically.
- **Not yet?** Click **Create Repository in “…”** to run `git init` in the file's folder. Best practice: give the todo file its own folder first (Settings → New…, e.g. `~/Todos/Todos.md`) rather than creating a repository over all of `~/Documents`.

How commits work:

- Changes are batched: Menial waits until you've paused for 3 seconds, so typing notes makes one commit, not one per keystroke. Quitting from the menu commits anything still pending.
- **Only the todo file and its images and files folders are committed.** Other files in the repository — and anything you've staged yourself — are left alone.
- Edits made in other apps are committed too (`Edit outside Menial`).
- If git has no `user.name`/`user.email` configured, commits are authored as `Menial <menial@localhost>`.

Syncing with a remote (off by default):

1. Add a remote in Terminal, e.g. `cd ~/Todos && git remote add origin git@github.com:you/todos.git`
2. Turn on **Pull and push to remote** in Settings.

Menial then runs `git pull --rebase --autostash` and `git push` after each commit, and pulls every 5 minutes (and at launch) to pick up changes from your other Macs. The first push publishes the current branch with `--set-upstream`. Authentication uses your normal git setup (SSH keys, or the macOS keychain credential helper); Menial never prompts for a password, so set that up in Terminal first. If a pull hits a conflict, Menial aborts the rebase and shows the error in Settings — resolve it in Terminal.

Settings:

| Setting | Default | |
|---|---|---|
| Commit changes automatically | On | Only has an effect when the file is in a repository |
| Pull and push to remote | Off | Needs a remote |
| Launch at login | Off | |

## Troubleshooting

- **"git push failed: … Permission denied / could not read Username"** — run `git push` once in Terminal inside the repository and fix authentication there.
- **"git pull failed"** — usually a conflict with a change made on another Mac. Open Terminal in the repository, run `git pull --rebase`, resolve, and commit.
- **Reminders don't notify** — check System Settings → Notifications → Menial. The details window shows a shortcut there when notifications are off. macOS also refuses notifications for an app run from a temporary folder.
- **Nothing happens in the menu bar** — with a crowded menu bar, macOS hides overflow icons behind the notch; quit a few menu bar apps or use a menu bar manager.

## Project layout

```
Package.swift
Resources/Info.plist          app bundle metadata (LSUIElement = menu bar only)
Sources/Menial/
  main.swift                  app entry point (plain AppKit, no SwiftUI scenes)
  AppDelegate.swift           menu bar icon, popover, keyboard-shortcut menu
  ContentView.swift           popover: header, add field, list, footer
  TodoRow.swift               one todo: checkbox, inline edit, details icons
  TodoDetailView.swift        details window: priority, notes, subtasks, images
  PriorityViews.swift         priority colors and the 1/2/3 picker
  ReminderViews.swift         reminder date in the row and the details window
  Reminders.swift             schedules macOS notifications for reminders
  DetailWindows.swift         opens one details window per todo
  ImagePreviewWindows.swift   large preview window for an attached image
  SettingsView.swift          file picker, git options, launch at login
  TodoStore.swift             state, saving, file watching, images
  GitSync.swift               batched commits, pull/push
  ProcessRunner.swift         runs command-line tools with a timeout
  TodoItem.swift              model + Markdown parser/writer
  Prefs.swift                 settings keys and defaults
  ViewState.swift             @State stand-in that builds with the Command Line Tools
build.sh                      builds Menial.app (and installs with --install)
```

## License

Menial is free software under the [MIT License](LICENSE), © 2026 Christopher De Nicolo.

The project follows the [REUSE](https://reuse.software) standard: every file carries an SPDX copyright and license header, and the license text lives in [`LICENSES/`](LICENSES/). Check compliance with `reuse lint`.

Not affiliated with Apple or with any editor or service mentioned in this README.
