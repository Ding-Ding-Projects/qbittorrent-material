# Tab Management and Discovery

## Behavior

The personal Workspace uses a browser-style tab strip backed by schema 2 state.
It persists physical tab order, a stable pinned region, tab groups, group order,
group membership, group collapse, and appearance overrides. Schema 1 workspaces
remain readable and are upgraded when saved.

Individual tabs can be pinned or unpinned from the context menu and keyboard
paths. Pinned tabs stay visible in a dedicated region, can be reordered within
that region, survive ordinary overflow, and are preserved by close-others.

Groups can be created, named, renamed, colored, reordered, collapsed, expanded,
and removed. Tabs can move into or out of a group by pointer or explicit menu
action. Removing a group does not silently delete its member pages. Groups are
not pinned as a unit; pinning remains an individual-tab property.

An explicit overflow surface prevents silent clipping. Four independent search
surfaces are available:

1. current tab strip;
2. one search per tab group;
3. group-name search; and
4. master search across the app-owned Workspace tabs.

Results identify the strip, group, pinned state, and visible label. Activating a
result in a collapsed group reveals it transiently without changing the saved
collapse preference. The app currently owns one Workspace manager and one
window, so the master result set is complete for this application model rather
than a claim of unimplemented multi-window aggregation.

## Configuration

Use a tab or group header's normal context menu for management commands.
Shift+right-click opens appearance directly, while `Ctrl+Shift+A` provides the
keyboard appearance path. The search control on the strip opens the discovery
panel. Group headers provide their own scoped search.

The model accepts at most 100 tabs and 32 groups. Workspace JSON is limited to
32 MiB and each page body to 4 MiB.

## Bulk close

Both **Close tabs containing text** and **Close tabs not containing text** use
the same visible-label predicate. Plain text is the default; regex is opt-in.
An empty query or invalid expression cannot execute. A review step shows the
scope and affected tabs before confirmation.

Pinned tabs are excluded by default. Including them is an explicit choice. The
Workspace checkpoints dirty state into its local Git history before a
destructive bulk close, and existing write failures leave the affected tabs
open.

## Failure modes

- Invalid, duplicate, or dangling group identifiers are rejected or normalized
  during import.
- A tab whose stored group no longer exists becomes ungrouped instead of
  disappearing.
- Overflow remains available at narrow widths; tabs are not clipped off-screen.
- Read-only workspace state disables mutating actions and reports the failure.
- Empty groups are removed only according to the explicit group operation or
  the model's documented empty-group cleanup, not as a side effect of search.

## Security and privacy

Tab discovery evaluates labels locally and does not inspect page bodies for
bulk close. Imported state is size-bounded and schema-validated before it can
replace live state. Search text and group names are not transmitted.

## Verification

- WorkspaceManager targeted MSVC compilation and the new tab-strip/search QML
  cache generation passed.
- The release smoke validates schema 2 persistence and crash recovery in the
  installed application.
- Runtime UI automation is still required for pointer reorder, keyboard
  reorder, overflow at narrow widths, pinned protection, collapsed-group result
  activation, and both bulk-close confirmation paths.

## Related articles

- [Search and regex builder](search-and-regex.md)
- [Local version history](local-version-history.md)
- [Runtime appearance and element editor](../appearance/runtime-appearance.md)
