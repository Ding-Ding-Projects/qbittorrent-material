# Immutable Windows Releases

## Behavior

`.github/workflows/release-every-push.yml` runs for every branch push and for
manual `workflow_dispatch`. It uses the GitHub-hosted `windows-2022` image and
records the actual logical processor count, total/free memory, and total/free
system-disk capacity before relying on that runner.

The pipeline then:

1. reserves the monotonic tag `build-<run-number>-<sha8>` and refuses an
   existing tag or release;
2. runs `scripts/test-desktop-policy.ps1`;
3. installs the declared Qt 6.8.3 and vcpkg toolchains;
4. configures and builds the Release target;
5. creates exactly one NSIS installer;
6. silently installs it, launches the installed executable offscreen, validates
   schema 2 Workspace persistence and both crash-recovery windows, checks the
   embedded Git repository, and silently uninstalls it; and
7. creates one full, non-draft, non-prerelease GitHub Release for the triggering
   commit.

The release attaches two real assets: the built Windows installer and the
existing bundled `resources/dim-sum/har-gow.png`. Release notes identify the
image as Shrimp dumpling · 蝦餃 and include the installer SHA-256. The workflow
does not create a disposable Actions artifact.

## Release identity and immutability

`GITHUB_RUN_NUMBER` supplies the increasing numeric component and the short
commit SHA makes the tag auditable. The workflow checks the remote tag before
the build and immediately before publishing. It calls `gh release create` once;
there is no upload-to-existing branch, `--clobber`, recycled tag, or draft
phase. A rerun after a release exists fails safely instead of mutating it.

Release API authentication follows this exact fallback order:

```text
RELEASE_TOKEN || ORG_TOKEN || GITHUB_TOKEN
```

## Failure modes

- A policy-test, configure, compile, package, install, launch, recovery, Git
  integrity, or uninstall failure stops the job before release creation.
- A missing or non-decodable dim-sum image fails the policy test before build.
- More or fewer than one matching installer fails packaging.
- A tag collision fails rather than replacing an earlier build.
- Post-publication verification requires the release to be full and both named
  assets to be present; a mismatch fails the workflow and must be investigated
  without editing the immutable release in place.

## Security considerations

The workflow has `contents: write` and no pull-request trigger. Publishing
credentials are passed only through `GH_TOKEN`; they are not printed or written
to release notes. Dependencies come from the repository manifest plus pinned
major GitHub Actions, and release assets are built or bundled in the checked-out
commit. The release step never downloads an image from a third party.

## Verification

Local checks are:

```powershell
./scripts/test-desktop-policy.ps1
git diff --check
```

The policy script validates 108 desktop and release invariants in the current
tree, including all three decoded PNGs, 34 changelog records, resource globs,
required QML/controller surfaces, localization controls, trigger/token rules,
and immutability guards.

Remote completion requires the exact workflow run to finish successfully and
the resulting release to show the expected tag, target commit, installer, and
`har-gow.png`. A local YAML parse does not substitute for that evidence.

## Related articles

- [Building qBittorrent Material](../../BUILDING.md)
- [Startup dim-sum surprise](../experience/startup-dim-sum.md)
- [In-app changelog viewer](../experience/changelog-viewer.md)
