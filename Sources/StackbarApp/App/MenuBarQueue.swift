/// Runs the sequences that expand and collapse the menu bar (dropdown refresh, click forwarding,
/// arrangement) one after the other, so none changes the bar in the middle of another.
@MainActor
final class MenuBarQueue {
    private var last: Task<Void, Never>?

    func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = last
        last = Task {
            await previous?.value
            await work()
        }
    }
}
