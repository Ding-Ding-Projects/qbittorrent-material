# Workspace Tabs

Workspace tabs are persistent plain-text pages that behave like browser tabs.
Schema 2 saves individual pin state, tab/group order, group membership and
collapse, sparse appearance, and every page change in a managed local Git
repository.

## Quick start

1. Select **Workspace** in the persistent application navigation or press `Alt+5`.
2. Select **+** or press `Ctrl+T` to add a page.
3. Write in the page editor; the status changes while the edit is being saved.
4. Right-click the tab for pin/group/close actions or **Edit appearance…**.
5. Use the installed-font typography controls, continuous color translator,
   geometry/state controls, inheritance, resets, and optional named presets.
6. Press `Ctrl+S` whenever you want to save and commit immediately.

Pinned and ordinary order, groups, the selected page, open and closed tabs,
content, and appearance are restored the next time the application starts.

![Persistent browser-style Workspace tabs](images/app/09-custom-workspace-tabs.png)

## Browser-style tab actions

- Click a tab to select it.
- Click its close button or middle-click it to close it.
- Double-click it to customize its name and appearance.
- Right-click it to pin, group, customize, duplicate, close other tabs, or
  close the tab.
- Shift+right-click it to open appearance directly, or press `Ctrl+Shift+A`.
- Use the overflow action rather than losing ordinary tabs at narrow widths.
- Close every tab if you want an empty workspace; select **Create tab** to begin
  again.

## Find and organize tabs

Create, rename, color, reorder, collapse, expand, and remove groups. Search the
current strip, one group, group names, or all app-owned Workspace tabs. Each
search has its own adjacent Qt/PCRE2 builder and remains plain-text-first.

Containing and inverse bulk close match visible labels, reject empty or invalid
input, preview the exact affected set, and exclude pinned tabs by default.
Dirty state is committed before a destructive close.

## Rename the app

Choose **Workspace > Rename application** or **Rename app** in the workspace
header. The new display name is remembered in the window title, Workspace
header, and tray tooltip. The executable name, installer, application profile,
and repository path do not change.

## Local Git saving

The app atomically writes `workspace.json`, one `tabs/<uuid>.md` file per page,
and a managed README, then records the update in `.git`. Git support is built
into the installer; installing the Git command-line client is optional.

Use the folder button or **Workspace > Open managed repository** to inspect the
files. Use **Save & Commit Workspace** or `Ctrl+S` to flush a pending edit.

If a crash leaves a valid untracked UUID-named page body ahead of
`workspace.json`, the next launch restores it as a **Recovered tab** and commits
it. A formerly tracked body omitted from the manifest is instead recognized as
an interrupted close and removed without reopening the tab.

## Pick the right export

| Choose | When you need |
| --- | --- |
| **Export workspace JSON** | One compact snapshot of the current app name, pinned/grouped tabs, text, appearance, and presets |
| **Export complete Git repository** | The current workspace plus every local commit |
| **Import workspace JSON** | To replace the live workspace but continue using its current local history |
| **Import complete Git repository** | To activate an exported workspace and history while retaining the previous repository as a hidden recovery copy |

Both import actions ask for confirmation because they replace the current tabs.
JSON imports require every tab's full text, commit pending edits before the
replacement, and roll back to the previous workspace if the imported state
cannot be saved. The internal metadata-only `workspace.json` from a repository
is not accepted as a portable JSON snapshot.

A complete-repository import activates the selected history but keeps the prior
complete repository beside `workspace-tabs` as a hidden
`.workspace-backup-<timestamp>-<id>` directory. If activation fails, the app
restores the prior repository when possible. If automatic recovery cannot
finish, it blocks new workspace writes and preserves all backup, staging, and
failed-import copies for manual recovery.

Invalid state found during startup is also preserved, not overwritten. It is
moved to a hidden `.workspace-recovery-<timestamp>-<id>` sibling before a fresh
Welcome workspace is created. If the move itself is unsafe or fails, the
original directory stays untouched and workspace saving remains blocked.
The editor and every mutating action also become visibly read-only, so changes
that cannot be saved are never accepted in memory.

These hidden folders are in the parent of the managed repository. Open the
managed repository, move up one directory, and enable hidden items to inspect
them. Keep recovery copies until the active pages and history are verified.

Workspace Git is local only. It does not push to GitHub or another remote.

For the file layout, limits, validation rules, and detailed migration behavior,
read [Custom Workspace Tabs](../WORKSPACE_TABS.md).

The detailed feature articles cover
[tab management](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-workspace-tab-management),
[search and regex](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-workspace-search-and-regex),
and [runtime appearance](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-appearance-runtime-appearance).
