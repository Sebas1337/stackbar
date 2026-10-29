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
        enqueue { [weak self] in
            guard let self else { return }
            let report = await refresh.run { [weak self] items in self?.show(items) }
            if report.outcome != .noLayout {
                capturer.keepImages(of: Set(report.dropdown))
            }
            model.isEmpty = report.outcome == .empty
            model.notice = report.outcome == .noLayout
                ? "Stackbar couldn't find its icon or divider in the menu bar. Try again in a moment."
                : nil
            show(model.items.map(\.menuBarItem))
            log(report.description)
        }
    }

    func close() {
        guard isOpen else { return }
        removeMonitors()
        panel.orderOut(nil)
        lastClose = Date()
    }

    private func forward(_ item: MenuBarItem) {
        close()
        enqueue { [weak self] in
            guard let self else { return }
            let report = await ClickForwarding(driver: menuBar, presser: presser, capturer: capturer).run(item)
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
        let grid = DropdownGrid.layout(sizes: items.map { ($0.window.frame.width, $0.window.frame.height) })
        model.items = zip(items, grid.frames).map { item, frame in
            let app = item.ax.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
            return DropdownModel.Item(
                menuBarItem: item,
                frame: frame,
                image: capturer.images[item.window.windowID].map {
                    NSImage(cgImage: $0, size: NSSize(width: frame.width, height: frame.height))
                },
                appIcon: app?.icon,
                name: Self.name(of: item, appName: app?.localizedName)
            )
        }
        model.gridWidth = grid.width
        model.gridHeight = grid.height
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
            MainActor.assumeIsolated { self?.close() }
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
