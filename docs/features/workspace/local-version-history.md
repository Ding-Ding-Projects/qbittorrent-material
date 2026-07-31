# Local Version History

## Behavior

The desktop app keeps Git-backed history in app-managed data locations rather
than placing a `.git` directory in an arbitrary user folder.

The personal Workspace commits page content, tab metadata, ordering, pin and
group state, and appearance changes through bundled libgit2. A separate action
journal records supported torrent operations, and a settings repository records
settings changes with auto-commit always on. The History sheet switches between
the action and settings repositories, searches commit message or SHA, shows
diffs, copies commit identifiers, and exports the visible history as JSON.

Undo and restore operations append a new revision. They do not rewrite or
discard the history being restored, so a restore can itself be undone.

## Configuration

Open the header History button. Settings provides retention choices of 30 days,
1 year, or forever and links to the same history surface. Workspace exports can
produce either compact JSON state or a complete local repository; complete
repository export is the option that carries every commit.

## Failure modes

- A history-write failure is logged and must not cancel the torrent, settings,
  or Workspace operation the user requested.
- Unchanged state does not create a meaningless revision.
- A restore conflict reports skipped or failed records instead of claiming a
  complete restore.
- Workspace crash recovery adopts a fully written orphan page and completes an
  interrupted close without resurrecting an intentionally closed tab.
- Settings history is always on; an older stored “off” preference cannot
  silently disable it.

## Security and privacy

History remains local unless the user explicitly exports it. Workspace page
content is plain text, and history can retain previous content after the live
page is edited or deleted. Action and settings revisions can contain torrent
names, paths, and configuration values. Treat repository and JSON exports as
sensitive user data and do not publish them casually.

The version repositories are not pushed automatically. Downloaded payload data
is not copied into the action journal, and restore does not overwrite downloaded
content.

## Verification

- The release smoke starts the installed app with Git removed from `PATH`,
  checks the managed repository, simulates both crash windows, runs strict Git
  integrity checking, and requires a clean final repository.
- WorkspaceManager and journal targeted compilation cover the append-only
  interfaces.
- Runtime acceptance should create, modify, delete, undo, restore, restart,
  prune by each retention policy, and round-trip both JSON and complete-repo
  exports.

## Related articles

- [Tab management and discovery](tab-management.md)
- [External editor integration](external-editor.md)
- [Notification center](../experience/notifications.md)
