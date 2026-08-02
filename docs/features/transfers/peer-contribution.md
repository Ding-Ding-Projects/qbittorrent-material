# Peer contribution

The native Peers properties table includes qBittorrent's **Contribution**
column. It estimates how much of a connected peer's current progress was
uploaded by this client and displays the result as a percentage with one decimal
place.

The calculation follows [upstream qBittorrent commit `5c769abc86`](https://github.com/qbittorrent/qBittorrent/commit/5c769abc86f70ef6a3db4166dc55dc8bc98d4ea9):

```text
contribution = uploaded to peer / (peer progress * torrent total size)
```

When metadata size or peer progress is unavailable, the same guarded fallbacks
as upstream prevent division by zero. A peer with no uploaded bytes shows
`0.0%`. The table sorts Contribution by its raw numeric fraction rather than by
the formatted percentage text, and keeps the selected sort after each async peer
refresh.

Verification is source-level and build-level: the peer model exposes formatted
and raw contribution roles, the Peers table declares the column, and desktop
policy checks guard the calculation and UI contract. Live values still depend
on connected peers and libtorrent's runtime counters.
