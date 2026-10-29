import AppKit
import SwiftUI
import StackbarCore

/// Debug → Items window: every status item, live, plus buttons for the spike experiments.
@MainActor
final class ItemsWindowController {
    private let window: NSWindow
    private let model: ItemsModel

    init(debug: DebugController) {
        model = ItemsModel(debug: debug)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stackbar — Menu bar items"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ItemsView(model: model))
        window.center()
        // Each refresh scans every app through AX: only while the window is open.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [model] _ in
            MainActor.assumeIsolated { model.stopAutoRefresh() }
        }
    }

    func show() {
        model.refresh()
        model.startAutoRefresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// One row: a status item window joined with its AX element.
struct ItemRow: Identifiable {
    var id: UInt32 { window.windowID }
    var window: WindowInfo
    var ax: AXMenuBarItem?
    var isStackbar: Bool
    var overlapsNotch: Bool

    var app: String { ax?.info.bundleID ?? (isStackbar ? "Stackbar" : "?") }
    var name: String {
        [ax?.info.title?.plainText, ax?.info.axDescription?.plainText, window.title?.plainText]
            .compactMap { $0 }.first ?? ""
    }
}

@MainActor
@Observable
final class ItemsModel {
    var rows: [ItemRow] = []
    var selection: UInt32?
    var status = "Select an item, then run an experiment. Results also go into Copy diagnostics."
    var busy = false
    var permissions = PermissionState.current

    @ObservationIgnored private let debug: DebugController
    @ObservationIgnored private var timer: Timer?

    init(debug: DebugController) {
        self.debug = debug
    }

    var hasDivider: Bool { debug.divider != nil }
    var isCollapsed: Bool { debug.divider?.isCollapsed ?? false }

    func startAutoRefresh() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.busy else { return }
                self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        permissions = PermissionState.current
        let windows = WindowListReader.windows()
        let axItems = AXMenuBarReader.items()
        let screen = ScreenReader.screens().first { $0.isPrimary }
        let ownIDs = debug.stackbarWindowIDs
        let joined = MenuBarItemJoin.join(windows: windows, axItems: axItems.map(\.info))
        rows = joined.map { item in
            ItemRow(
                window: item.window,
                ax: item.axItem.flatMap { info in axItems.first { $0.info == info } },
                isStackbar: ownIDs.contains(item.window.windowID),
                overlapsNotch: screen.map { NotchGeometry.overlapsNotch(item.window.frame, on: $0) } ?? false
            )
        }
    }

    private var selectedRow: ItemRow? { rows.first { $0.id == selection } }

    private func run(_ work: @escaping @MainActor () async -> String) {
        guard !busy else { return }
        busy = true
        status = "Running…"
        Task {
            status = await work()
            busy = false
            refresh()
        }
    }

    // MARK: Divider

    func toggleDivider() {
        debug.toggleDivider()
        refresh()
    }

    func toggleCollapsed() {
        debug.setCollapsed(!isCollapsed)
        refresh()
    }

    // MARK: S1

    /// Captures the selected item as it is now; with `collapsed`, collapses first (the item is
    /// pushed off-screen if it is left of the divider), captures, and expands again.
    func capture(collapsed: Bool) {
        guard let row = selectedRow else { return }
        let debug = debug
        let wasCollapsed = isCollapsed
        run {
            if collapsed && !wasCollapsed {
                debug.setCollapsed(true)
                try? await Task.sleep(for: .milliseconds(700))
            }
            let window = WindowListReader.windows().first { $0.windowID == row.window.windowID } ?? row.window
            let result = await SpikeActions.capture(window: window, label: collapsed ? "collapsed" : "current")
            if collapsed && !wasCollapsed { debug.setCollapsed(false) }
            if let file = result.file { NSWorkspace.shared.open(file) }
            return result.message
        }
    }

    // MARK: S2

    func press(collapsed: Bool) {
        guard let row = selectedRow, let ax = row.ax else {
            status = "No AX element for this item (needs Accessibility, or no frame match)."
            return
        }
        let debug = debug
        run {
            if collapsed {
                debug.setCollapsed(true)
                try? await Task.sleep(for: .milliseconds(700))
            }
            let message = await SpikeActions.press(ax)
            // Leave it collapsed so the user can see where the menu opened; they expand by hand.
            return message + (collapsed ? " (still collapsed: close the menu, then Expand)" : "")
        }
    }

    // MARK: S3

    /// ⌘-drags the selected item to the other side of the divider.
    func dragAcrossDivider() {
        guard let row = selectedRow else { return }
        guard let dividerID = debug.divider?.windowID,
              let divider = WindowListReader.windows().first(where: { $0.windowID == dividerID })
        else {
            status = "Show the divider first."
            return
        }
        guard !isCollapsed else {
            status = "Expand first: ⌘-drag can't reach off-screen items."
            return
        }
        let toDropdown = row.window.frame.midX > divider.frame.midX
        // Bar → dropdown: drop just left of the divider. Dropdown → bar: just right of it.
        let target = CGPoint(
            x: toDropdown ? divider.frame.minX - 4 : divider.frame.maxX + 4,
            y: divider.frame.midY
        )
        run {
            await SpikeActions.commandDrag(row.window, to: target, label: toDropdown ? "bar→dropdown" : "dropdown→bar")
        }
    }

    // MARK: Permissions

    func requestAccessibility() {
        PermissionState.requestAccessibility()
    }

    func requestScreenRecording() {
        PermissionState.requestScreenRecording()
    }
}

struct ItemsView: View {
    @Bindable var model: ItemsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Accessibility", systemImage: model.permissions.accessibility ? "checkmark.circle.fill" : "xmark.circle")
                if !model.permissions.accessibility {
                    Button("Request") { model.requestAccessibility() }
                }
                Label("Screen Recording", systemImage: model.permissions.screenRecording ? "checkmark.circle.fill" : "xmark.circle")
                if !model.permissions.screenRecording {
                    Button("Request") { model.requestScreenRecording() }
                }
                Spacer()
                Text("\(model.rows.count) status items")
                    .foregroundStyle(.secondary)
                Button("Refresh") { model.refresh() }
            }

            Table(model.rows, selection: $model.selection) {
                TableColumn("Window") { Text(String($0.window.windowID)).monospacedDigit() }
                    .width(60)
                TableColumn("App") { row in
                    Text(row.app).foregroundStyle(row.ax == nil ? .secondary : .primary)
                }
                .width(min: 140, ideal: 220)
                TableColumn("Name") { Text($0.name) }
                    .width(min: 80, ideal: 160)
                TableColumn("x") { Text(String(Int($0.window.frame.x))).monospacedDigit() }
                    .width(50)
                TableColumn("w") { Text(String(Int($0.window.frame.width))).monospacedDigit() }
                    .width(40)
                TableColumn("On screen") { Text($0.window.isOnScreen ? "yes" : "no") }
                    .width(70)
                TableColumn("Notch") { Text($0.overlapsNotch ? "overlaps" : "") }
                    .width(60)
                TableColumn("AX frame") { row in
                    Text(row.ax?.info.frame.map(SpikeActions.describe) ?? "–").monospacedDigit()
                }
                .width(min: 120, ideal: 150)
            }

            GroupBox("Divider (S8)") {
                HStack {
                    Button(model.hasDivider ? "Remove divider" : "Show divider") { model.toggleDivider() }
                    Button(model.isCollapsed ? "Expand" : "Collapse (10 000 pt)") { model.toggleCollapsed() }
                        .disabled(!model.hasDivider)
                    Spacer()
                }
            }

            GroupBox("Selected item") {
                HStack {
                    Button("Capture (S1)") { model.capture(collapsed: false) }
                    Button("Capture while collapsed (S1)") { model.capture(collapsed: true) }
                        .disabled(!model.hasDivider)
                    Divider().frame(height: 16)
                    Button("AXPress (S2)") { model.press(collapsed: false) }
                    Button("AXPress while collapsed (S2)") { model.press(collapsed: true) }
                        .disabled(!model.hasDivider)
                    Divider().frame(height: 16)
                    Button("⌘-drag across divider (S3/S4)") { model.dragAcrossDivider() }
                        .disabled(!model.hasDivider)
                    Spacer()
                }
                .disabled(model.selection == nil || model.busy)
            }

            Text(model.status)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(minWidth: 900, minHeight: 420)
    }
}
