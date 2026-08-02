# Transfer-list filtering

## Behavior

The transfer toolbar filters one selected field at a time: torrent name, save
path, BitTorrent v1 info hash, or BitTorrent v2 info hash. Hash matching is
case-insensitive and accepts partial values, which makes a pasted prefix enough
to locate a transfer. Hybrid torrents can be found through either hash field.

The field selector mirrors qBittorrent desktop's filter-by control. Changing
the selected field immediately reapplies the current query; it does not clear
the query or any status, category, tag, or tracker filter.

## Configuration

Plain mode retains the existing wildcard behavior. Choose the expression
affordance in the text field to use a Qt regular expression instead. Both modes
apply to whichever field is selected in **Filter by**.

## Failure modes

- An invalid regular expression matches no transfers until it is corrected or
  regular-expression mode is disabled.
- A v1-only torrent has no v2 value and cannot match a v2 query; the inverse is
  true for a v2-only torrent.
- Save-path matching uses the path reported by the active torrent session.

## Security and privacy

Filtering is performed locally against the in-memory transfer model. Names,
paths, and hashes are not transmitted or added to telemetry.

## Verification

Desktop policy checks require all four upstream-compatible choices, the proxy
column property, and separate v1/v2 matching branches. Compile verification
covers the C++ proxy and QML cache. Runtime acceptance should exercise partial
v1 and v2 hashes, hybrid torrents, save paths, wildcard names, regular
expressions, invalid expressions, and switching fields without clearing text.

