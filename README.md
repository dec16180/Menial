# TodoBar

A small native macOS menu bar todo list. Your todos live in a plain Markdown file, and every change can be committed to a git repository, so you get a full history and can sync between Macs.

## What it does

- **Menu bar only** — a checklist icon in the top bar, no Dock icon. Click it, type, press Return.
- **Markdown file as the database** — defaults to `~/Documents/Todos.md`. Edit it in any editor (Obsidian, VS Code, iA Writer…); TodoBar notices changes within a couple of seconds.
- **Priorities 1–3** — 1 (red, high), 2 (orange, medium), 3 (blue, low). Open todos sort themselves: 1 → 2 → 3 → no priority, newest first within each. Set it by ending a todo with `!1`, `!2` or `!3` as you type, via right-click → Priority, or with the chips in the details window (click the selected chip again to clear it).
- **Search** — click 🔍 in the header (or press ⌘F) and type to filter the list. It searches titles, notes, subtasks and attachment names, ignoring case and accents (`steuererklarung` finds “Steuererklärung”); several words must all match, and `!1` finds priority-1 todos. Matching done todos are shown too. Esc closes the search.
- **Details window per todo** — click a todo (anywhere but its circle) to open a window with:
  - **Notes**: as much free text as you like,
  - **Subtasks**: a checklist of smaller steps,
  - **Images**: drag them in, paste a screenshot, or use Add Images…
  - **Attachments**: any file (PDFs, spreadsheets, documents, even folders) — drag them in or use Add Files…; click one to open it.
  Dropped or pasted images go to Images, everything else to Attachments. The row in the menu shows small icons for what's inside (e.g. ☑ 2/5, 🖼 3, 📎 2); click them to open the window.
- **Git history** — when the todo file is in a git repository, TodoBar commits it (and its images) after each change, with messages like `Complete “Renew passport”`. Optionally pulls and pushes to a remote.
- Click a todo to open its details (the circle just checks it off). Hover for 🗑 (delete); right-click → Edit renames it right in the list. Titles save as you type — no Return needed.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode isn't needed. This also provides `git`.

## Build & install

```bash
cd TodoBar
chmod +x build.sh
./build.sh --install
```

That compiles the app, copies `TodoBar.app` into `/Applications`, and launches it. Use `./build.sh` alone to only build into `build/TodoBar.app`.

The first time it reads `~/Documents`, macOS asks for permission — allow it (or pick a file elsewhere in Settings).

## The file format

```markdown
# Todos

- [ ] Book a dental cleaning for next week !1
- [ ] Draft the Q4 budget proposal !2
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
- A trailing `!1`, `!2` or `!3` is the priority. TodoBar writes open todos in priority order.
- Indented `- [ ]` lines are subtasks.
- Indented `![](path)` lines are images. TodoBar copies attached images into a `Todos-images` folder next to the file (named after your file) and links them relatively, so Obsidian and other editors show them too. Removing an image or deleting its todo deletes the copy; images you linked by hand from elsewhere are never deleted.
- Indented `- [name](path)` lines are attachments. Files are copied into a `Todos-files` folder next to the todo file under their original name (`Report 2.pdf` if the name is taken). Removing an attachment or deleting its todo deletes the copy. Web links (`https://…`) stay part of the notes.
- Any other indented text under a todo becomes its notes.
- TodoBar rewrites the headings itself; loose top-level paragraphs outside of todos aren't kept.

## Git

Open Settings (⚙︎) → **Git history**.

- **Already in a repository?** If the todo file sits anywhere inside a git working tree, TodoBar uses that repository automatically.
- **Not yet?** Click **Create Repository in “…”** to run `git init` in the file's folder. Best practice: give the todo file its own folder first (Settings → New…, e.g. `~/Todos/Todos.md`) rather than creating a repository over all of `~/Documents`.

How commits work:

- Changes are batched: TodoBar waits until you've paused for 3 seconds, so typing notes makes one commit, not one per keystroke. Quitting from the menu commits anything still pending.
- **Only the todo file and its images and files folders are committed.** Other files in the repository — and anything you've staged yourself — are left alone.
- Edits made in other apps are committed too (`Edit outside TodoBar`).
- If git has no `user.name`/`user.email` configured, commits are authored as `TodoBar <todobar@localhost>`.

Syncing with a remote (off by default):

1. Add a remote in Terminal, e.g. `cd ~/Todos && git remote add origin git@github.com:you/todos.git`
2. Turn on **Pull and push to remote** in Settings.

TodoBar then runs `git pull --rebase --autostash` and `git push` after each commit, and pulls every 5 minutes (and at launch) to pick up changes from your other Macs. The first push publishes the current branch with `--set-upstream`. Authentication uses your normal git setup (SSH keys, or the macOS keychain credential helper); TodoBar never prompts for a password, so set that up in Terminal first. If a pull hits a conflict, TodoBar aborts the rebase and shows the error in Settings — resolve it in Terminal.

Settings:

| Setting | Default | |
|---|---|---|
| Commit changes automatically | On | Only has an effect when the file is in a repository |
| Pull and push to remote | Off | Needs a remote |
| Launch at login | Off | |

## Troubleshooting

- **"git push failed: … Permission denied / could not read Username"** — run `git push` once in Terminal inside the repository and fix authentication there.
- **"git pull failed"** — usually a conflict with a change made on another Mac. Open Terminal in the repository, run `git pull --rebase`, resolve, and commit.
- **Nothing happens in the menu bar** — with a crowded menu bar, macOS hides overflow icons behind the notch; quit a few menu bar apps or use a menu bar manager.

## Project layout

```
Package.swift
Resources/Info.plist          app bundle metadata (LSUIElement = menu bar only)
Sources/TodoBar/
  TodoBarApp.swift            app entry, menu bar icon + popover
  ContentView.swift           popover: header, add field, list, footer
  TodoRow.swift               one todo: checkbox, inline edit, details icons
  TodoDetailView.swift        details window: priority, notes, subtasks, images
  PriorityViews.swift         priority colors and the 1/2/3 picker
  DetailWindows.swift         opens one details window per todo
  SettingsView.swift          file picker, git options, launch at login
  TodoStore.swift             state, saving, file watching, images
  GitSync.swift               batched commits, pull/push
  ProcessRunner.swift         runs command-line tools with a timeout
  TodoItem.swift              model + Markdown parser/writer
  Prefs.swift                 settings keys and defaults
  ViewState.swift             @State stand-in that builds with the Command Line Tools
build.sh                      builds TodoBar.app (and installs with --install)
```
