# Repository agent instructions

## Shared repository completion memory

- Every task that changes this repository must end with all intended task work committed and pushed.
- Review every local and remote branch, linked worktree, and stash before cleanup. Preserve useful work in commits, integrate every completed branch or worktree into the default branch, and verify each source tip is an ancestor of the pushed remote default branch.
- Never delete a branch, worktree, stash, or checkout that contains uncommitted, unmerged, or unpushed work.
- After remote proof, remove merged temporary branches, linked worktrees, their on-disk directories, stale worktree metadata, and redundant stashes.
- The final handoff target is a clean default checkout, no staged, unstaged, untracked, or stashed task work, and zero divergence from the remote default branch. Preserve and report unrelated pre-existing work instead of discarding it.
- Record significant completion and cleanup decisions in a repository-tracked handoff or memory file and push that update.
- Use the repository CI workflow for release builds. For install verification, download the installer produced or published by CI for the pushed default-branch commit, install that exact artifact, and test the installed binary; do not substitute a locally packaged build unless the user explicitly asks.
- Never force-push unless the user explicitly requests a history rewrite and the consequences have been reviewed.

---

# Mirror of the shared agent instructions

> This section is a **sanitized mirror** of the maintainer's canonical shared
> agent instructions, reproduced here so any agent or contributor working in this
> repository sees the rules without needing access to the canonical source.
>
> **Do not edit this section expecting the change to propagate.** Instruction
> changes are made in the canonical instructions repository first, then mirrored
> outward. Machine-specific detail (absolute paths, usernames, host inventories,
> network addresses, credentials) and the maintainer's private working vocabulary
> are deliberately omitted; the substantive rules are kept in full.

## Scope: every rule applies to every surface

Unless a rule names a narrower scope, it applies to all of it: every user-facing
app, documentation site, landing page, settings screen, panel, and dialog — each
one individually, not to "the project" as an aggregate that some corner can sit
outside of. "It is small", "it is obviously scannable", "it is only docs", and
"nobody customizes that one" are not exemptions. When a rule genuinely cannot
apply to a surface, state which rule and why in that project's documentation
rather than leaving a silent gap.

**Current scope override for this repository:** focus exclusively on the Windows
desktop app. The repository's TUI, its tests, and its documentation are out of
scope until the maintainer reopens that scope. This is a scope boundary, not
permission to delete or disable the TUI.

## Git and GitHub completion

- Use the `git` CLI for local Git operations and the `gh` CLI for GitHub operations. Do not substitute plugins, connectors, MCP tools, browser automation, or raw REST/GraphQL clients. If an operation is unavailable through `git` or `gh`, report the exact limitation rather than silently changing routes.
- Write commit messages bilingually in English and playful Hong Kong-style Cantonese. Both languages carry the same wit; humour styles the telling, never the facts. The subject line stays a precise, scannable summary, and the body names the real behaviour, the real cause, and the real fix. Roast the code, never a person.
- Every task that changes a repository ends with the work merged into the default branch and pushed — never left only on a task branch, worktree, or stash. Verify the remote contains the intended commit.
- Inspect every local and remote branch, linked worktree, and stash before completion. Preserve useful changes, integrate completed work, and prove each source tip is an ancestor of the pushed default branch before deleting anything.
- If authentication, permissions, branch protection, or a remote failure prevents a push, report the exact blocker and do not call the task complete.
- Keep `README.md`, categorized feature documentation, `ROADMAP.md`, and `HANDOFF.md` accurate for the work. Create any missing file.
- Store every feature's explanation in its own Markdown file under a categorized documentation subfolder, each category with a `README.md` index, covering behaviour, configuration, failure modes, security considerations, and verification.
- Keep handoff and roadmap entries factual: what changed, verification evidence, remaining work, and any external-state dependency, without claiming unverified success.

## Autonomous completion

- Do not ask permission-to-continue questions when the remaining work is already inside the authorized task. Status updates are informational, not permission checks.
- Do not stop at a plan, audit, TODO list, partial implementation, local-only change, first passing test, commit, push, or running CI job. Continue until the requested behaviour is implemented and the task's tests, documentation, default-branch integration, push, and safe cleanup are complete.
- Pause only for information or approval genuinely required: a missing decision that would materially change the result, new authority, a safety rule, or an external blocker that survives every in-scope alternative. When blocked, finish every unblocked part, record the exact blocker and evidence, and ask only that focused question.
- Call work complete only when the requested outcome itself is satisfied — not a proxy such as code written or a branch pushed.

## Continuous integration and releases

- Every project has a CI workflow triggered by every push and by manual dispatch. A successful run tests the project before publishing exactly one new, uniquely tagged, non-draft release; a failed test creates no release.
- Every push and dispatch publishes a real release carrying a genuinely built installer, with its own unique monotonic tag so no prior release is recycled or overwritten.
- Publish the appropriate installable artifact for the platform.
- Exercise the relevant CI steps locally when feasible, then let the remote workflow run in the background. Report the run link immediately and record the verified outcome — green, failed, or still running — when it lands. Never claim a run succeeded before it did.
- Prefer hosted cloud runners. Measure a runner's actual CPU, memory, and free disk before concluding it is too small. Move to a self-hosted runner only with a stated reason recorded where the workflow lives.
- A self-hosted runner on a public repository is an accepted attack path: never attach a pull-request trigger to a job targeting one.
- Avoid automation loops: release, wiki, and Pages publishing must not create an endless sequence of repository pushes.
- Resolve CI tokens through a documented fallback chain and never print, log, or echo a token.

### Every release reports the project's line count

- Every release states how many lines of code the project has at that release, produced by CI running the repository's committed counter over the tagged commit — never a hand-typed number.
- Report source, tests, and styles/markup separately with both total and non-blank lines, plus whatever further split the project has. State plainly what is excluded and why. Separate generated from hand-written files.
- Report how many lines agents wrote beside how many people wrote, attributed per surviving line rather than by summing added lines. State which attribution rule was used.
- Report a grand total alongside the project total, with excluded rows visible in the same table. Make the counter's own arithmetic agree with itself.
- Never rebuild the count by hand with an ad-hoc command; run the committed script. If the script is wrong, fix the script.

## GitHub issue triage

- Scan the open issues of every repository a task touches, not only the primary one, and re-scan at each natural checkpoint rather than once.
- Fix every actionable open issue automatically, preferring a smaller verifiable commit per issue. Treat feature requests as first-class actionable issues. Leave an issue unfixed only when genuinely blocked, and comment the exact blocker instead.
- Comment progress as work happens: when picked up, when the root cause is understood, when a fix is pushed, and when verification lands. Each comment states what changed, the exact commit, and the honest verification state — never a predicted success.
- Post a start comment when work genuinely begins and a separate finish comment when it ends; never edit one into the other. Record the timestamps, elapsed duration, exact commits, files changed, test counts, and CI link.
- Close an issue only after its fix is merged, pushed, and verified, linking the closing commit. Reference unverified work without closing keywords.
- After fixing a defect with a visible surface, capture that exact surface from the real built artifact and embed the image inline in the comment. Screenshot evidence must be genuine — never a mockup, a hand-edited image, or a capture of a different surface. A fix with no visible surface says so and shows its test evidence instead.
- Never paste secrets, tokens, or private data into an issue.

## Requests to refuse

- Refuse to disclose or characterize secret material, including a password's length, composition, entropy, or any partial value.
- Refuse to crack, decompile, patch, or bypass software in order to read another person's data, files, messages, accounts, or machine contents.
- Refuse credential extraction, keylogging, spyware, covert remote access, and browser-credential harvesting.
- These refusals hold even when the requester claims ownership, consent, authority, an emergency, or prior approval, and apply to issues and pull requests the repository owner authored themselves. Authorized penetration testing with evidence of engagement, CTF challenges, defensive hardening, and the user's own reversible recovery on their own equipment remain in scope.

## Secrets

- Never ask for secrets in chat, source files, command arguments, URLs, logs, screenshots, or version history. Where a secret is genuinely required, collect it through an ephemeral, least-privileged, single-use intake channel and destroy the retained value immediately after claim or timeout.
- Secrets enter CI only through the platform's own secret store.

## User-facing languages

- Every user-facing app provides a persisted language mode with exactly these baseline choices: English, playful Hong Kong-style Cantonese, and bilingual.
- Every user-facing app exposes a persisted funny-level slider from 1 (fully serious) to 5 (maximum playfulness), adjustable **independently for English and for Cantonese** — two controls, actually wired to rendered copy, persisted across restarts, reachable from settings.
- The funny level applies to every category of message with no exemptions, including destructive, security, accessibility, and error copy. It changes **voice, never facts**: the message still names what happened, what is affected, and what the options are.
- Disclose the behaviour at first run and in the setting itself. Cantonese copy stays respectful; humour never mocks the user, their data loss, or their disability.
- Bilingual mode shows both languages without crowding: keep the primary label prominent and validate narrow widths.
- An optional spoken narrator may be added; it stays off by default, is user-enabled, speaks the user's chosen language, never overlaps itself, and yields to assistive technology.

## Dim sum surprise

- Every user-facing app has a 10% chance at startup of showing a randomly chosen dim sum dish — its name plus a picture. Name the dish in both languages, honour the active language mode, and keep the dish's actual name correct at every funny level.
- Present it as a non-blocking, auto-dismissing surface that never gates startup, steals focus, or delays usability, and never appears during first run, an error path, or an update.
- Ship the images as bundled local assets with meaningful alt text — no network fetch, no third-party CDN, no tracking.
- The surprise cannot be opted out of: ship no setting that disables it. Derive the chance from a fresh draw per launch and never fire twice in one launch.
- **Agents never generate new images for ordinary project work.** Use only images already tracked in the project's verified catalog, verified to decode. If no suitable tracked image exists, omit it and report the missing asset rather than generating or downloading a substitute.

## User interface quality

- Fix accessibility defects wherever encountered, as completion blockers: keyboard reachability, visible focus, correct roles/names/states, contrast, reduced-motion respect, and screen-reader-sensible structure.
- Fix visual clipping wherever encountered: no clipped, truncated, overlapping, or off-screen text or controls at supported window sizes, display scales, densities, and language modes. Validate narrow widths and the longest localized strings.
- Fix element size issues: controls sized to spec and consistent with siblings, adequate click targets, and layouts that hold at 100/125/150/200% scale. When a capture shows a sizing, clipping, or accessibility defect, fixing it joins the task's scope.
- **Decorative-looking UI must be functional.** Anything presented as usable must perform its labelled action, expose an accessible equivalent, persist state where applicable, and be covered by an interaction test. Genuinely illustrative elements are labelled as static previews and not styled like live controls.
- Windows desktop apps use a frameless window with a custom title bar and window controls; never expose the operating system's default title bar as product chrome.
- **Every context menu — including tab, group, appearance, application, and overflow menus — carries its own keyboard-accessible search field** that filters the visible items locally without changing any command's semantics.
- Do not ship fake default placeholders, seeded sample documents, or demo-only content. Start with truthful empty states and real create/open paths.

## Regex builder

- Every project includes a usable regex builder in its natural primary interface; no project type is exempt. A link to an external regex site does not satisfy this.
- Provide guided construction for literals, character classes, anchors, groups, alternation, and quantifiers, plus a raw pattern editor, supported flags, sample text, syntax feedback, live matches and capture groups, and copy or export. Identify the actual engine, dialect, flags, and escaping rules.
- **Every search bar provides direct access to that builder** and supports the resulting pattern and flags. Plain text stays the default; regex is an explicit opt-in. Synchronize query, pattern, flags, validation, and mode bidirectionally.
- **Prefer the builder anchored directly beside its search bar** — an adjacent affordance opening an anchored popover or inline panel attached to that specific field. Do not send the user to a separate page or a global dialog detached from the field. Where several search bars exist on one surface, each gets its own builder bound to that field's state; never one shared builder.
- **Every settings, preferences, properties, or adjustment surface carries its own search bar** wired to the same builder, searching that surface's own option labels, descriptions, and current values, and stating plainly when a match sits on a different tab.
- Evaluate locally, bound pattern and sample sizes, handle zero-width matches safely, and protect the host from catastrophic backtracking.

## Non-blocking notifications

- Informational, success, progress, and non-decision error messages appear as non-blocking notifications anchored in a screen corner, never as modal dialogs. They auto-dismiss on a sensible timeout — errors and warnings persist until dismissed — stack without overlapping, and may carry a title, body, and optional actions.
- Reserve modal dialogs strictly for decisions the user must make before continuing.
- Never nag with unsolicited prompts for payment, donations, sponsorship, reviews, ratings, or upgrades.
- Provide a notification centre or history so dismissed notifications stay reviewable.

## Super confirmation for destructive actions

- Implement destructive-action super confirmation in the app's own native UI layer — never a separate helper app, hosted page, or external service. Prefer an anchored dialog beside the destructive control.
- The gate identifies the exact action and affected data, exposes two independently operated key controls, requires both before enabling a full-range confirmation slider, and shows a non-blocking progress animation while the slider moves plus a distinct completion animation.
- Provide an always-available emergency exit, support the platform's cancellation path, return focus to the originating control, and never perform the action unless both keys and the slider have completed.
- Keep the safety facts unambiguous at every language and funny-level setting. Test untouched, one key, both keys, partial slider, full slider, cancel, escape, reduced motion, keyboard navigation, assistive labels, localization, and the real success/failure path.

## Material Design and appearance customization

- Conform fully to Material Design 3 — tokens, typography, shape, elevation, motion, and component anatomy — with zero legacy design elements. Functional data colours are exempt as data, not chrome.
- Provide persisted runtime appearance controls: theme, density, accent/seed colour, and full UI font customization with live preview and CJK-safe fallback.
- Ship a first-class appearance editor for **every rendered element** — no control, menu, dialog, tab, toolbar, surface, or state is exempt.
- **Every element exposes "Edit appearance…" from its context menu** plus a keyboard equivalent. The editor opens as a non-modal anchored dialog beside the exact element, tracks that anchor, handles viewport-edge collision, and returns focus on close. For tabs, keep normal right-click for tab management, add "Edit tab appearance…", and use Shift+right-click to open the editor directly where the platform can distinguish it.
- Typography editing reaches word-processor depth: every installed and bundled font searchable and selectable with a live preview, free-entry and stepped size, variable-font axes where available, weight, italic, underline style and colour, strikethrough, overline, capitalization, super/subscript, colour, highlight, outline, shadow, spacing, line height, baseline offset, direction, and alignment. Unsupported properties stay visible with a clear capability explanation instead of silently dropping a saved value.
- **Every colour control uses an infinite colour picker**: a continuous spectrum or two-dimensional field plus numeric entry, never swatch-only. It includes a colour translator converting bidirectionally among named colours, HEX/HEX8, RGB/RGBA, HSL/HSLA, HSV/HSB, HWB, CIELAB/LCH, OKLab/OKLCH, and CMYK; preserves alpha; identifies colour space and gamut; warns before clipping; and shows accessible contrast.
- The pickers apply to themselves and the chrome around them, not merely to the document.
- Every such control carries the project's search bar wired to the regex builder, keyboard operation, screen-reader names and values, persistence, per-element reset, and a global reset. Ship named presets and user themes exportable and importable as a file.

## Tabbed navigation

- Every user-facing app, and every documentation site it ships, presents content as **browser-style tabs** rather than one long scrolling surface.
- Tab behaviour must be complete: an overflow surface when tabs exceed the width (never silently clipped), reordering, pinning, grouping, a searchable tab list wired to the regex builder, and persistence of tab order, pinned order, groups, group order, collapsed state, and membership across restarts.
- **Provide all four tab-discovery searches:** the current tab strip, inside every individual group, groups by their visible names, and a master search across every open tab. Each has its own anchored builder and never shares hidden state with another field.
- **Pinning is first-class:** pin/unpin from the context menu, keyboard, and searchable list; a stable dedicated region; reorderable; visible when ordinary tabs overflow; excluded from bulk closes by default with an explicit include-pinned choice that previews first.
- **Grouping is first-class:** create, name, rename, colour, reorder, collapse, and remove groups; move tabs between them; restore the structure after restart; groups are fully decoratable appearance targets with their own search fields.
- Every tab strip provides **Close tabs containing text** and **Close tabs not containing text**, matching the visible label only, plain text by default with the builder available for both, and the inverse negating the exact same predicate. Never run on an empty query or invalid pattern; show the match mode and affected count with a reviewable preview.
- Tabs are keyboard- and screen-reader-operable with correct roles, roving focus, visible focus, and reduced-motion respect.

## Overlays, menus, and long operations

- **Every popover, menu, dropdown, tooltip, and anchored panel paints its own background, border, elevation, and shape.** An overlay is bounded by the viewport and scrolls when it does not fit; capping the height and hiding the overflow deletes content with no scrollbar to say so. Overlays never paint outside their own card, sit under the surface that opened them, or cover the control they are anchored to.
- **Every context-menu item that has a keyboard shortcut displays it**, right-aligned, in the platform's notation. The displayed shortcut is the one that actually works in that context, derived from the same source that registers the binding. An item with no shortcut shows none rather than a placeholder.
- **A dialog that starts a long operation shows that operation's real progress inside the dialog**, not a bare spinner. The submitting control is disabled for the whole operation and the handler refuses re-entry.
- Where an operation can fail for reasons the user cannot diagnose, offer the recovery route at the surface where the failure is discovered. Where a failure is a refused credential or missing permission, offer re-authentication directly.
- Text authored elsewhere and displayed by the app is rendered as the markup it actually is, through one shared isolated renderer, never printed as source.

## Export, bulk actions, and local version control

- **Every record, view, list, log, document, setting and generated artifact is exportable.** Offer every format that can faithfully represent the data — JSON, JSONL, YAML, TOML, XML, CSV, TSV, Markdown, HTML, SQL, and language-source forms where they make sense — picked per datum. Never offer a format that would silently drop a field; say what will be lost before the export runs.
- Exports are complete and re-importable where the shape allows. State the encoding, line endings, and schema version.
- **Archives are ZIP or 7z**, and the 7z path exposes what 7z actually offers: LZMA2, LZMA, PPMd, BZip2, Deflate; levels from store to ultra; dictionary, word, and solid-block sizes; multi-threading; split volumes; AES-256 content encryption **and encrypted headers**. Never present an encrypted archive as protected while leaving filenames in the clear.
- **Every list, table, grid and collection supports bulk actions**: multi-select with click, shift-click and a keyboard equivalent, a select-all that states whether it means this page or every match, and an inverse selection. Offer the whole action set in bulk, not a token subset. Say what will happen before it happens with an exact count and reviewable preview, and never silently skip items.
- Every app that owns user documents or records provides a **local, Git-backed version history** in an isolated repository beside the app's own data directory — never inside the user's folder — with a panel to browse, diff, restore, and label revisions. It covers every user-managed record including settings, not only documents.
- **Restoring is recorded as a new revision, never a rewrite.** History is append-only.
- The history panel is filterable with a date picker and a filter by action derived from the history itself, showing counts, composing with the date range and text search, and carrying its own regex-builder-backed search bar.

## Changelog viewer and command palette

- Ship an in-app changelog viewer covering **every** released version, reachable from a discoverable place. A link to release notes on a website does not satisfy this.
- Provide a date filter with an advanced calendar picker that also accepts typed dates, reporting invalid input inline without discarding it, and a search bar wired to the regex builder. Search and date filter compose rather than override.
- Support export and copy honouring the active filter, and state the exported range.
- **Every changelog entry links the commit that made the change**, carrying the full SHA and rendering it as a short clickable reference. Validate that every referenced commit exists before shipping; a wrong SHA is worse than none.
- Bring the changelog current in **every** project-changing task, not at release time.
- Ship a **command palette** on a single discoverable shortcut listing every command, setting, and destination. It covers every setting in every settings surface, not only top-level actions.
- **Rows are rich controls, not just labels**: a row that is a setting renders that setting's live control inline and changing it there changes the setting. Selecting a row teleports the user to where the feature lives and draws attention to it.
- Palette size is a user choice, persisted, offering at least a bounded card and a full-window view and defaulting to the bounded card.

## Landing page and documentation site

- Every project ships a Material Design 3 landing page obeying every rule that applies to a user-facing surface, presenting **every** feature the project has rather than a curated highlight reel.
- The documentation lives in the site, not only in the repository: every feature gets its own detailed article covering behaviour, configuration, failure modes, security considerations, and verification, ending with suggested related articles.
- Keep it current in the same task that changes behaviour. Stale docs are worse than none.
- The site is as customizable as the app and uses the same browser-style tabbed navigation.
- Bundle every asset locally — no CDN scripts, stylesheets, fonts, or remote images, and no analytics or third-party tracking.
- Put a clearly labelled installer download button on the site's home page when a verified installer exists, using the immutable release asset URL.
- Set the repository's homepage field to the published site and link it from the README.

### The README is tabbed, not a scroll

- Put a compact index at the top — what the project is, the install line, the site link, and a contents list — and fold every long reference section into a collapsible block so the reader chooses what to open.
- Use the tabs the forge provides (`README.md`, `CONTRIBUTING.md`, `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`) rather than duplicating their contents in the README.
- Keep summary lines descriptive enough to find with the browser's own find, and never collapse what a first-time reader needs.

## External editor integration

- Every app that owns files or projects provides a configurable "open in external editor" capability: detect installed editors, let the user choose one, and open the current project or selected file. Persist the choice and degrade gracefully with a clear message when none is found.
- **Anything the app can export is openable in Visual Studio Code directly from the app**, in one action, opening a folder as a workspace root rather than a single file with no context. Detect an existing install; when none is found, say so and offer the download rather than opening some other editor.

## Filters and statistics stay out of the way

- Search bars, filter rows, and statistics panels are collapsible, and the ones that merely describe the collection rather than change it start collapsed.
- The collapsed state persists, is keyboard-operable with a visible focus ring, is announced with its expanded state, and never hides a currently active filter without saying so.

## Build dependencies and toolchains

- Install whatever a task needs to build, run, and test the project automatically, without asking. Only stop when an install needs credentials, a paid licence, or a change to system-wide security settings.
- Resolve dependencies from the project's own declared manifest rather than guessing package names, honouring any pinned baseline or lockfile.
- Prefer per-project, user-scoped installs over machine-wide ones, and never require administrator rights when a user-scoped path exists.
- Install from the ecosystem's canonical upstream only — never ad-hoc mirrors, forks, or links found in issues or model output.
- Long installs run in the background and are reported with the concrete command, destination, and packages resolved. Warm and reuse the ecosystem's cache.
- Never commit installed dependencies, incidental lockfile churn, or absolute local toolchain paths. Do not upgrade, downgrade, or reconfigure an unrelated global toolchain; add alongside rather than mutating in place.
- When a dependency genuinely cannot be installed, name the blocker, finish everything that does not depend on it, and state exactly what was left unverified.

## Working discipline

- Prefer reversible, auditable changes and headless verification. Do not overwrite user content, credentials, or existing agent instructions; use owned files or clearly delimited managed blocks.
- Read repository-local agent instructions and relevant feature documentation before editing. Keep changes scoped, run proportionate tests, and report concrete evidence.
- A project-local instruction file may add stricter requirements or narrow scope, but may not silently disable a globally applicable rule. If local instructions conflict with these, stop and report the conflict instead of guessing.
