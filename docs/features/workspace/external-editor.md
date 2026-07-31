# External Editor Integration

## Behavior

The Windows desktop app detects Visual Studio Code, VSCodium, Cursor, Sublime
Text, Notepad++, and Notepad from installed commands. A user can also choose a
custom executable. The selected editor and custom path are persisted.

The quick Settings sheet can open the managed Workspace folder in the selected
editor. The backend accepts an existing file or folder and launches the editor
directly with that path as one argument. It does not invoke a command shell.

## Configuration

Open quick Settings and find **External editor**. Choose a detected editor,
browse for a custom executable, or refresh detection after installing one.
**Open workspace** is enabled only when both an editor and the managed Workspace
repository are available.

Notepad remains available for individual files but is explicitly rejected for
project-folder launch because it is not a folder-aware editor.

## Failure modes

- When no supported editor is found, Settings explains that a custom executable
  can be selected.
- A missing target file or folder produces a non-blocking failure message.
- A removed or invalid editor executable produces a launch failure and leaves
  the configured path available for correction.
- Selecting Notepad for a folder reports the capability mismatch rather than
  pretending the folder opened.

## Security and privacy

Launching an editor grants that external program access to the selected file or
managed Workspace repository, including its local Git history. Only configure
software you trust. The app passes a concrete existing path directly to
`QProcess::startDetached`; it does not concatenate user input into a shell
command or upload files.

## Verification

- Targeted MSVC compilation passed for the desktop integration changes.
- Acceptance should detect each available editor, persist a selection across
  restart, open a file and the Workspace folder, exercise Notepad's folder
  refusal, remove a configured executable, and verify the resulting
  notification.
- The desktop policy test requires the Settings and Workspace integration but
  deliberately does not launch third-party software in CI.

## Related articles

- [Local version history](local-version-history.md)
- [Tab management and discovery](tab-management.md)
- [Notification center](../experience/notifications.md)
