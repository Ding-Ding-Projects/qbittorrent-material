# Language Modes and Funny Levels

## Behavior

The desktop app has three live language modes: English, playful Hong Kong-style
Cantonese, and a compact bilingual mode that composes English and Cantonese.
Changing the mode retranslates existing QML bindings without restarting the
application.

English and Cantonese each have an independent funny-level value from 1 to 5.
Level 1 is professional; level 5 applies the strongest voice styling. The
levels change presentation, never identifiers, numbers, paths, consequences,
or recovery instructions. The settings surface discloses that the voice level
also applies to errors and warnings.

The default levels are English 1 and Cantonese 3. Bilingual mode uses both
current levels.

## Configuration

Open full Options and use the Behavior page. The language and both sliders are
staged with the rest of the Options transaction:

- **Apply** or **OK** persists all three values together and retranslates the
  running interface.
- **Cancel** discards the staged values.
- **Reset funny levels** restores the two defaults without changing the chosen
  language.

The values are stored in the application preferences and restored on the next
launch.

## Failure modes

- Values outside 1–5 are clamped before use, so malformed preferences cannot
  select an unsupported voice level.
- A missing Cantonese entry falls back to factual English.
- A translated entry whose placeholders do not match the English source also
  falls back to English rather than dropping or corrupting values.
- If the translator is unavailable, the controller logs the condition and
  keeps the factual source text.

## Security and privacy

The Cantonese catalog is a bundled JSON resource. The app does not send source
strings, selected language, or funny levels to a translation service. Format
placeholder parity is checked locally so translated copy cannot silently
discard runtime values.

## Verification

- Targeted MSVC object compilation and QML-cache generation passed for the
  language-controller and Behavior-page changes.
- `scripts/test-desktop-policy.ps1` parses the case-sensitive Cantonese catalog
  and checks the language, disclosure, and independent slider labels.
- The final parity scan found 1,178 unique source literals and zero missing
  translations. Its 1,989-key catalog has no exact duplicates or placeholder,
  newline, mnemonic, glob, HTML, unit-token, or changelog fact mismatches; all
  37 unique changelog title/change strings are covered.
- Runtime acceptance should switch all three modes, exercise levels 1 and 5 in
  both languages, restart the app to prove persistence, and verify that Apply
  and Cancel keep their transactional meanings.

## Related articles

- [Notification center](notifications.md)
- [Startup dim-sum surprise](startup-dim-sum.md)
- [Runtime appearance and element editor](../appearance/runtime-appearance.md)
