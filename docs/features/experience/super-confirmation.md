# Super confirmation for destructive actions

## Behavior

An action that destroys data nothing in the application can bring back is gated
by `SuperConfirmDialog`, built in the app's own QML layer — there is no helper
window, hosted page, or external service anywhere in the flow.

The gate has three stages, and all three are required:

1. **Two independent keys.** Both must be turned. Turning either one back off
   immediately disarms the slider, so a half-armed gate cannot be left sitting
   there.
2. **A full-range slider.** It is disabled until both keys are turned. A slider
   released before the end **springs back to zero** — a partial slide is not a
   decision, and leaving the handle parked near the end would let the next stray
   click finish an irreversible action.
3. **Authorization**, which only happens on a completed slide.

A dramatic but non-blocking progress bar tracks the slide, and a distinct
completion state confirms authorization before the dialog closes.

## Honesty

The dialog names the exact action (`actionText`), exactly what it affects
(`affectedText`), and any additional consequence (`consequenceText`), plus a
fixed "This cannot be undone." line. These are rendered verbatim at every
language mode and funny level: the surrounding copy may be styled, but a user
must never be unsure what the slider is about to do.

## Escape

**Emergency exit** is present the whole time, including mid-slide, and Escape
always closes the gate. Both routes reset every control and emit `cancelled()`
without performing anything. Focus returns to the control that opened the gate
on every exit path — authorized, cancelled, or dismissed.

## Placement

The gate anchors beside the control that opened it when there is room, tries the
opposite side when there is not, and only centres itself when neither side fits.

## Accessibility

Every control is keyboard-operable with a visible focus ring, and each key and
the slider carry a screen-reader name that includes the current state ("First
key, turned"). When `ThemeManager.reducedMotion` is set, the progress and
completion animations are replaced by their end states rather than played, and
the dialog closes immediately instead of holding for the completion animation.

## Where it applies

Erasing downloaded content files — the one path in the transfer list that
destroys data the application cannot recover. Removing a torrent from the
transfer list *without* deleting its files stays a single click, because that is
recoverable: the torrent can be added again.

## Verification

Repository policy checks require two independent keys gating the slider, a
partial slide springing back rather than authorizing, an emergency exit plus the
Escape path plus focus restoration, reduced-motion handling, the exact-action and
affected-data copy, and that the content-deletion path routes through the gate.

## Related articles

- [Windows Desktop Features](../README.md)
