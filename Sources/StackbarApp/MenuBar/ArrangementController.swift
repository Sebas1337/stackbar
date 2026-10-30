import os
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "moves")

/// Assigns items and moves them (docs/PLAN.md "How it works" step 5): stores the assignment,
/// then queues an `Arrangement` run behind any running dropdown sequence.
@MainActor
final class ArrangementController {
    private let menuBar: MenuBarController
    private let queue: MenuBarQueue
    let store: ConfigStore
    private let arrangement: Arrangement
    /// Holds back the user's mouse and keyboard while items are dragged; Esc cancels.
    private let blocker = InputBlocker()
    private let hud = ArrangingHUD()

    /// The last run's report, for Settings.
    private(set) var lastReport: Arrangement.Report?
    /// Runs after every arrangement (Settings reloads its lists).
    var onChange: (() -> Void)?
    /// Runs queued or running.
    private var pending = 0
    var isRunning: Bool { pending > 0 }

    init(menuBar: MenuBarController, queue: MenuBarQueue, store: ConfigStore) {
        self.menuBar = menuBar
        self.queue = queue
        self.store = store
        arrangement = Arrangement(driver: menuBar, mover: CommandDragMover())
        arrangement.onWillMove = { [weak self] in
            guard let self else { return }
            blocker.start()
            hud.show(under: menuBar.icon.frame)
        }
        blocker.onEscape = { [weak self] in self?.arrangement.cancel() }
    }

    /// The user's choice in Settings: saved, then applied right away (blocked items tried again).
    func assign(_ item: MenuBarItem, to section: Section, name: String) {
        guard let identity = item.identity else { return }
        store.update { $0.assign(identity, to: section, name: name) }
        apply(force: true)
    }

    /// Moves every misplaced item. `force` retries items found blocked before.
    func apply(force: Bool) {
        pending += 1
        onChange?()
        queue.enqueue { [weak self] in
            guard let self else { return }
            let report = await arrangement.run(config: store.config, force: force)
            blocker.stop()
            hud.hide()
            lastReport = report
            pending -= 1
            logger.notice("\(report.description, privacy: .public)")
            SpikeLog.shared.add(report.description)
            onChange?()
        }
    }
}
