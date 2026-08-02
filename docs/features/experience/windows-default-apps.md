# Windows Default Apps integration

## Behavior

On Windows, **Options → Behavior → Desktop → File association** explains that
`.torrent` files and Magnet links are assigned by the operating system. **Open
Windows Default Apps settings page** opens the per-user Windows Default Apps
surface, where each file or link type can be assigned manually.

The action follows upstream qBittorrent: it starts the system `explorer.exe`
with the `ms-settings:defaultapps` URI. The panel is absent on other platforms.
Opening Settings does not modify an option transaction, so **Apply**, **OK**,
and **Cancel** remain concerned only with staged qBittorrent preferences.

## Configuration

No qBittorrent preference is stored. Windows owns the resulting associations.
The exact controls presented after launch depend on the installed Windows
version and its current Default Apps policy.

## Failure modes

The application reports whether Windows accepted the detached Settings launch.
Policy restrictions, a missing system handler, or failure to start Explorer
produce an error notification without changing any association.

## Security and privacy

The executable path is derived from Windows' system directory and the URI is a
fixed application constant. No user-controlled command or shell text is
executed, and no network request is required by qBittorrent Material.

## Verification

Desktop policy checks cover the Windows-only capability property, the fixed
Settings URI, system Explorer dispatch, QML visibility guard, accessible button
description, and action wiring. Live acceptance still depends on Windows and is
verified separately from headless compilation.
