# Search and Regex Builder

## Behavior

Desktop filter fields use plain-text matching by default. Each `FilterTextField`
has its own adjacent builder affordance; opening one preserves that field's
query, mode, flags, validation, and sample text. Applying a pattern writes those
values back to the originating field.

The full builder uses the application's real Qt `QRegularExpression` engine
(PCRE2), not JavaScript regular expressions. It provides:

- a raw pattern editor and guided tokens for literals, character classes,
  anchors, groups, alternation, and quantifiers;
- `g`, `i`, `m`, `s`, and `u` controls, with `g` controlling result collection
  and Unicode properties enabled for evaluation;
- editable sample text, syntax feedback, live matches, and capture groups;
- saved builder presets; and
- copy plus versioned JSON clipboard export.

Workspace evaluation limits patterns to 4,096 characters, sample text to
64 KiB, and displayed results to 200. PCRE2 match and depth limits are inserted
before the user expression. Zero-width matches advance safely.

The four Workspace discovery searches, both bulk-close actions, the quick
Settings search, changelog search, and existing fields built from
`FilterTextField` each retain independent state. No hidden shared “last field”
determines where a pattern is applied.

## Configuration

Type normally for plain text. Use the adjacent expression button to open the
anchored builder, then explicitly enable regex and choose flags. **Apply** sends
the pattern and flags back to that field; closing the builder leaves the field
unchanged.

Saved builder presets are local application data. Clipboard export is a JSON
representation; it is not a direct file write.

## Failure modes

- Invalid syntax displays the engine's error and blocks Apply or destructive
  bulk-close execution.
- Patterns or samples over the limits are rejected before evaluation.
- Match/depth exhaustion returns a bounded failure instead of hanging the UI.
- No-match is a valid result and uses an honest empty state.
- Unsupported flags are removed during normalization rather than passed to a
  different regex dialect.

## Security and privacy

Patterns and sample text are evaluated locally. They are not uploaded or added
to telemetry. Bounds and PCRE2 limits reduce catastrophic-backtracking risk,
but users should still treat expressions imported from untrusted sources as
code-like input and review them before enabling a bulk action.

## Verification

- Targeted WorkspaceManager compilation covers Qt expression validation,
  evaluation, search results, and bulk-close predicates.
- QML-cache generation passed for `RegexBuilderSheet.qml`,
  `FilterTextField.qml`, Workspace discovery, and the settings integration.
- Acceptance should cover valid, invalid, no-match, Unicode, multiline,
  zero-width, capture-group, adversarial, and plain-text-versus-regex cases from
  every desktop search surface.

## Related articles

- [Tab management and discovery](tab-management.md)
- [In-app changelog viewer](../experience/changelog-viewer.md)
- [Runtime appearance and element editor](../appearance/runtime-appearance.md)
