# Spoken narrator

## Behavior

The narrator optionally speaks application events aloud. It is **off by
default** and is enabled only by the user, from **Settings → Spoken narrator**.
Until it is enabled nothing is synthesized, no audio device is opened, and no
text leaves the machine.

It narrates whatever reaches the notification centre, so it covers the same
events the user already sees without a second event bus to keep in sync. A
notification's severity becomes the narration category, which is what drives the
per-category cooldown.

## Voices

Speech is synthesized by Microsoft Edge's online neural voices through the
`edge-tts` Python package, which is what gives the Cantonese track a real Hong
Kong voice — `zh-HK-HiuMaanNeural`, `zh-HK-HiuGaaiNeural` or
`zh-HK-WanLungNeural` — rather than a robotic one or a Mandarin voice reading
Cantonese copy. Five English voices (US, UK, AU) are offered for the English
track. Each track has its own **Preview** button so a voice can be heard before
it is committed.

**Speak in** selects English, Cantonese, or Both. Both speaks English first and
Cantonese second, strictly serialized — never together.

## Privacy

While the narrator is enabled, **the text it speaks is sent to Microsoft's
speech service** in order to synthesize it. This is stated in the settings
surface itself, next to the switch, because enabling a voice is not consent to a
network round trip nobody mentioned. Nothing is sent while the narrator is off,
and no torrent contents, file names beyond what a notification already shows, or
credentials are involved.

## One utterance at a time

Narration runs through a strictly serialized queue with a single player:

- Never overlapping. A new line waits for the current one to finish.
- A queued line that a newer line of the **same category and voice** supersedes
  is **replaced**, not stacked, so a burst of torrent completions does not become
  a backlog the user waits out.
- A per-category cooldown (15 s) plus a global debounce (1.2 s) keeps narration
  infrequent.
- Lines are truncated to 300 characters: narration is a notification, not a
  document reader.
- Synthesis is bounded by a 20 s timeout, so a hung network request cannot wedge
  the queue.

**Errors are exempt from the rate limits.** A failure the user needs to act on is
exactly the line that must not be dropped for arriving too soon after another,
so an error preempts the queue instead of waiting behind routine chatter.

## Yielding

The narrator stays silent while a screen reader is running (detected through
`SPI_GETSCREENREADER`): the reader is already speaking the interface, and talking
over it leaves both unintelligible. A **Quiet** switch suppresses narration
without discarding the user's other settings.

## Requirements and failure modes

Narration needs Python (already required for search plugins) plus the `edge-tts`
package, and a network connection at the moment of synthesis. Each failure is
reported in the settings surface rather than failing silently:

- Python not found.
- Synthesis failed or the speech service did not respond — the interpreter's own
  error output is included when there is any.
- A temporary directory for the audio could not be created.

Install the package with:

```bash
python -m pip install --user edge-tts
```

## Verification

Repository policy checks require the narrator to default to off, to offer
English/Cantonese/Both with a Hong Kong Cantonese voice, to be serialized with
supersession and both rate limits, to exempt errors from those limits, to yield
to a screen reader, and for the settings surface to disclose the online
synthesis.

## Related articles

- [Searchable context actions](context-menu-search.md)
- [Windows Desktop Features](../README.md)
