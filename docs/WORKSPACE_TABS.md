# Custom Workspace Tabs

The **Workspace** area is a persistent, browser-style collection of plain-text
pages inside qBittorrent Material. Each inner tab owns its content and visual
style, while the application display name, physical and pinned order, groups,
collapse state, active tab, and complete page collection survive restarts.

The workspace is stored in a managed local Git repository. Saving and committing
use the libgit2 library shipped with the application, so the Git command-line
client is not required.

## Open and navigate the workspace

Select **Notes** in the persistent application navigation or press `Alt+5`. The row
inside that view behaves like a browser tab strip: the strip itself is a recessed
surface and each tab is drawn as its own shape on top of it, so the selected tab,
unselected tabs, and the hovered tab are all distinguishable at rest.

- Select a tab to open its page.
- Select **+** or press `Ctrl+T` to create a page.
- Select a tab's close button, middle-click it, or press `Ctrl+W` while the
  Workspace view is active to close it.
- Right-click a tab to pin, group, customize, duplicate, close other tabs, or
  close it.
- Shift+right-click a tab or group to open its anchored appearance editor
  directly; `Ctrl+Shift+A` is the keyboard path.
- Use the overflow action whenever ordinary tabs do not fit. Pinned tabs remain
  in their stable region.

Closing every tab is supported. The empty view offers a **Create tab** action to
start again. A workspace can contain up to 100 tabs.

![Persistent browser-style Workspace tabs](images/app/09-custom-workspace-tabs.png)

## Pin, group, search, and bulk close

Schema 2 persists individual pin state, pinned and ordinary order, up to 32
groups, group names/colors/order/collapse, and membership. Schema 1 remains
readable and is upgraded on the next save.

Groups can be created, renamed, colored, reordered, collapsed, expanded, and
removed. Tabs move into or out of a group by pointer or explicit context action.
Removing a group does not silently delete its member pages. Pinning applies to
individual tabs rather than a complete group.

The discovery panel provides four independent searches: current strip, one per
group, group names, and a master search across the app-owned Workspace tabs.
Each field defaults to plain text and has its own adjacent full Qt/PCRE2 builder.
Activating a result from a collapsed group reveals the page without changing
the saved collapse preference.

**Close tabs containing text** and **Close tabs not containing text** use the
same visible-label predicate. An empty query or invalid pattern cannot run.
Review the affected set before confirming; pinned tabs are excluded unless the
preview's include-pinned choice is explicitly enabled. Dirty state is
checkpointed into local Git before destructive close.

## Rename the application display

Choose **Workspace > Rename application**, select **Rename app** in the workspace
header, or use the workspace portability menu. The chosen name is restored at
the next launch and is used in the window title, Workspace header, and system
tray tooltip.

This is a display-name customization. It does not rename the executable,
installer entry, application data directory, profile identity, or managed
repository path.

## Customize a page

Open **Edit appearance…** from a tab or group context menu. Sparse overrides
inherit in this order: app default, Workspace global, group, then tab. The
editor covers installed-font typography, direction/alignment, spacing,
geometry, icons/badges, and state colors. Its continuous color studio translates
named, HEX8, RGBA, HSLA, HSVA, HWB, Lab/LCH, OKLab/OKLCH, and CMYK values while
preserving alpha and showing contrast/clipping evidence.

Reset one working property, one persisted target, or global Workspace
appearance. Save, apply, remove, import, or export up to 32 named presets in the
versioned preset JSON format.

Qt Quick renders double strike and shadow approximately. Custom underline,
outline, and glow values remain visible and persisted as metadata but are not
all rendered; arbitrary variable-font axes remain backend-dependent. The app
states these limits instead of silently dropping the user's value.

Pages use a plain-text editor. Their repository files use the `.md` extension so
they remain convenient to inspect and diff, but the application does not render
Markdown formatting inside the editor.

## Automatic saving and local history

Editing a page or changing workspace state schedules an atomic save and local
commit after a short debounce. The status below the workspace name changes from
**Changes pending** to **Synced to local Git** and shows the latest short commit
ID. Press `Ctrl+S`, choose **Save & Commit Workspace**, or select the sync button
to flush pending changes immediately.

Choose **Open managed repository** to inspect the folder in the platform file
manager. The repository contains:

```text
workspace-tabs/
|-- .git/                 Complete automatic local history
|-- README.md             Description of the managed repository
|-- workspace.json        Display name, orders, groups, active tab, and appearance
`-- tabs/
    `-- <tab-uuid>.md      One UTF-8 plain-text page per tab
```

Tab UUIDs keep filenames stable when a tab is renamed. Closing a tab removes its
current page file in the next commit, so earlier content remains recoverable
from Git history. The app writes managed files atomically before creating the
commit.

The normal repository location is selected through Qt's per-user application
data location. Use **Open managed repository** instead of assuming a fixed path;
the exact directory varies by operating system and application profile.

## JSON snapshots and complete repository transfers

The portability menu and the **Workspace** application menu offer two formats:

| Format | Includes | Best for |
| --- | --- | --- |
| Workspace JSON | Display name, active tab, ordered/pinned pages, groups, content, timestamps, appearance, and presets | A compact snapshot or exchange with another profile |
| Complete Git repository | `workspace.json`, page files, README, and the entire `.git` history | Backup, migration, or continued version history on another computer |

### Export or import JSON

Choose **Export workspace JSON** and select a `.json` file. The export is a
versioned `qbt-material-workspace` document with all page content embedded.

Choose **Import workspace JSON** to replace the current display name, tabs,
content, and appearance with a snapshot. The confirmation is intentional: JSON
import replaces the live workspace. Every imported tab must contain its full
page text; the repository's internal metadata-only `workspace.json` is not a
portable snapshot and is rejected instead of creating empty pages.

Before applying a valid JSON snapshot, the application flushes and commits all
pending edits in the current workspace. The imported state then becomes another
commit in that repository. If writing or committing the imported state fails,
the previous in-memory workspace is restored and the application attempts to
commit that restoration, so a failed JSON import does not silently discard the
pages that were open before it.

### Export or import the complete repository

Choose **Export complete Git repository** and select a destination directory.
The application first saves pending work, then creates a timestamped child
folder containing a standalone copy of the managed repository and its history.

Choose **Import complete Git repository** and select an exported repository
folder. A repository import replaces both the current workspace and its local
Git history with the selected copy. The importer commits pending work, validates
and stages the incoming copy, and only then switches the managed repository.

After a successful switch, the previous complete repository is retained as a
hidden sibling named `.workspace-backup-<timestamp>-<id>` rather than deleted.
The success message reports its full path. Keep that folder until the imported
workspace and history have been verified; it can be archived as an additional
recovery copy.

If activation or post-activation validation fails, the application restores the
previous repository when possible. When automatic restoration cannot complete,
it blocks further workspace writes and preserves every available copy in the
repository's parent directory, including `.workspace-backup-*`,
`.workspace-import-*`, or `.workspace-failed-import-*` folders. The status and
error message point to that parent directory instead of overwriting a recovery
copy.

At the next launch, if the normal managed repository is missing after an
interrupted import, the application checks the newest valid
`.workspace-backup-*` sibling and restores it automatically.

## Startup recovery

If the process stops after a new tab body reaches `tabs/<uuid>.md` but before
the matching metadata update reaches `workspace.json`, the next launch sees
that the body is untracked, adopts it as a **Recovered tab**, and commits it. If
the manifest already records a close but the formerly tracked body remains, the
next launch completes that intentional close instead of resurrecting the tab.
The embedded Git index makes the two crash windows unambiguous.

Existing workspace files are never overwritten just because they fail startup
validation. If the managed repository exists but its metadata or page files are
invalid, the application first moves the complete directory to a hidden sibling
named `.workspace-recovery-<timestamp>-<id>`. It then creates a fresh Welcome
workspace and reports the preserved path in the Workspace status.

If the invalid directory cannot be moved safely, it is left untouched. The app
shows an in-memory Welcome page but blocks workspace saves and Git operations so
the original files cannot be replaced accidentally. The editor and mutating
actions visibly switch to read-only while navigation and repository inspection
remain available.

The backup and recovery directories live beside the normal `workspace-tabs`
folder and may be hidden by the operating-system file manager. Use **Open managed
repository**, move up to its parent directory, and enable hidden items to locate
them. Do not remove a `.workspace-backup-*`, `.workspace-recovery-*`,
`.workspace-import-*`, or `.workspace-failed-import-*` directory until the
active workspace is verified and any needed files or history have been copied
somewhere safe.

## Validation and privacy

Workspace data stays on the local computer unless it is explicitly exported or
shared. There is no remote push, cloud sync, or repository host configured by
the Workspace feature.

Imports enforce the current schema, unique UUID tab identifiers, valid colors,
font-size bounds, and these resource limits:

- 100 tabs;
- 32 groups and 32 named appearance presets;
- 4 MB of text per page;
- 32 MB per workspace JSON file;
- 256 MB per complete repository transfer.

Interactive regex evaluation additionally limits patterns to 4,096 characters,
sample text to 64 KiB, and returned matches to 200, with PCRE2 match/depth caps.

Unsafe symbolic-link or reparse-point paths are rejected, as are repository
folders nested inside the managed repository. Imported JSON and repository data
should still be treated like any other local file: review the source before
replacing a workspace you care about.

## Keyboard reference

| Shortcut | Action |
| --- | --- |
| `Alt+5` | Open the Workspace navigation destination |
| `Ctrl+T` | Create a workspace tab |
| `Ctrl+W` | Close the active workspace tab when Workspace is active |
| `Ctrl+S` | Save and commit pending workspace changes when Workspace is active |
| `Ctrl+Shift+A` | Open appearance for the focused Workspace tab or group |

See the [Workspace Tabs wiki guide](wiki/Workspace-Tabs.md) for the short
task-oriented walkthrough and [Troubleshooting](wiki/Troubleshooting.md) for
recovery guidance.

For feature-level behavior, failure modes, privacy, and verification, see
[Tab management and discovery](features/workspace/tab-management.md),
[Search and regex builder](features/workspace/search-and-regex.md), and
[Runtime appearance](features/appearance/runtime-appearance.md).
