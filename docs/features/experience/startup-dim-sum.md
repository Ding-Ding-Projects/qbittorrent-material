# Startup Dim-Sum Surprise

## Behavior

On each eligible launch the app makes one fresh random draw. Exactly one outcome
out of 100 displays a non-blocking corner card for 8 seconds. The card names the
dish in the active language mode, includes meaningful localized alt text, and
uses one of three bundled images:

- Shrimp dumpling · 蝦餃 (`har-gow.png`)
- Pork and shrimp siu mai · 燒賣 (`siu-mai.png`)
- Puff-pastry egg tart · 酥皮蛋撻 (`egg-tart.png`)

The card does not take focus or delay the main window. Reduced-motion mode
removes its transition.

The draw is skipped during first run, capture mode, and blocking startup flows.
It cannot occur twice in one process launch.

## Configuration

The feature is enabled by default. Open the quick Settings sheet and turn off
**Dim sum startup surprise**, or use the disable action on the card. The setting
is persisted and an off value is honored before any random draw.

## Failure modes

- A missing or malformed dish catalog produces no surprise and does not block
  startup.
- A missing image leaves that dish unavailable to a valid release build; the
  desktop policy test fails before packaging.
- Disabling the feature while the card is visible dismisses it immediately.
- The capture harness can explicitly force the surface for evidence; ordinary
  capture runs suppress it so screenshots remain deterministic.

## Security and privacy

The catalog and PNG files are local resources. There are no CDN requests,
analytics calls, or tracking pixels. The random draw uses the platform-backed
Qt random generator and is not persisted as a user profile signal.

## Verification

- `scripts/test-desktop-policy.ps1` parses the three catalog records, checks
  unique identifiers and bilingual alt text, validates each PNG signature, and
  decodes every image with the Windows image decoder.
- The integrated Windows build passed, and the real capture path rendered the
  forced dim-sum surface after runtime integration fixes.
- Release automation attaches the existing `har-gow.png` asset and identifies
  it as Shrimp dumpling · 蝦餃 in the release notes.
- Runtime acceptance should force the card once through the capture harness,
  verify no focus movement, check the 8-second dismissal, then disable it and
  prove the controller will not show it again.

## Related articles

- [Language modes and funny levels](language-and-funny-levels.md)
- [Immutable Windows releases](../delivery/windows-releases.md)
- [Notification center](notifications.md)
