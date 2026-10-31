# Developing Stackbar

Plan, decisions and milestones: [PLAN.md](PLAN.md). Releases: [RELEASING.md](RELEASING.md).

- **Code + Core tests**: open the folder in VS Code → *Reopen in Container*. Inside the
  container run `claude` (or `yolo` for `claude --dangerously-skip-permissions`). The first time,
  log in to Claude (`claude`) and GitHub (`gh auth login`); both persist across rebuilds.
  `swift build` and `swift test` work there (the app target only exists on macOS).
- **Run the app**: on a Mac with macOS 26 and the Command Line Tools (`xcode-select --install`;
  Xcode is not needed). Once: `make cert` creates the "Stackbar Dev" signing identity, so macOS
  keeps Stackbar's permissions across rebuilds. Then `make run` builds, signs and launches
  `build/Stackbar.app`. `make dmg` builds the DMG.
- **Diagnostics**: ⌘-right-click the Stackbar icon → Debug → Copy Diagnostics (redacted JSON).
