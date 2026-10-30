import ApplicationServices
import StackbarCore

/// Moves items for `Arrangement` with a synthesized ⌘-drag, the cursor hidden meanwhile
/// (`CursorHider`) and put back where it was: the plain drag of S3 (`ItemMover.visible`) across
/// the divider, or, to make room for an item behind the notch, the window-targeted drag of
/// S9/S11 (`ItemMover.windowTargeted`) aimed at that item.
@MainActor
final class CommandDragMover: ItemMoving {
    func move(_ move: ArrangementPlan.Move) async {
        // Without Accessibility the synthesized events are dropped; `Arrangement` reports it failed.
        guard AXIsProcessTrusted() else { return }
        let window = move.item.window
        let point = CGPoint(x: move.point.x, y: move.point.y)
        await CursorHider.hidden {
            if let target = move.dropWindowID {
                await ItemMover.drag(window, to: point, targetWindowID: target, route: ItemMover.windowTargeted)
            } else {
                await ItemMover.drag(window, to: point, targetWindowID: window.windowID, route: ItemMover.visible)
            }
        }
    }
}
