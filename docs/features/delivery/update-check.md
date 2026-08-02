# In-app Update Check

## Behavior

**Check for updates** starts an asynchronous request to this project's public
latest-release endpoint. The application remains usable while the request is in
flight. A second request is not started while one is already active.

The checker accepts only a full, stable release whose tag matches the immutable
`build-<run-number>-<commit-prefix>` convention. It compares the monotonic run
number with the `build.<run-number>.<commit-prefix>` identity compiled into a
release package. A local development build has no published identity, so a valid
published release is offered instead of being reported as equivalent.

When the latest build is newer, the existing non-modal notification reports its
tag. When the identities match, the app reports that it is current.

## Failure modes

Network errors, oversized responses, invalid JSON, draft or prerelease objects,
and unsupported tags produce a non-blocking failure notification. They never
fall through to the "up to date" message. Users can retry later; the application
does not download or install an update automatically.

## Security and privacy

The request contains the app's release build identity in its user agent and uses
the configured general-purpose proxy preference. No torrent, transfer, Workspace,
or personal data is sent. Responses are capped at 256 KiB and must match the
repository's release schema before they influence the result.

## Verification

The release parser and comparison are isolated in `src/app/updatecheck.*` so
malformed payload, stable-release, development-build, older-build, same-build,
and newer-build cases can be tested without a live request. Repository policy
checks require the bounded asynchronous request, stable-release validation,
compiled build identity, and failure-safe notification path.

## Related articles

- [Immutable Windows releases](windows-releases.md)
- [Building qBittorrent Material](../../BUILDING.md)
- [Windows Desktop Features](../README.md)
