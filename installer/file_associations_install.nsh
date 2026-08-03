; Register the app as the handler for .torrent files and magnet: links so
; double-clicking a .torrent or clicking a magnet link launches it with the
; source as argv[1] (Application::run() adds it on cold start).
;
; Before taking ownership, retain the effective registry values in HKCU. The
; uninstaller uses those snapshots to restore the association that was there
; before this installation, even when the previous handler was another app.
; A snapshot is created only once and is kept across upgrades.
;
; This lives in its own .nsh file (included verbatim via CPACK_NSIS_EXTRA_
; INSTALL_COMMANDS with a single !include line) instead of being embedded as
; a CMake string, because round-tripping quotes/backslashes through
; CMakeLists.txt -> CPackConfig.cmake -> project.nsi corrupts them.

; Do not replace a snapshot from an earlier installation. If the current
; command already belongs to us, this is an upgrade and the original snapshot
; remains the one the final uninstall must restore.
ReadRegStr $0 HKCR "qBittorrentMaterial.torrent\shell\open\command" ""
StrCmp $0 '"$INSTDIR\bin\qbittorrent.exe" "%1"' qbt_install_torrent_write qbt_install_torrent_backup_check

qbt_install_torrent_backup_check:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "Saved"
IfErrors qbt_install_torrent_capture
Goto qbt_install_torrent_write

qbt_install_torrent_capture:
ClearErrors
ReadRegStr $1 HKCR ".torrent" ""
IfErrors qbt_install_torrent_default_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionDefaultValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionDefaultPresent" 1
qbt_install_torrent_default_absent:
ClearErrors
ReadRegStr $1 HKCR ".torrent" "Content Type"
IfErrors qbt_install_torrent_content_type_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionContentTypeValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionContentTypePresent" 1
qbt_install_torrent_content_type_absent:
ClearErrors
ReadRegStr $1 HKCR "qBittorrentMaterial.torrent" ""
IfErrors qbt_install_torrent_description_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdDescriptionValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdDescriptionPresent" 1
qbt_install_torrent_description_absent:
ClearErrors
ReadRegStr $1 HKCR "qBittorrentMaterial.torrent\DefaultIcon" ""
IfErrors qbt_install_torrent_icon_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdIconValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdIconPresent" 1
qbt_install_torrent_icon_absent:
ClearErrors
ReadRegStr $1 HKCR "qBittorrentMaterial.torrent\shell\open\command" ""
IfErrors qbt_install_torrent_command_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdCommandValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdCommandPresent" 1
qbt_install_torrent_command_absent:
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "Saved" 1

qbt_install_torrent_write:
WriteRegStr HKCR ".torrent" "" "qBittorrentMaterial.torrent"
WriteRegStr HKCR ".torrent" "Content Type" "application/x-bittorrent"
WriteRegStr HKCR "qBittorrentMaterial.torrent" "" "BitTorrent Torrent"
WriteRegStr HKCR "qBittorrentMaterial.torrent\DefaultIcon" "" "$INSTDIR\bin\qbittorrent.exe,0"
WriteRegStr HKCR "qBittorrentMaterial.torrent\shell\open\command" "" '"$INSTDIR\bin\qbittorrent.exe" "%1"'

ReadRegStr $0 HKCR "magnet\shell\open\command" ""
StrCmp $0 '"$INSTDIR\bin\qbittorrent.exe" "%1"' qbt_install_magnet_write qbt_install_magnet_backup_check

qbt_install_magnet_backup_check:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "Saved"
IfErrors qbt_install_magnet_capture
Goto qbt_install_magnet_write

qbt_install_magnet_capture:
ClearErrors
ReadRegStr $1 HKCR "magnet" ""
IfErrors qbt_install_magnet_description_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "DescriptionValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "DescriptionPresent" 1
qbt_install_magnet_description_absent:
ClearErrors
ReadRegStr $1 HKCR "magnet" "URL Protocol"
IfErrors qbt_install_magnet_protocol_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "ProtocolValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "ProtocolPresent" 1
qbt_install_magnet_protocol_absent:
ClearErrors
ReadRegStr $1 HKCR "magnet\DefaultIcon" ""
IfErrors qbt_install_magnet_icon_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "IconValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "IconPresent" 1
qbt_install_magnet_icon_absent:
ClearErrors
ReadRegStr $1 HKCR "magnet\shell\open\command" ""
IfErrors qbt_install_magnet_command_absent
WriteRegStr HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "CommandValue" "$1"
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "CommandPresent" 1
qbt_install_magnet_command_absent:
WriteRegDWORD HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "Saved" 1

qbt_install_magnet_write:
WriteRegStr HKCR "magnet" "" "URL:Magnet Link"
WriteRegStr HKCR "magnet" "URL Protocol" ""
WriteRegStr HKCR "magnet\DefaultIcon" "" "$INSTDIR\bin\qbittorrent.exe,0"
WriteRegStr HKCR "magnet\shell\open\command" "" '"$INSTDIR\bin\qbittorrent.exe" "%1"'
System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
