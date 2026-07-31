# Runtime Appearance and Element Editor

## Behavior

The application-wide appearance layer persists color scheme, one of the three
desktop layouts, density, Material seed color, UI font family, font-size scale,
font weight, and reduced motion. Changes are applied to the live interface.
Global appearance can be reset from the searchable quick Settings sheet.

The personal Workspace adds sparse global, group, and tab overrides. Resolution
is predictable: app defaults, then Workspace global values, then group values,
then the target tab. A child stores only properties it overrides, so resetting
one value reveals the inherited value without copying a stale theme.

Normal right-click on a tab or group includes its appearance command.
Shift+right-click opens the editor directly, and `Ctrl+Shift+A` is the keyboard
path. The non-modal editor anchors to the originating element, adjusts for
viewport edges, and returns focus when it closes. A dedicated preview shows the
resolved target appearance.

## Typography controls

The editor searches installed fonts and renders font-family previews. It
supports family and style, free-entry and stepped size, numeric weight, bold,
italic/oblique, underline metadata, single and double strikethrough, overline,
capitalization and small caps, superscript and subscript, text and highlight
color, shadow, character and word spacing, line height, baseline offset, text
direction, and alignment.

Qt Quick limitations are visible rather than silently hidden:

- double strikethrough previews as one strike;
- custom underline style/color and outline/glow are persisted metadata but are
  not rendered by the current QML preview;
- shadow uses a lightweight offset approximation; and
- arbitrary variable-font axes beyond family/style/numeric weight depend on the
  backend and do not get synthesized axis controls.

## Color and geometry controls

The color studio combines a continuous saturation/value field with hue and
alpha controls. It translates bidirectionally among named color, HEX8, RGBA,
HSLA, HSVA, HWB, CIELAB/LCH, OKLab/OKLCH, and CMYK representations. It includes
copy actions, swatches, recent colors, contrast evidence, and explicit review
before wide-gamut input is clipped to sRGB.

Target geometry and identity controls include background/foreground and state
colors, borders, radius, padding, spacing, opacity, icon/emoji, and badges.

## Configuration and portability

The editor search bar has its own adjacent full regex builder. Reset is
available per working property, per persisted target, and globally. Named
presets can be saved, applied, removed, imported, and exported in a versioned
JSON format. Up to 32 presets are stored with Workspace state.

The editor chrome follows the application Theme. The dedicated preview applies
the working target values live; applying every unfinished target override
recursively to all editor controls is not currently proven.

## Failure modes

- Invalid colors and values remain visible for correction and are not silently
  persisted.
- Unsupported rendered effects keep their stored metadata and show the
  platform limitation.
- A read-only Workspace prevents save and reports the error without closing the
  editor.
- Invalid or unsupported preset JSON is rejected before it changes a target.
- Closing without Apply leaves persisted appearance unchanged.

## Security and privacy

Font enumeration, previews, color conversion, and contrast calculation are
local. The editor does not download fonts or send preset data to a service.
Preset files are untrusted input: version, structure, values, and Workspace size
limits are checked before adoption. Export occurs only to a user-selected file.

## Verification

- Direct Qt 6.8.3 `qmlcachegen` passed for the complete editor; WorkspaceManager
  targeted MSVC compilation and tab-strip/search QML cache generation also
  passed. `git diff --check` reports no whitespace errors in the implementation.
- File-dialog import/export, collision-aware anchoring, context-menu paths, and
  keyboard behavior are compiled but have not yet received live UI-automation
  or fresh capture evidence.
- Runtime acceptance should cover every inheritance level, each reset scope,
  narrow-window collision, all color representations, clipping review,
  contrast, installed-font search, unsupported-effect disclosure, preset
  round-trip, restart persistence, and keyboard focus return.

## Related articles

- [Tab management and discovery](../workspace/tab-management.md)
- [Search and regex builder](../workspace/search-and-regex.md)
- [Language modes and funny levels](../experience/language-and-funny-levels.md)
