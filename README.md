# Stackbar

Declutter your Mac's menu bar. Stackbar adds a single icon that opens a dropdown with the
status icons you don't want in the bar, including the ones that would otherwise be lost behind
the notch.

Status: planning. See [docs/PLAN.md](docs/PLAN.md).

## Development

- **Code + Core tests**: open the folder in VS Code → *Reopen in Container*. Inside the
  container run `claude` (or `yolo` for `claude --dangerously-skip-permissions`). The first time,
  log in to Claude (`claude`) and GitHub (`gh auth login`); both persist across rebuilds.
- **Run the app**: on the Mac host (macOS 14+, Command Line Tools), `make run` (available after M0).

## Releases

Downloads are on [GitHub Releases](https://github.com/Sebas1337/stackbar/releases); changes are in
[CHANGELOG.md](CHANGELOG.md). Release process: [docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE)
