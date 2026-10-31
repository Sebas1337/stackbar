# Versions & releases

## Scheme

- [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`, tags `vX.Y.Z`.
- **Source of truth: the `VERSION` file.** `scripts/build-app.sh` writes it into `Info.plist`
  as `CFBundleShortVersionString`; `CFBundleVersion` (build number) is
  `git rev-list --count HEAD`, so it always increases.
- Pre-1.0, one minor version per milestone: M0 → `0.1.0`, M1 → `0.2.0`, M2 → `0.3.0`, M3 → `0.4.0`,
  M3b → `0.5.0`, M4 → `0.6.0`, M5 → `1.0.0`.
  Fixes in between bump the patch version.
- Pre-releases use a suffix (`0.3.0-beta.1`) and are marked as pre-release on GitHub.
- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Every PR
  with a user-visible change adds a line under `## [Unreleased]`.

## Cutting a release

1. On a branch (`release-X.Y.Z`): set `VERSION` to `X.Y.Z`, rename `## [Unreleased]` in
   `CHANGELOG.md` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]` above it.
2. PR into `main`, wait for CI, merge.
3. Tag the merge commit and push the tag:
   ```sh
   git checkout main && git pull
   git tag -a vX.Y.Z -m "Stackbar X.Y.Z"
   git push origin vX.Y.Z
   ```
4. `.github/workflows/release.yml` checks the tag matches `VERSION`, runs tests, builds
   `Stackbar.app` signed with the release certificate (see Signing), and publishes a GitHub Release
   with `Stackbar-X.Y.Z.dmg` and `Stackbar-X.Y.Z.zip` (+ SHA-256) and the changelog section as
   notes. Check it with `gh run watch` / `gh release view vX.Y.Z`. Running copies of Stackbar
   find it within a day (Check for Updates… at once).

A tag whose version has no changelog section, or doesn't match `VERSION`, fails the workflow
before anything is published. To redo a failed release: fix on `main`, delete the tag
(`git push origin :vX.Y.Z && git tag -d vX.Y.Z`) and tag again. Never move a tag that already
has a published release; release a new patch version instead.

## Signing

Releases are signed with a self-signed **"Stackbar Release"** certificate (decided 2026-10-30;
no Apple Developer account, no notarization). Because every release carries the same
certificate, macOS keeps Stackbar's Accessibility and Screen Recording permissions across
updates, and the in-app updater installs only releases signed with it (it checks the new app
against the running app's designated requirement).

- **Create it once** on the Mac: `make release-cert` writes `stackbar-release.p12` and its
  password into `~/Stackbar Release Certificate` and prints the next steps. **Back that folder up**:
  without it, the next release is signed differently and every user has to grant the permissions
  again (and the updater refuses it). Never re-create it while releases signed with it exist.
- **GitHub secrets** (repo Settings → Secrets and variables → Actions): `RELEASE_CERT_P12` (the
  `.p12`, base64) and `RELEASE_CERT_PASSWORD`. `release.yml` imports them into a temporary keychain,
  trusts the certificate for code signing and builds with `REQUIRE_IDENTITY=1`, so a release is
  never signed ad-hoc; it fails when the secrets are missing.
- **Assets**: `Stackbar-X.Y.Z.dmg` (install: drag to Applications) and `Stackbar-X.Y.Z.zip` (the
  updater downloads it), each with a `.sha256`. The app inside both is signed; the DMG itself is
  not: Gatekeeper checks a signed disk image when it opens, which with this certificate was a
  second "Open Anyway" before the app's own (rc.1 test, 2026-10-31).

### First launch (Gatekeeper)

The certificate isn't from Apple, so Gatekeeper blocks the **first** launch of a downloaded copy.
Since macOS 15, right-click → Open no longer bypasses it. Documented step (README):

1. Open the DMG, drag Stackbar to Applications, open it from there. macOS says it can't verify
   the app: click **Done**.
2. System Settings → Privacy & Security → "Stackbar was blocked…" → **Open Anyway**, confirm.

Updates installed by Stackbar itself aren't quarantined, so they open without that step. A DMG
downloaded again by hand needs it again.

### Testing an update

The updater offers pre-releases only to pre-releases. To test the update path, tag two
pre-releases (`1.0.0-beta.1`, `1.0.0-beta.2`), install the first from its DMG, grant the
permissions, and let it update to the second (icon menu → Check for Updates…): no permission
prompts may appear.

Local builds (`make app`) are signed with "Stackbar Dev" (`make cert`), so they can't install
releases (different certificate): the updater says so and offers the download page.
