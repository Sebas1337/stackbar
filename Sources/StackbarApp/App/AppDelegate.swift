import AppKit
import os
import StackbarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var store: ConfigStore?
    private var dropdown: DropdownController?
    private var arranger: ArrangementController?
    private var settings: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var watcher: MenuBarWatcher?
    private var hotKeys: HotKeyCenter?
    private var general: GeneralSettingsController?
    private var debug: DebugController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let menuBar = MenuBarController(buildInfo: buildInfo)
        let store = ConfigStore()
        let queue = MenuBarQueue()
        let capturer = ItemCapturer()
        let dropdown = DropdownController(menuBar: menuBar, queue: queue, capturer: capturer)
        let arranger = ArrangementController(menuBar: menuBar, queue: queue, store: store)
        let watcher = MenuBarWatcher()
        let hotKeys = HotKeyCenter()
        let general = GeneralSettingsController(store: store, hotKeys: hotKeys, watcher: watcher)
        let settings = SettingsWindowController(menuBar: menuBar, arranger: arranger, capturer: capturer, general: general)
        let onboarding = OnboardingWindowController { [weak settings] in settings?.show() }
        let debug = DebugController(buildInfo: buildInfo, menuBar: menuBar)

        // Until onboarding has finished, the icon opens it instead of the panel and collapsing is
        // refused (docs/PLAN.md, Decisions → First run).
        menuBar.isSetUp = store.config.onboardingCompleted
        let openDropdown: () -> Void = { [weak menuBar, weak dropdown, weak onboarding] in
            if menuBar?.isSetUp == true { dropdown?.toggle() } else { onboarding?.show() }
        }
        menuBar.icon.onClick = openDropdown
        hotKeys.onPress = openDropdown
        menuBar.icon.onMenu = { [weak dropdown] in dropdown?.close() }
        menuBar.icon.installCollapseItem(isCollapsed: { [weak menuBar] in menuBar?.isCollapsed ?? false }) { [weak dropdown] in
            dropdown?.toggleCollapsed()
        }
        menuBar.icon.installSettingsItem { [weak settings] in settings?.show() }
        dropdown.onSettings = { [weak settings] in settings?.show() }
        menuBar.icon.installDebugMenu(debug)

        watcher.isBusy = { [weak dropdown, weak arranger, weak settings, weak queue] in
            dropdown?.isOpen == true || arranger?.isRunning == true || settings?.isVisible == true || queue?.isRunning == true
        }
        watcher.isCollapsed = { [weak menuBar] in menuBar?.isCollapsed ?? true }
        watcher.onDue = { [weak arranger] in arranger?.apply(force: false) }
        watcher.onAutoCollapse = { [weak queue, weak menuBar] in
            queue?.enqueue {
                guard let menuBar, !menuBar.isCollapsed else { return }
                SpikeLog.shared.add("Auto-collapse")
                menuBar.setCollapsed(true)
            }
        }
        general.applyStored()
        onboarding.onFinish = { [weak menuBar, weak store, weak arranger, weak watcher, weak general] opensAtLogin in
            store?.update { $0.onboardingCompleted = true }
            general?.setOpensAtLogin(opensAtLogin)
            menuBar?.isSetUp = true
            arranger?.apply(force: false)
            watcher?.start()
        }
        debug.resetOnboarding = { [weak menuBar, weak store, weak onboarding] in
            store?.update { $0.onboardingCompleted = false }
            menuBar?.setCollapsed(false)
            menuBar?.isSetUp = false
            onboarding?.show(opensAtLogin: LoginItem.isEnabled || LoginItem.needsApproval)
        }

        if menuBar.isSetUp {
            // Restore the collapsed state of the last quit, then put items back where the user wants
            // them: collapsed, the arrangement takes its collapsed path and checks the collapsed bar
            // afterwards. The new status items need a moment to show up in the window list.
            queue.enqueue { try? await Task.sleep(for: .seconds(1)) }
            if store.config.isCollapsed {
                queue.enqueue { [weak menuBar] in menuBar?.setCollapsed(true) }
            }
            arranger.apply(force: false)
            watcher.start()
        } else {
            onboarding.show()
        }

        self.menuBar = menuBar
        self.store = store
        self.dropdown = dropdown
        self.arranger = arranger
        self.settings = settings
        self.onboarding = onboarding
        self.watcher = watcher
        self.hotKeys = hotKeys
        self.general = general
        self.debug = debug
        Logger(subsystem: "io.github.sebas1337.stackbar", category: "app")
            .notice("launched \(buildInfo.displayString, privacy: .public), AX trusted=\(AXIsProcessTrusted(), privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let menuBar else { return }
        store?.update { $0.isCollapsed = menuBar.isCollapsed }
    }
}
