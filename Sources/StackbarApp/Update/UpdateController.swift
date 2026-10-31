import AppKit
import os
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "update")

/// Looks for updates on GitHub Releases (docs/PLAN.md M5, Updates): by itself once a day when the
/// user allows it (`UpdateCheck`), or from Check for Updates…. Offers the newest one
/// (`ReleaseFeed`) in an alert; `UpdateInstaller` installs it. One check or install at a time.
@MainActor
final class UpdateController {
    static let releasesAPI = URL(string: "https://api.github.com/repos/Sebas1337/stackbar/releases?per_page=30")!

    private let store: ConfigStore
    private let current: SemanticVersion?
    private var timer: Timer?
    private var isWorking = false
    /// The last outcome in words, for Settings → General.
    private(set) var status: String?
    /// Runs when `status` changes.
    var onChange: () -> Void = {}
    /// True while onboarding runs or Stackbar uses the menu bar (an arrangement holds back the
    /// user's input): an automatic check waits for the next hour instead of raising an alert.
    var isBusy: () -> Bool = { false }

    init(store: ConfigStore, buildInfo: BuildInfo) {
        self.store = store
        current = SemanticVersion(buildInfo.version)
    }

    /// Checks shortly after launch and then hourly whether a daily check is due.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard !isBusy(),
              UpdateCheck.isDue(now: Date(), lastCheck: store.config.lastUpdateCheck, enabled: store.config.checksForUpdates)
        else { return }
        check(userInitiated: false)
    }

    /// Check for Updates…: also reports "up to date" and errors, and offers a skipped version again.
    func check(userInitiated: Bool) {
        guard !isWorking else { return }
        guard let current else {
            if userInitiated { inform("This build has no version number, so it can't be updated.") }
            return
        }
        isWorking = true
        setStatus("Checking…")
        Task {
            defer { isWorking = false }
            let update: ReleaseFeed.Update?
            do {
                update = try await newest(after: current)
            } catch {
                logger.error("update check failed: \(error.localizedDescription, privacy: .public)")
                setStatus("Couldn't check for updates: \(error.localizedDescription)")
                if userInitiated { inform("Couldn't check for updates: \(error.localizedDescription)") }
                return
            }
            store.update { $0.lastUpdateCheck = Date() }
            guard let update else {
                setStatus("Stackbar \(current) is up to date.")
                if userInitiated { inform("Stackbar \(current) is the newest version.") }
                return
            }
            if !userInitiated, update.version == store.config.skippedVersion.flatMap(SemanticVersion.init) {
                setStatus("Stackbar \(update.version) is available (skipped).")
                return
            }
            setStatus("Stackbar \(update.version) is available.")
            // An automatic check that found something while Stackbar got busy offers it next time.
            if !userInitiated, isBusy() { return }
            if offer(update, current: current) {
                await install(update)
            }
        }
    }

    private func newest(after current: SemanticVersion) async throws -> ReleaseFeed.Update? {
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return ReleaseFeed.update(in: try ReleaseFeed.decode(data), current: current)
    }

    /// True when the user chose to install.
    private func offer(_ update: ReleaseFeed.Update, current: SemanticVersion) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stackbar \(update.version) is available"
        let notes = update.notes.count > 1200 ? String(update.notes.prefix(1200)) + "…" : update.notes
        alert.informativeText = "You have \(current).\n\n\(notes)"
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertThirdButtonReturn:
            store.update { $0.skippedVersion = update.version.description }
            setStatus("Stackbar \(update.version) is available (skipped).")
        default:
            break
        }
        return false
    }

    private func install(_ update: ReleaseFeed.Update) async {
        setStatus("Installing Stackbar \(update.version)…")
        do {
            try await UpdateInstaller.install(update)
        } catch UpdateInstaller.Failure.cancelled {
            setStatus("Stackbar \(update.version) is available.")
        } catch {
            logger.error("update failed: \(error.localizedDescription, privacy: .public)")
            SpikeLog.shared.add("Update to \(update.version) failed: \(error.localizedDescription)")
            setStatus("The update failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Couldn't install Stackbar \(update.version)"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Open Download Page")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(update.page)
            }
        }
    }

    private func setStatus(_ text: String) {
        status = text
        onChange()
    }

    private func inform(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
