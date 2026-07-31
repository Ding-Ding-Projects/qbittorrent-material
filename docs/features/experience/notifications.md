# Notification Center

## Behavior

Informational, success, progress, warning, and error messages are routed through
one severity-aware notification model. The bottom-right Snackbar host stacks up
to five cards without blocking the current task. Information auto-dismisses
after 5 seconds, success after 4 seconds, and progress after 6.5 seconds.
Warnings and errors remain visible until dismissed.

Every message is also retained in the searchable notification center, including
messages already dismissed from the corner stack. Entries carry a title, body,
severity, timestamp, read/dismissed state, and an optional action. The center
shows an unread badge, supports marking messages read, invokes available
actions, and can clear its history.

## Configuration

The notification center is opened from the header bell. History is stored in
application preferences and is capped at 200 entries. Titles are bounded to 160
characters and bodies to 4,096 characters before persistence.

Native tray notifications remain separately controlled by the existing desktop
notification preference. Turning off native balloons does not remove the
in-app history.

## Failure modes

- If persisted history is invalid JSON, the controller starts with an empty
  model instead of preventing startup.
- When more than five cards arrive, the corner host removes the oldest visible
  card while the history model keeps the entry.
- An unavailable optional action leaves the notification reviewable; it does
  not turn the message into a blocking dialog.
- Preference-write failure is logged but does not prevent the user action that
  raised the notification.

## Security and privacy

Notification history is local application data. Call sites must not put
credentials, access tokens, private tracker URLs, or other secrets in titles or
bodies. The history limit bounds storage growth, but it is not a redaction
mechanism.

## Verification

- `scripts/test-desktop-policy.ps1` requires the notification controller,
  Snackbar host, and notification center, and rejects legacy static
  `Snackbar.show` calls.
- Acceptance should raise one message of each severity, verify stacking and
  timeouts, restart the app to confirm history persistence, invoke an action,
  and clear the history.
- Keyboard and screen-reader checks should cover the bell, cards, actions,
  dismiss controls, unread state, and history search.

## Related articles

- [Language modes and funny levels](language-and-funny-levels.md)
- [Local version history](../workspace/local-version-history.md)
- [Runtime appearance and element editor](../appearance/runtime-appearance.md)
