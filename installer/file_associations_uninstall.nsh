; Restore the effective associations that existed before this installation.
; HKCR is a merged registry view, so only touch an association while its
; command still carries this installer's exact ownership marker. If another
; application took over after installation, leave that application's handler
; untouched and retain the private snapshot for diagnostics/reinstallation.

ReadRegStr $0 HKCR "qBittorrentMaterial.torrent\shell\open\command" ""
StrCmp $0 '"$INSTDIR\bin\qbittorrent.exe" "%1"' qbt_uninstall_torrent_owned qbt_uninstall_skip_torrent

qbt_uninstall_torrent_owned:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "Saved"
IfErrors qbt_uninstall_torrent_legacy_cleanup
StrCmp $1 1 qbt_uninstall_torrent_restore qbt_uninstall_torrent_legacy_cleanup

qbt_uninstall_torrent_restore:
; .torrent default value
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionDefaultPresent"
IfErrors qbt_restore_torrent_default_absent
StrCmp $1 1 qbt_restore_torrent_default_present qbt_restore_torrent_default_absent
qbt_restore_torrent_default_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionDefaultValue"
IfErrors qbt_restore_torrent_default_absent
WriteRegStr HKCR ".torrent" "" "$2"
Goto qbt_restore_torrent_content_type
qbt_restore_torrent_default_absent:
DeleteRegValue HKCR ".torrent" ""

qbt_restore_torrent_content_type:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionContentTypePresent"
IfErrors qbt_restore_torrent_content_type_absent
StrCmp $1 1 qbt_restore_torrent_content_type_present qbt_restore_torrent_content_type_absent
qbt_restore_torrent_content_type_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ExtensionContentTypeValue"
IfErrors qbt_restore_torrent_content_type_absent
WriteRegStr HKCR ".torrent" "Content Type" "$2"
Goto qbt_restore_torrent_description
qbt_restore_torrent_content_type_absent:
DeleteRegValue HKCR ".torrent" "Content Type"

qbt_restore_torrent_description:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdDescriptionPresent"
IfErrors qbt_restore_torrent_description_absent
StrCmp $1 1 qbt_restore_torrent_description_present qbt_restore_torrent_description_absent
qbt_restore_torrent_description_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdDescriptionValue"
IfErrors qbt_restore_torrent_description_absent
WriteRegStr HKCR "qBittorrentMaterial.torrent" "" "$2"
Goto qbt_restore_torrent_icon
qbt_restore_torrent_description_absent:
DeleteRegValue HKCR "qBittorrentMaterial.torrent" ""

qbt_restore_torrent_icon:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdIconPresent"
IfErrors qbt_restore_torrent_icon_absent
StrCmp $1 1 qbt_restore_torrent_icon_present qbt_restore_torrent_icon_absent
qbt_restore_torrent_icon_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdIconValue"
IfErrors qbt_restore_torrent_icon_absent
WriteRegStr HKCR "qBittorrentMaterial.torrent\DefaultIcon" "" "$2"
Goto qbt_restore_torrent_command
qbt_restore_torrent_icon_absent:
DeleteRegValue HKCR "qBittorrentMaterial.torrent\DefaultIcon" ""

qbt_restore_torrent_command:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdCommandPresent"
IfErrors qbt_restore_torrent_command_absent
StrCmp $1 1 qbt_restore_torrent_command_present qbt_restore_torrent_command_absent
qbt_restore_torrent_command_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent" "ProgIdCommandValue"
IfErrors qbt_restore_torrent_command_absent
WriteRegStr HKCR "qBittorrentMaterial.torrent\shell\open\command" "" "$2"
Goto qbt_restore_torrent_cleanup
qbt_restore_torrent_command_absent:
DeleteRegValue HKCR "qBittorrentMaterial.torrent\shell\open\command" ""

qbt_restore_torrent_cleanup:
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\shell\open"
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\shell"
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\DefaultIcon"
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent"
DeleteRegKey HKCU "Software\qBittorrentMaterial\AssociationBackup\torrent"
Goto qbt_uninstall_magnet_check

; Compatibility path for installations made before association snapshots were
; introduced. It is still ownership-guarded and removes only our values.
qbt_uninstall_torrent_legacy_cleanup:
ReadRegStr $1 HKCR ".torrent" ""
StrCmp $1 "qBittorrentMaterial.torrent" 0 qbt_uninstall_torrent_legacy_progid
DeleteRegValue HKCR ".torrent" ""
ReadRegStr $1 HKCR ".torrent" "Content Type"
StrCmp $1 "application/x-bittorrent" 0 qbt_uninstall_torrent_legacy_progid
DeleteRegValue HKCR ".torrent" "Content Type"

qbt_uninstall_torrent_legacy_progid:
DeleteRegValue HKCR "qBittorrentMaterial.torrent\shell\open\command" ""
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\shell\open"
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\shell"
ReadRegStr $1 HKCR "qBittorrentMaterial.torrent\DefaultIcon" ""
StrCmp $1 "$INSTDIR\bin\qbittorrent.exe,0" 0 qbt_uninstall_torrent_legacy_description
DeleteRegValue HKCR "qBittorrentMaterial.torrent\DefaultIcon" ""
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent\DefaultIcon"

qbt_uninstall_torrent_legacy_description:
ReadRegStr $1 HKCR "qBittorrentMaterial.torrent" ""
StrCmp $1 "BitTorrent Torrent" 0 qbt_uninstall_magnet_check
DeleteRegValue HKCR "qBittorrentMaterial.torrent" ""
DeleteRegKey /ifempty HKCR "qBittorrentMaterial.torrent"
Goto qbt_uninstall_magnet_check

qbt_uninstall_skip_torrent:

qbt_uninstall_magnet_check:
ReadRegStr $0 HKCR "magnet\shell\open\command" ""
StrCmp $0 '"$INSTDIR\bin\qbittorrent.exe" "%1"' qbt_uninstall_magnet_owned qbt_uninstall_skip_magnet

qbt_uninstall_magnet_owned:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "Saved"
IfErrors qbt_uninstall_magnet_legacy_cleanup
StrCmp $1 1 qbt_uninstall_magnet_restore qbt_uninstall_magnet_legacy_cleanup

qbt_uninstall_magnet_restore:
; magnet description
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "DescriptionPresent"
IfErrors qbt_restore_magnet_description_absent
StrCmp $1 1 qbt_restore_magnet_description_present qbt_restore_magnet_description_absent
qbt_restore_magnet_description_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "DescriptionValue"
IfErrors qbt_restore_magnet_description_absent
WriteRegStr HKCR "magnet" "" "$2"
Goto qbt_restore_magnet_protocol
qbt_restore_magnet_description_absent:
DeleteRegValue HKCR "magnet" ""

qbt_restore_magnet_protocol:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "ProtocolPresent"
IfErrors qbt_restore_magnet_protocol_absent
StrCmp $1 1 qbt_restore_magnet_protocol_present qbt_restore_magnet_protocol_absent
qbt_restore_magnet_protocol_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "ProtocolValue"
IfErrors qbt_restore_magnet_protocol_absent
WriteRegStr HKCR "magnet" "URL Protocol" "$2"
Goto qbt_restore_magnet_icon
qbt_restore_magnet_protocol_absent:
DeleteRegValue HKCR "magnet" "URL Protocol"

qbt_restore_magnet_icon:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "IconPresent"
IfErrors qbt_restore_magnet_icon_absent
StrCmp $1 1 qbt_restore_magnet_icon_present qbt_restore_magnet_icon_absent
qbt_restore_magnet_icon_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "IconValue"
IfErrors qbt_restore_magnet_icon_absent
WriteRegStr HKCR "magnet\DefaultIcon" "" "$2"
Goto qbt_restore_magnet_command
qbt_restore_magnet_icon_absent:
DeleteRegValue HKCR "magnet\DefaultIcon" ""

qbt_restore_magnet_command:
ClearErrors
ReadRegDWORD $1 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "CommandPresent"
IfErrors qbt_restore_magnet_command_absent
StrCmp $1 1 qbt_restore_magnet_command_present qbt_restore_magnet_command_absent
qbt_restore_magnet_command_present:
ClearErrors
ReadRegStr $2 HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet" "CommandValue"
IfErrors qbt_restore_magnet_command_absent
WriteRegStr HKCR "magnet\shell\open\command" "" "$2"
Goto qbt_restore_magnet_cleanup
qbt_restore_magnet_command_absent:
DeleteRegValue HKCR "magnet\shell\open\command" ""

qbt_restore_magnet_cleanup:
DeleteRegKey /ifempty HKCR "magnet\shell\open"
DeleteRegKey /ifempty HKCR "magnet\shell"
DeleteRegKey /ifempty HKCR "magnet\DefaultIcon"
DeleteRegKey /ifempty HKCR "magnet"
DeleteRegKey HKCU "Software\qBittorrentMaterial\AssociationBackup\magnet"
Goto qbt_uninstall_finish

qbt_uninstall_magnet_legacy_cleanup:
DeleteRegValue HKCR "magnet\shell\open\command" ""
DeleteRegKey /ifempty HKCR "magnet\shell\open"
DeleteRegKey /ifempty HKCR "magnet\shell"
ReadRegStr $1 HKCR "magnet\DefaultIcon" ""
StrCmp $1 "$INSTDIR\bin\qbittorrent.exe,0" 0 qbt_uninstall_magnet_legacy_description
DeleteRegValue HKCR "magnet\DefaultIcon" ""
DeleteRegKey /ifempty HKCR "magnet\DefaultIcon"

qbt_uninstall_magnet_legacy_description:
ReadRegStr $1 HKCR "magnet" ""
StrCmp $1 "URL:Magnet Link" 0 qbt_uninstall_magnet_legacy_protocol
DeleteRegValue HKCR "magnet" ""

qbt_uninstall_magnet_legacy_protocol:
; The command ownership check above makes this empty URL Protocol value ours;
; retain it if a user or another application has changed it to another value.
ReadRegStr $1 HKCR "magnet" "URL Protocol"
StrCmp $1 "" 0 qbt_uninstall_finish
DeleteRegValue HKCR "magnet" "URL Protocol"
Goto qbt_uninstall_finish

qbt_uninstall_skip_magnet:

qbt_uninstall_finish:
DeleteRegKey /ifempty HKCU "Software\qBittorrentMaterial\AssociationBackup"
System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
