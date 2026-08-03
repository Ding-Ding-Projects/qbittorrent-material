# Transfer-list export

The Windows desktop Transfers surface exports the torrent list through the
**Export list…** action above the list, or **Export transfer list…** in the
searchable row context menu. The dialog makes the scope explicit before a file
is chosen:

- all torrents in the session; or
- only the current selection.

The export is a UTF-8 file with LF line endings. The current 14-column summary
contains: Name, Info hash v1, Info hash v2, Size, Progress (%), State, Save path,
Category, Tags, Downloaded, Uploaded, Ratio, Added on, and Completed on. Size
matches the visible wanted size, progress is a numeric percentage from 0 to 100,
and State is the localized visible status (including an error detail when the
torrent supplies one). An unfinished torrent has an empty Completed on value.
The export is a summary rather than a full dump; fields not listed here are not
included.
The keyed formats derive field names from the active translated headers, so
those keys can vary with the selected UI language; the exported values and
column order remain the same. Date/time values are normalized to UTC ISO-8601
text across all formats, and non-finite numeric values are represented as
strings where a format cannot carry them as numbers. Hashes and local save
paths are included because they are part of the transfer record; users should
treat the resulting file as local profile data.

## Formats and configuration

The format picker offers JSON, JSON Lines, YAML, TOML, XML, CSV, TSV, Markdown,
HTML, and SQL. The file extension and native Save-file filter follow the selected
format. JSON and JSON Lines retain JSON scalar values. The other formats show a
plain-language loss note before saving when they coerce values to text or flatten
line breaks. SQL quotes generated identifiers and values, and HTML/XML escape
cell content rather than treating torrent names as markup.

There is no separate export preference and there is no importer for these
files. The chosen format, destination, and scope apply only to the current
operation; the source session is never changed. CSV/TSV prefix
formula-looking text with an apostrophe, and Markdown escapes table and inline
markup punctuation so metadata stays literal.

## Failure modes and security

- An empty session or empty selection produces a non-blocking error notification
  and no file.
- An unknown format, missing destination, unavailable session, or unwritable
  path produces a non-blocking error with the reason returned by the controller.
- The native Save-file picker supplies the platform's overwrite confirmation
  when applicable. Once accepted, existing destinations are replaced through
  Qt's atomic `QSaveFile` commit. The export has no configured size limit,
  progress meter, or cancellation control, so very large sessions or slow
  network shares should be exported when the desktop is otherwise idle.
- Export never evaluates cell content as HTML, XML, YAML, TOML, or SQL code.
  Escaping is performed by the serializer, and SQL nulls remain `NULL` while
  non-null values are stored as `TEXT`.
- The export can contain tracker-adjacent identifiers, hashes, categories, and
  local paths. Do not upload it to a third party unless those fields are safe to
  disclose.
- The selected destination is written to the application log and may be a
  network location; choose a local path when the export should remain local.
- A successful export is recorded in the notification centre and, when an
  external editor is configured and the destination path fits the notification
  action limit, offers **Open in editor** as a single action. Long paths omit
  that action rather than creating a truncated target.

## Verification

The source policy suite checks the ten format paths, escaping, valid generated
identifiers, scope/encoding/loss disclosures, both UI entry points, and this
article. The Windows Release build compiles the serializer through the `qbt_base`
glob and compiles the QML dialog through the `qBittorrent` module. The real
binary is then launched offscreen with `scripts/test-qml-startup.ps1` so a QML
type or binding failure cannot hide behind a successful compile.

Suggested related articles:

- [Transfer-list filtering](filtering.md)
- [Peer contribution](peer-contribution.md)
- [External editor integration](../workspace/external-editor.md)
