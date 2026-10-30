import AppKit
import ApplicationServices
import SwiftUI
import StackbarCore

/// The Settings window (docs/PLAN.md M4): assign items to the menu bar or the dropdown. Opens
/// from the icon's menu and from the panel.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let model = SettingsModel()
    private let menuBar: MenuBarController
    private let arranger: ArrangementController
    private let capturer: ItemCapturer
    private let general: GeneralSettingsController

    init(menuBar: MenuBarController, arranger: ArrangementController, capturer: ItemCapturer, general: GeneralSettingsController) {
        self.menuBar = menuBar
        self.arranger = arranger
        self.capturer = capturer
        self.general = general
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stackbar Settings"
        window.identifier = GeneralSettingsModel.windowIdentifier
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsTabsView(items: model, general: general.model))
        window.center()
        model.onAssign = { [arranger] row, section in
            guard let item = row.item else { return }
            arranger.assign(item, to: section, name: row.name)
        }
        model.onRetry = { [arranger] in arranger.apply(force: true) }
        arranger.onChange = { [weak self] in
            guard let self, window.isVisible else { return }
            reload()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [general] _ in
            MainActor.assumeIsolated { general.close() }
        }
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        reload()
        general.reload()
        captureMissingImages()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Reads the menu bar again (every app through Accessibility) and rebuilds both lists.
    private func reload() {
        let layout = menuBar.layout()
        let config = arranger.store.config
        let report = arranger.lastReport
        var rows = layout.map { layout in layout.items.map { item in row(for: item, in: layout, config: config, report: report) } } ?? []
        let present = Set((layout?.items ?? []).compactMap(\.identity))
        for (index, assignment) in config.assignments.enumerated() where !present.contains(assignment.identity) {
            rows.append(SettingsModel.Row(
                id: "saved:\(index)",
                item: nil,
                appearance: nil,
                name: assignment.name,
                section: assignment.section,
                caption: "Not in the menu bar (app not running)",
                canMove: false,
                canRetry: false
            ))
        }
        model.rows = rows
        model.menuBarIsDark = menuBar.icon.menuBarAppearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        model.notice = notice(layout: layout)
        model.status = status(report)
    }

    private func row(for item: MenuBarItem, in layout: MenuBarLayout, config: StackbarConfig, report: Arrangement.Report?) -> SettingsModel.Row {
        let appearance = ItemAppearance(item, capturer: capturer)
        let id = item.window.windowID
        let assigned = item.identity.flatMap(config.section(for:))
        var caption: String?
        var canRetry = false
        let arrangeable = item.identity.map { ArrangementPlan.isArrangeable($0, in: layout) } ?? false
        let canMove = arrangeable && !item.isImmovable
        if item.isImmovable {
            caption = "macOS doesn't let this item move"
        } else if item.identity == nil {
            caption = "Unknown app"
        } else if !arrangeable {
            caption = "Can't tell it apart from its app's other items: grant Screen Recording"
        } else if let assigned, assigned != item.section {
            canRetry = !arranger.isRunning
            if arranger.isRunning {
                caption = "Moving…"
            } else if let blocker = report?.blocked[id] {
                caption = blocker == .clipped
                    ? "Behind the notch, with no visible item beside it to make room with"
                    : "Not moved (\(blocker.rawValue))"
            } else if report?.outOfRoom.contains(id) == true {
                caption = "No room: with this full a menu bar, it sits next to the notch where Stackbar can't reach it"
            } else if report?.reverted.contains(id) == true {
                caption = "macOS put it back when the menu bar collapsed"
            } else if report?.failed.contains(id) == true {
                caption = "Couldn't move it"
            } else {
                caption = "Not moved yet"
            }
        } else if item.isClipped {
            caption = item.section == .bar ? "Doesn't fit next to the notch: the menu bar is full. Open it from the panel" : "Behind the notch"
        }
        return SettingsModel.Row(
            id: String(id),
            item: item,
            appearance: appearance,
            name: appearance.name,
            section: assigned ?? item.section,
            caption: caption,
            canMove: canMove,
            canRetry: canRetry
        )
    }

    private func notice(layout: MenuBarLayout?) -> String? {
        if !AXIsProcessTrusted() {
            return "Stackbar needs Accessibility to know which app owns each item and to move items."
        }
        if layout?.divider == nil {
            return "Stackbar couldn't find its divider in the menu bar. Try again in a moment."
        }
        if let clipped = layout?.bar.filter(\.isClipped), !clipped.isEmpty {
            return "The menu bar is full: \(clipped.count) item\(clipped.count == 1 ? " doesn't" : "s don't") fit next to the notch. "
                + "They're in the panel; move some items to the Dropdown to make room."
        }
        return nil
    }

    private func status(_ report: Arrangement.Report?) -> String? {
        if arranger.isRunning { return "Moving items…" }
        guard let report else { return nil }
        switch report.outcome {
        case .arranged:
            var parts = ["Moved \(report.moved.count) item\(report.moved.count == 1 ? "" : "s")"]
            if !report.failed.isEmpty { parts.append("\(report.failed.count) couldn't be moved") }
            if !report.blocked.isEmpty { parts.append("\(report.blocked.count) out of reach") }
            return parts.joined(separator: ", ") + "."
        case .upToDate:
            return "Everything is where it belongs."
        case .noLayout:
            return "Stackbar couldn't read the menu bar."
        case .revealTimedOut:
            return "The dropdown items didn't come back into the menu bar; nothing was moved."
        }
    }

    /// Bar items have no image until captured once. They are on-screen, so ScreenCaptureKit takes
    /// them without revealing anything or showing the screen recording indicator.
    private func captureMissingImages() {
        guard CGPreflightScreenCaptureAccess() else { return }
        let missing = model.rows.compactMap(\.item).filter { $0.window.isOnScreen && !capturer.hasImage(of: $0) }
        guard !missing.isEmpty else { return }
        Task {
            _ = await capturer.capture(missing)
            if window.isVisible { reload() }
        }
    }
}
