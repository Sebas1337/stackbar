# Stackbar

Declutter your Mac's menu bar. Stackbar adds a single icon that opens a dropdown with the
status icons you don't want in the bar, including the ones that would otherwise be lost behind
the notch.

Status: early development (0.1.0: menu bar icon only). Requires macOS 26. See [docs/PLAN.md](docs/PLAN.md).

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
