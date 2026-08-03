; Remove only values that still belong to this installation. HKCR is a merged
; view of per-user and machine-wide registrations, so deleting shared keys
; unconditionally can remove another application's association.
;
; The open-command value is the ownership marker: if another application has
; taken over either association, leave the whole registration alone. This
; installer predates registry backups, so preserving a changed association is
; safer than pretending it can restore an unknown previous value.
ReadRegStr $0 HKCR "qBittorrentMaterial.torrent\shell\open\command" ""
StrCmp $0 '"$INSTDIR\bin\qbittorrent.exe" "%1"' 0 qbt_uninstall_skip_torrent

ReadRegStr $1 HKCR ".torrent" ""
StrCmp $1 "qBittorrentMaterial.torrent" 0 qbt_uninstall_torrent_progid
DeleteRegValue HKCR ".torrent" ""
ReadRegStr $1 HKCR ".torrent" "Content Type"
StrCmp $1 "application/x-bittorrent" 0 qbt_uninstall_torrent_progid
DeleteRegValue HKCR ".torrent" "Content Type"

qbt_uninstall_torrent_progid:
DeleteRegValue HKCR "qBittorrentMaterial.torrent\shell\open\command" ""
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\shell\open"
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\shell"
ReadRegStr $1 HKCR "qBittorrentMaterial.torrent\DefaultIcon" ""
StrCmp $1 "$INSTDIR\bin\qbittorrent.exe,0" 0 qbt_uninstall_torrent_description
DeleteRegValue HKCR "qBittorrentMaterial.torrent\DefaultIcon" ""
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\DefaultIcon"

qbt_uninstall_torrent_description:
ReadRegStr $1 HKCR "qBittorrentMaterial.torrent" ""
StrCmp $1 "BitTorrent Torrent" 0 qbt_uninstall_skip_torrent
DeleteRegValue HKCR "qBittorrentMaterial.torrent" ""
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent"

qbt_uninstall_skip_torrent:
ReadRegStr $0 HKCR "magnet\shell\open\command" ""
StrCmp $0 '"$INSTDIR\bin\qbittorrent.exe" "%1"' 0 qbt_uninstall_skip_magnet

DeleteRegValue HKCR "magnet\shell\open\command" ""
DeleteRegKey /ifempty HKCR "magnet\shell\open"
DeleteRegKey /ifempty HKCR "magnet\shell"
ReadRegStr $1 HKCR "magnet\DefaultIcon" ""
StrCmp $1 "$INSTDIR\bin\qbittorrent.exe,0" 0 qbt_uninstall_magnet_description
DeleteRegValue HKCR "magnet\DefaultIcon" ""
DeleteRegKey /ifempty HKCR "magnet\DefaultIcon"

qbt_uninstall_magnet_description:
ReadRegStr $1 HKCR "magnet" ""
StrCmp $1 "URL:Magnet Link" 0 qbt_uninstall_magnet_protocol
DeleteRegValue HKCR "magnet" ""

qbt_uninstall_magnet_protocol:
; The command ownership check above makes this empty URL Protocol value ours;
; retain it if a user or another application has changed it to another value.
ReadRegStr $1 HKCR "magnet" "URL Protocol"
StrCmp $1 "" 0 qbt_uninstall_magnet_cleanup
DeleteRegValue HKCR "magnet" "URL Protocol"

qbt_uninstall_magnet_cleanup:
DeleteRegKey /ifempty HKCR "magnet"

qbt_uninstall_skip_magnet:
System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
