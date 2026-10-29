import ApplicationServices
import StackbarCore

/// Moves items for `Arrangement` with the visible ⌘-drag of S3 (`ItemMover.visible`), the cursor
/// hidden meanwhile (`CursorHider`) and put back where it was.
@MainActor
final class CommandDragMover: ItemMoving {
    func move(_ item: MenuBarItem, to point: ArrangementPlan.Point) async {
        // Without Accessibility the synthesized events are dropped; `Arrangement` reports it failed.
        guard AXIsProcessTrusted() else { return }
        await CursorHider.hidden {
            await ItemMover.drag(item.window, to: CGPoint(x: point.x, y: point.y), targetWindowID: item.window.windowID, route: ItemMover.visible)
        }
    }
}
