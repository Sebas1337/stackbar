# Agent task: why doesn't Accessibility stick for the signed release build? (M5)

You run on the user's Mac (macOS 26, `uname` = Darwin) in the Stackbar repository. Read
`CLAUDE.md` and `docs/RELEASING.md` → Signing first. Talk to the user in **Dutch**; they are at the
Mac and do the clicks you can't (Gatekeeper, System Settings toggles, menu items). Keep each
request to the user short and numbered, and wait for their answer before going on.

## Background

M5 signs releases with a self-signed "Stackbar Release" certificate (not Developer ID) so that
permissions survive updates. Test of `1.0.0-beta.1` (GitHub pre-release) in a fresh macOS user:

- In onboarding, *Open System Settings* for Accessibility did **not** add Stackbar to the
  Accessibility list (normally the prompt adds it, switched off).
- Adding `/Applications/Stackbar.app` by hand with **+** and switching it on: onboarding still says
  *Not granted yet* (`AXIsProcessTrusted()` stays false), also after quitting and reopening.
- The app ran from `/Applications` (no App Translocation).

Suspicion: the release certificate is not trusted anywhere on that account (the developer's
"Stackbar Dev" certificate is trusted in the login keychain by `make cert`, and there everything
works), and TCC doesn't accept the app's identity. Not proven yet. **Your job is to find out, with
evidence, in this (the developer's own) account**, and then, if Accessibility works, finish the
update test.

## Rules

- Don't change code, don't commit, push or tag. Never print `.env` or any token.
- Don't delete user data: move things aside (`.bak`). Ask before removing an app bundle.
- Write everything you find to `build/m5-accessibility-report.md` (gitignored; the dev session
  reads it from there): every command, its **full** output, what the user saw, timestamps.
  Append as you go, so a crash doesn't lose results.
- The dev build `build/Stackbar.app` has the same bundle id. Make sure it isn't running during the
  test (`pgrep -fl Stackbar`).

## Steps

### 1. Clean state

1. Quit every running Stackbar (`pkill -x Stackbar`, then check `pgrep -fl Stackbar`).
2. Record the current state, then reset:
   ```sh
   tccutil reset Accessibility io.github.sebas1337.stackbar
   tccutil reset ScreenCapture io.github.sebas1337.stackbar
   mv ~/Library/Application\ Support/io.github.sebas1337.stackbar ~/Library/Application\ Support/io.github.sebas1337.stackbar.bak
   ```
   (If the `.bak` already exists, ask the user instead of overwriting it.)
3. Record which code-signing certificates this account trusts:
   `security find-identity -v -p codesigning` and
   `security find-certificate -a -c "Stackbar Release" -Z 2>&1 | head -20`
   ("Stackbar Release" should **not** be in the keychain; if it is, note it: it changes the test.)
4. If `/Applications/Stackbar.app` exists, show `defaults read /Applications/Stackbar.app/Contents/Info CFBundleShortVersionString`
   and ask the user before moving it to the Trash.

### 2. Install 1.0.0-beta.1 like a user would

1. Download the DMG and its checksum from
   `https://github.com/Sebas1337/stackbar/releases/tag/v1.0.0-beta.1` into `build/dl/`
   (`curl -fL -o …`), check `shasum -a 256 -c`.
2. A browser download is quarantined, curl's isn't. Add the flag so Gatekeeper behaves the same:
   `xattr -w com.apple.quarantine "0081;$(printf '%x' $(date +%s));Safari;" build/dl/Stackbar-1.0.0-beta.1.dmg`
3. Mount it (`hdiutil attach -nobrowse`), copy the app with `ditto` to `/Applications`, detach.
   Record `xattr -l /Applications/Stackbar.app`.
4. Record, before the first launch:
   ```sh
   codesign --verify --strict -vvv /Applications/Stackbar.app 2>&1
   codesign -dvvv -r- /Applications/Stackbar.app 2>&1
   spctl -a -vv /Applications/Stackbar.app 2>&1
   ```
5. `open /Applications/Stackbar.app`. Ask the user what macOS shows, and to do the one documented
   step: **Done**, then System Settings → Privacy & Security → **Open Anyway**, confirm. Record
   exactly what they saw (this is the Done-when's "one Open Anyway step").

### 3. Accessibility: catch what TCC says

1. Start a log stream **before** the user clicks:
   ```sh
   log stream --style compact --predicate 'subsystem == "com.apple.TCC" OR process == "tccd"' > build/tcc-stream.log 2>&1 &
   ```
2. Ask the user to go through onboarding to the Accessibility step, click *Open System Settings*,
   and tell you whether Stackbar appears in the Accessibility list. Then ask them to switch it on
   (add it with **+** if it isn't listed) and to tell you whether onboarding turns to *Granted*
   within ~5 s.
3. Stop the stream (`kill %1`). Put every line mentioning `stackbar`, `sebas1337` or
   `Stackbar` into the report, plus ~20 lines around the first `deny`, `invalid`, `csreq`,
   `requirement`, `untrusted`, `SecStaticCode` or `SecCode` match.
4. Also run `log show --last 10m --style compact --predicate 'process == "tccd"' | grep -i -E 'stackbar|sebas1337' | tail -50`.

**If onboarding says Granted:** the certificate isn't the problem here; note that clearly (the
fresh user account then differs in something else: ask the user whether that test user was a
*Standard* or *Administrator* account and note it), and go on with step 5.

### 4. Only if still not granted: the trust experiment

1. Extract the app's certificate and trust it for code signing **in this login keychain only**
   (macOS asks for the user's password in a dialog; tell the user before you run it):
   ```sh
   codesign -d --extract-certificates=build/dl/sbcert /Applications/Stackbar.app
   security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db build/dl/sbcert0
   ```
2. Quit and reopen Stackbar (`pkill -x Stackbar; open /Applications/Stackbar.app`). Ask the user
   whether Accessibility now shows *Granted* (toggle off/on once if not). Record the result and
   `spctl -a -vv` / `codesign --verify --strict -vvv` again.
3. Remove the trust again so the account stays clean, and record it:
   `security remove-trusted-cert build/dl/sbcert0` (asks for the password).
4. If it only worked while trusted, **stop here** and finish the report: that is the answer, and
   the distribution decision has to be revisited. Don't try other workarounds.

### 5. If Accessibility works: Screen Recording, the update, login

1. Ask the user to finish onboarding (Screen Recording, keep *Open Stackbar at login* checked).
   Record whether each permission showed *Granted*.
2. Ask the user: icon menu → **Check for Updates…** → expect "Stackbar 1.0.0-beta.2 is
   available" → **Install and Relaunch**. Afterwards record:
   `defaults read /Applications/Stackbar.app/Contents/Info CFBundleShortVersionString` (expect
   `1.0.0-beta.2`), `codesign -dvvv -r- /Applications/Stackbar.app 2>&1 | grep -E 'Authority|designated'`,
   `xattr -l /Applications/Stackbar.app`, and whether macOS showed **any** permission or
   Gatekeeper prompt (there must be none).
3. Ask the user: Debug → **Copy Diagnostics**; then save it with `pbpaste > build/m5-diag-beta2.json`
   (don't edit it; the dev session decides whether it becomes a fixture).
4. Login item: `sfltool dumpbtm 2>/dev/null | grep -i -A3 stackbar` (if it needs sudo, ask the user
   to run it). Ask the user to log out and in later and report whether Stackbar started; you can
   leave that question in the report as open.

### 6. Finish

- At the top of the report, a short summary: works / doesn't, at which step, and the single most
  telling log line or output.
- Leave the test state as it is (`/Applications/Stackbar.app`, the `.bak` config). Tell the user
  in Dutch: the report is in `build/m5-accessibility-report.md`, and to tell the dev session
  "rapport staat klaar".
