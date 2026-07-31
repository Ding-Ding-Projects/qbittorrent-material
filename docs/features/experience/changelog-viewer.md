# In-App Changelog Viewer

## Behavior

The About surface includes an offline changelog tab. Its bundled catalog
contains the 34 existing releases, including explicit “no detailed changes
recorded” entries where no factual changelog was available.

Search and date range are one composed filter. Text search is plain text by
default and can opt into Qt `QRegularExpression` (PCRE2). Flags are validated
against `g`, `i`, `m`, `s`, and `u`; Unicode properties remain enabled. The
query is bounded to 4,096 characters and evaluated with explicit PCRE2 match
and depth limits. Search includes the factual English catalog and its bundled
Cantonese translation.

The date range accepts typed ISO `YYYY-MM-DD` values and the current locale's
short date format. Calendar controls support month and year selection, separate
start/end endpoints, and presets for the last year and current month. The
filtered selection can be copied or exported to Markdown in the active language
and funny level. The exported file states the actual earliest/latest release
dates and number of entries represented.

## Configuration

Open **About** and select **Changelog**. Enter either or both dates, use the
calendar buttons, and type a search query. The adjacent regex affordance opens
the same full builder used by desktop search fields. Copy and export operate on
the current combined result, not the unfiltered catalog.

## Failure modes

- Invalid or partial dates remain in their fields and produce an inline error.
- A start date after the end date is rejected without discarding either value.
- Invalid regular expressions produce syntax feedback and no misleading
  matches.
- An unwritable export destination produces a non-blocking error notification.
- Missing historical detail is stated explicitly; the viewer never fabricates
  a change to fill a gap.

## Security and privacy

Release history and filtering are local. Queries, dates, and generated Markdown
are not uploaded. Export occurs only after the user chooses a local destination.
Both the changelog controller and shared builder enforce bounded Qt/PCRE2
validation and match/depth safeguards.

## Verification

- `scripts/test-desktop-policy.ps1` validates the catalog JSON, checks at least
  34 uniquely versioned entries, and requires a date, title, and non-empty
  change list for every entry.
- The integrated Windows build passed, and the real capture path rendered the
  changelog surface after runtime integration fixes.
- Acceptance should combine a date preset with plain text, repeat with regex,
  exercise invalid and partial dates, verify the honest empty state, and compare
  copied/exported output with the visible filtered list.
- New releases must add factual catalog entries in a later app build; the
  current build does not query GitHub at runtime.

## Related articles

- [Search and regex builder](../workspace/search-and-regex.md)
- [Immutable Windows releases](../delivery/windows-releases.md)
- [Language modes and funny levels](language-and-funny-levels.md)
