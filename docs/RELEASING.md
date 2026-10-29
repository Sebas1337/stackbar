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
   `Stackbar.app`, and publishes a GitHub Release with `Stackbar-X.Y.Z.zip` (+ SHA-256) and the
   changelog section as notes. Check it with `gh run watch` / `gh release view vX.Y.Z`.

A tag whose version has no changelog section, or doesn't match `VERSION`, fails the workflow
before anything is published. To redo a failed release: fix on `main`, delete the tag
(`git push origin :vX.Y.Z && git tag -d vX.Y.Z`) and tag again. Never move a tag that already
has a published release; release a new patch version instead.

## Signing

Until M5, release builds are signed ad-hoc only (CI has no signing identity). Consequences:

- **Gatekeeper blocks the first launch** of a downloaded build. Since macOS 15, right-click →
  Open no longer bypasses it: open the app once, then System Settings → Privacy & Security →
  "Open Anyway". Or remove the quarantine flag: `xattr -dr com.apple.quarantine Stackbar.app`.
- **Permissions reset on every update**: an ad-hoc signature changes with every build, so macOS
  asks for Accessibility and Screen Recording again after each release.

Local builds (`make app`) avoid the second point by signing with the self-signed "Stackbar Dev"
identity (`make cert`). At M5 we choose between Developer ID signing + notarization (paid Apple
Developer account, secrets in GitHub Actions, DMG) and a stable self-signed release certificate;
see the Distribution decision in [PLAN.md](PLAN.md).
