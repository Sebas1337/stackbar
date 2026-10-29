import AppKit
import os
import SwiftUI
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "dropdown")

/// The dropdown panel under the icon (docs/PLAN.md "How it works" steps 3 and 4). Opening it
/// shows the dropdown items with their cached images, then refreshes them and collapses
/// (`DropdownRefresh`); clicking an item closes it and forwards the click (`ClickForwarding`).
/// Both sequences expand and collapse the menu bar, so they run one after the other.
@MainActor
final class DropdownController {
    private let menuBar: MenuBarController
    private let capturer = ItemCapturer()
    private let presser = ItemPresser()
    private let refresh: DropdownRefresh
    private let model = DropdownModel()
    private let hostingView: NSHostingView<DropdownView>
    private let panel: DropdownPanel
    /// The running sequence; the next one waits for it.
    private var queue: Task<Void, Never>?
    private var eventMonitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    /// A click on the icon while the panel is open first closes the panel (it loses key focus),
    /// then reaches the icon: that click must not reopen it.
    private var lastClose = Date.distantPast

    init(menuBar: MenuBarController) {
        self.menuBar = menuBar
        refresh = DropdownRefresh(driver: menuBar, capturer: capturer)
        hostingView = NSHostingView(rootView: DropdownView(model: model))
        panel = DropdownPanel(content: hostingView)
        model.onSelect = { [weak self] item in self?.forward(item) }
        model.onUpdate = { [weak self] in self?.updateImages() }
    }

    var isOpen: Bool { panel.isVisible }

    func toggle() {
        if isOpen {
            close()
        } else if Date().timeIntervalSince(lastClose) > 0.3 {
            open()
        }
    }

    func open() {
        model.permissions = PermissionState.current
        model.hovered = nil
        panel.appearance = menuBar.icon.menuBarAppearance
        place()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        refreshItems(force: false)
    }

    /// The panel's update button: capture every item again.
    func updateImages() {
        refreshItems(force: true)
    }

    /// Finds the dropdown items and, when needed or `force`d, captures them (`DropdownRefresh`).
    private func refreshItems(force: Bool) {
        enqueue { [weak self] in
            guard let self else { return }
            model.isUpdating = true
            defer { model.isUpdating = false }
            let report = await refresh.run(force: force) { [weak self] items in self?.show(items) }
            if report.outcome == .noLayout {
                // Last time's items may be gone; don't offer them.
                show([])
            } else {
                capturer.keepImages(of: Set(report.dropdown))
                show(model.items.map(\.menuBarItem))
            }
            model.isEmpty = report.outcome == .empty
            if report.outcome == .noLayout {
                model.notice = "Stackbar couldn't find its icon or divider in the menu bar. Try again in a moment."
            } else if report.outcome != .empty, !report.isCollapsed {
                model.notice = menuBar.refusal
            } else {
                model.notice = nil
            }
            log(report.description)
        }
    }

    func close() {
        guard isOpen else { return }
        removeMonitors()
        panel.orderOut(nil)
    }

    /// Show All Items / Collapse Menu Bar from the icon's menu. Queued, so it doesn't change the
    /// menu bar in the middle of a refresh or a forwarded click.
    func toggleCollapsed() {
        enqueue { [weak self] in self?.menuBar.toggleCollapsed() }
    }

    private func forward(_ item: MenuBarItem) {
        close()
        enqueue { [weak self] in
            guard let self else { return }
            let report = await ClickForwarding(driver: menuBar, presser: presser, capturer: capturer, recaptures: false).run(item)
            if report.recaptured { show(model.items.map(\.menuBarItem)) }
            log(report.description)
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    // MARK: Showing items

    private func show(_ items: [MenuBarItem]) {
        model.items = items.map { item in
            let app = item.ax.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
            let size = CGSize(width: item.window.frame.width, height: item.window.frame.height)
            return DropdownModel.Item(
                menuBarItem: item,
                size: size,
                image: capturer.image(for: item).map { NSImage(cgImage: $0, size: size) },
                appIcon: app?.icon,
                name: Self.name(of: item, appName: app?.localizedName)
            )
        }
        if isOpen { place() }
    }

    /// "Bluetooth" for Control Center's items, "App – Item" when the item names itself,
    /// otherwise the app's name.
    private static func name(of item: MenuBarItem, appName: String?) -> String {
        let itemName = [item.ax?.title, item.ax?.axDescription].compactMap { $0?.plainText }.first { !$0.isEmpty }
        let appName = appName ?? item.bundleID ?? "Unknown app"
        guard let itemName, itemName != appName else { return appName }
        return item.bundleID == "com.apple.controlcenter" ? itemName : "\(appName) – \(itemName)"
    }

    /// Sizes the panel to its content and puts it under the icon.
    private func place() {
        let size = hostingView.fittingSize
        guard let icon = menuBar.icon.frame else { return }
        let screens = ScreenReader.screens()
        guard let screen = screens.first(where: { $0.frame.contains(x: icon.midX, y: icon.midY) })
            ?? screens.first(where: \.isMain)
        else { return }
        let frame = PanelPlacement.frame(width: size.width, height: size.height, icon: icon, screen: screen)
        panel.setFrame(ScreenReader.appKitFrame(frame), display: true)
    }

    // MARK: Closing on Esc and outside clicks

    private func installMonitors() {
        guard eventMonitors.isEmpty else { return }
        // Clicks in other apps (and on the desktop) close the panel.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) {
            eventMonitors.append(monitor)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOpen else { return }
                self.close()
                self.lastClose = Date()
            }
        }
    }

    private func removeMonitors() {
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        SpikeLog.shared.add(message)
    }
}
