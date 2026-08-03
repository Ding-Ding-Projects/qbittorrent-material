# Searchable context actions

## Behavior

**Every** context menu in the application starts with a local **Search actions**
field: the transfer row, the execution log, the torrent content tree, the RSS
feeds, articles and rules lists, the search-plugin, search-result and search-tab
menus, and the toolbar text-position menu. Typing filters only that open menu's
visible commands; it does not alter the torrent list, log buffer, feed
selection, results, or any command's behavior. The field receives keyboard focus
when the menu opens, and Escape closes the menu.

All of them derive from the shared `SearchableMenu` component, so the field, its
focus behavior, its regex builder and the menu's sizing come from one place
rather than being re-implemented per menu — which is how eight of the ten menus
previously ended up with no search field at all.

## Regex

The menu's search field is a `FilterTextField`, so each menu carries its own
anchored regex builder bound to that menu's own query and flags — nothing is
shared between menus. Plain-text matching is the default and regex is an
explicit opt-in. Matching runs through the application's own engine
(`QRegularExpression`) rather than JavaScript's, so a pattern behaves in a menu
exactly as it does in every other search surface. An invalid pattern matches
nothing rather than throwing.

## Sizing

Menu items render their keyboard shortcut in a right-anchored label. An anchored
child contributes nothing to a menu's implicit width, so a menu sized purely
from its content collapsed to the label width and painted the shortcut on top of
the text. `SearchableMenu` establishes a density-scaled minimum width wide
enough for a label and its shortcut, and still grows past it for longer content
and longer localized strings.

The menu is bounded by the window height and scrolls inside that bound. Capping
the height and clipping instead would silently delete the last items with no
scrollbar to indicate anything was missing.

## Shortcuts

Context commands display a shortcut only when that shortcut is registered and
works on the owning surface. Transfer Start, Stop, and Remove read their labels
from the same shared actions used by the application menu and keyboard handling.
Log Copy displays `Ctrl+C`, matching the focused log view's key handler.
Commands without a real binding leave the shortcut column empty rather than
padding it with a placeholder.

## Implementation notes

`SearchableMenu` installs its reset-on-show and focus-on-open behavior through a
`Connections` block rather than `onAboutToShow:`/`onOpened:` handlers. A handler
declared in the base type is replaced outright when a deriving menu declares its
own, which would silently cost that menu its query reset and its keyboard focus.

## Verification

Repository policy checks require every `*ContextMenu.qml` to derive from
`SearchableMenu`, the base to filter through the application's regex engine and
expose the builder, the width floor and bounded scrolling to be present, and the
base handlers to survive a deriving menu declaring its own.

## Related articles

- [Windows Desktop Features](../README.md)
