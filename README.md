# Stackbar

Declutter your Mac's menu bar. Stackbar adds a single icon that opens a dropdown with the
status icons you don't want in the bar, including the ones that would otherwise be lost behind
the notch.

Requires macOS 26. Plan and design: [docs/PLAN.md](docs/PLAN.md).

## Install

1. Download `Stackbar-X.Y.Z.dmg` from [GitHub Releases](https://github.com/Sebas1337/stackbar/releases),
   open it and drag Stackbar to Applications.
2. Open Stackbar from Applications. Stackbar isn't signed by Apple, so the first time macOS says
   it can't verify it: click **Done**, then System Settings → Privacy & Security → **Open Anyway**
   (only once; updates installed by Stackbar itself skip this).
3. Setup asks for **Accessibility** (to see which app owns each item and to move items) and
   **Screen Recording** (to show the items' images in the dropdown).

Stackbar checks for updates once a day (Settings → General) and installs them when you agree;
the permissions stay granted.

## Development

- **Code + Core tests**: open the folder in VS Code → *Reopen in Container*. Inside the
  container run `claude` (or `yolo` for `claude --dangerously-skip-permissions`). The first time,
  log in to Claude (`claude`) and GitHub (`gh auth login`); both persist across rebuilds.
- **Run the app**: on the Mac host (macOS 26, Command Line Tools: `xcode-select --install`; Xcode
  is not needed). Once: `make cert` creates the "Stackbar Dev" signing identity, so macOS keeps
  Stackbar's permissions across rebuilds. Then `make run` builds, signs and launches
  `build/Stackbar.app`.

## Releases

Downloads are on [GitHub Releases](https://github.com/Sebas1337/stackbar/releases); changes are in
[CHANGELOG.md](CHANGELOG.md). Release process: [docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE)
