# Searchable context actions

The primary transfer-row and execution-log context menus start with a local
**Search actions** field. Typing filters only that open menu's visible commands;
it does not alter the torrent list, log buffer, selection, or command behavior.
The field receives keyboard focus when the menu opens, and Escape closes the
menu.

Context commands display a shortcut only when that shortcut is registered and
works on the owning surface. Transfer Start, Stop, and Remove read their labels
from the same shared actions used by the application menu and keyboard handling.
Log Copy displays `Ctrl+C`, matching the focused log view's key handler. Commands
without a real binding leave the shortcut column empty.
