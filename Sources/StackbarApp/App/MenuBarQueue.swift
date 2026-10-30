/// Runs the sequences that expand and collapse the menu bar (dropdown refresh, click forwarding,
/// arrangement) one after the other, so none changes the bar in the middle of another.
@MainActor
final class MenuBarQueue {
    private var last: Task<Void, Never>?
    /// Sequences queued or running.
    private var pending = 0

    /// True while a sequence is queued or running (a forwarded click stays expanded until its menu
    /// closes): the watcher and auto-collapse wait.
    var isRunning: Bool { pending > 0 }

    func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = last
        pending += 1
        last = Task {
            await previous?.value
            await work()
            pending -= 1
        }
    }
}
