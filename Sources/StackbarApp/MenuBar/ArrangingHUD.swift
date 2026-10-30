import AppKit
import SwiftUI
import StackbarCore

/// A small note under Stackbar's icon while an arrangement runs and the user's input is blocked:
/// what is happening and that Esc stops it. Doesn't take clicks or focus.
@MainActor
final class ArrangingHUD {
    private let hostingView = NSHostingView(rootView: ArrangingHUDView())
    private lazy var panel: DropdownPanel = {
        let panel = DropdownPanel(content: hostingView)
        panel.ignoresMouseEvents = true
        return panel
    }()

    func show(under icon: Rect?) {
        let size = hostingView.fittingSize
        if let icon, let screen = ScreenReader.screens().first(where: { $0.frame.contains(x: icon.midX, y: icon.midY) }) {
            let frame = PanelPlacement.frame(width: size.width, height: size.height, icon: icon, screen: screen)
            panel.setFrame(ScreenReader.appKitFrame(frame), display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct ArrangingHUDView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Arranging the menu bar…").font(.callout)
                Text("Mouse and keyboard are paused. Esc stops.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize()
    }
}
