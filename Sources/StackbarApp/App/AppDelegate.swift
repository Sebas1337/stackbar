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
    private var updates: UpdateController?
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
        let updates = UpdateController(store: store, buildInfo: buildInfo)
        let general = GeneralSettingsController(store: store, hotKeys: hotKeys, watcher: watcher, updates: updates)
        let settings = SettingsWindowController(menuBar: menuBar, arranger: arranger, capturer: capturer, general: general)
        let onboarding = OnboardingWindowController { [weak settings] in settings?.show() }
        let debug = DebugController(buildInfo: buildInfo, menuBar: menuBar)

        // Setup was only waiting for the relaunch Screen Recording needs (welcome page passed, both
        // permissions granted): finish it without its window and open Settings, its next step.
        let finishesSetup = !store.config.onboardingCompleted
            && OnboardingStep.first(welcomeDone: store.config.onboardingWelcomeDone, permissions: PermissionState.current) == nil
        if finishesSetup { store.update { $0.onboardingCompleted = true } }
        // Until onboarding has finished, the icon opens it instead of the panel and collapsing is
        // refused (docs/PLAN.md, Decisions → First run).
        menuBar.isSetUp = store.config.onboardingCompleted
        let openDropdown: () -> Void = { [weak menuBar, weak dropdown, weak onboarding, weak store] in
            if menuBar?.isSetUp == true {
                dropdown?.toggle()
            } else {
                onboarding?.show(welcomeDone: store?.config.onboardingWelcomeDone ?? false)
            }
        }
        menuBar.icon.onClick = openDropdown
        hotKeys.onPress = openDropdown
        menuBar.icon.onMenu = { [weak dropdown] in dropdown?.close() }
        menuBar.icon.installCollapseItems(
            isCollapsed: { [weak menuBar] in menuBar?.isCollapsed ?? false },
            // Queued, so it doesn't change the menu bar in the middle of a refresh or a forwarded click.
            toggle: { [weak queue, weak menuBar, weak watcher] in
                queue?.enqueue {
                    guard let menuBar else { return }
                    menuBar.toggleCollapsed()
                    if !menuBar.isCollapsed { watcher?.noteExpanded() }
                }
            },
            isAutoCollapsing: { [weak general] in general?.autoCollapses ?? false },
            toggleAutoCollapse: { [weak general] in general?.toggleAutoCollapse() }
        )
        menuBar.icon.installSettingsItem { [weak settings] in settings?.show() }
        menuBar.icon.installUpdateItem { [weak updates] in updates?.check(userInitiated: true) }
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
        updates.isBusy = { [weak menuBar, weak arranger, weak queue, weak dropdown] in
            menuBar?.isSetUp != true || arranger?.isRunning == true || queue?.isRunning == true || dropdown?.isOpen == true
        }
        updates.start()
        onboarding.onWelcomeDone = { [weak store, weak general] opensAtLogin in
            store?.update { $0.onboardingWelcomeDone = true }
            general?.setOpensAtLogin(opensAtLogin)
        }
        onboarding.onFinish = { [weak menuBar, weak store, weak arranger, weak watcher] in
            store?.update { $0.onboardingCompleted = true }
            menuBar?.isSetUp = true
            arranger?.apply(force: false)
            watcher?.start()
        }
        debug.resetOnboarding = { [weak menuBar, weak store, weak onboarding] in
            store?.update {
                $0.onboardingCompleted = false
                $0.onboardingWelcomeDone = false
            }
            menuBar?.setCollapsed(false)
            menuBar?.isSetUp = false
            onboarding?.show(welcomeDone: false, opensAtLogin: LoginItem.isEnabled || LoginItem.needsApproval)
        }
        debug.runDeadZoneSpike = { [weak menuBar, weak store, weak queue, weak arranger] in
            guard let menuBar, let store else { return }
            let spike = DeadZoneSpike(menuBar: menuBar) { [weak store] in store?.config ?? StackbarConfig() }
            queue?.enqueue {
                if await spike.run() { arranger?.apply(force: true) }
            }
        }

        if menuBar.isSetUp {
            // Restore the collapsed state of the last quit, then put items back where the user wants
            // them: collapsed, the arrangement takes its collapsed path and checks the collapsed bar
            // afterwards. The new status items need a moment to show up in the window list.
            queue.enqueue { try? await Task.sleep(for: .seconds(1)) }
            if store.config.isCollapsed {
                queue.enqueue { [weak menuBar] in menuBar?.setCollapsed(true) }
            }
            if finishesSetup {
                queue.enqueue { [weak settings] in settings?.show() }
            }
            arranger.apply(force: false)
            watcher.start()
        } else {
            onboarding.show(welcomeDone: store.config.onboardingWelcomeDone)
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
        self.updates = updates
        self.debug = debug
        Logger(subsystem: "io.github.sebas1337.stackbar", category: "app")
            .notice("launched \(buildInfo.displayString, privacy: .public), AX trusted=\(AXIsProcessTrusted(), privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let menuBar else { return }
        store?.update { $0.isCollapsed = menuBar.isCollapsed }
    }
}
