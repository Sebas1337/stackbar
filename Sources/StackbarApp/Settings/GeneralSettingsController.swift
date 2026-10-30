import Foundation
import StackbarCore

/// Applies Settings → General (docs/PLAN.md M5): Open at Login (`LoginItem`), the shortcut
/// (`HotKeyCenter`) and auto-collapse (the watcher's `AutoCollapse`). The shortcut and the
/// auto-collapse delay are kept in the config.
@MainActor
final class GeneralSettingsController {
    let model = GeneralSettingsModel()
    private let store: ConfigStore
    private let hotKeys: HotKeyCenter
    private let watcher: MenuBarWatcher

    init(store: ConfigStore, hotKeys: HotKeyCenter, watcher: MenuBarWatcher) {
        self.store = store
        self.hotKeys = hotKeys
        self.watcher = watcher
        model.onOpensAtLogin = { [weak self] in self?.setOpensAtLogin($0) }
        model.onOpenLoginItems = { LoginItem.openSystemSettings() }
        model.onHotKey = { [weak self] in self?.setHotKey($0) }
        model.onRecording = { [weak self] recording in
            guard let self else { return }
            if recording {
                hotKeys.register(nil)
            } else {
                model.hotKeyRefused = !hotKeys.register(store.config.hotKey)
            }
        }
        model.onAutoCollapse = { [weak self] in self?.setAutoCollapse($0) }
    }

    /// At launch: the stored shortcut and auto-collapse delay take effect.
    func applyStored() {
        model.hotKeyRefused = !hotKeys.register(store.config.hotKey)
        watcher.autoCollapse.delaySeconds = store.config.autoCollapseSeconds
    }

    /// Reads the current state into the model (Settings is opening).
    func reload() {
        model.opensAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
        model.loginNeedsApproval = LoginItem.needsApproval
        model.hotKey = store.config.hotKey
        model.autoCollapseSeconds = store.config.autoCollapseSeconds
    }

    /// Settings is closing: a recording in progress is dropped.
    func close() {
        model.stopRecording()
    }

    func setOpensAtLogin(_ enabled: Bool) {
        // Unregistering what was never registered throws: only change what differs.
        guard enabled != (LoginItem.isEnabled || LoginItem.needsApproval) else { return reload() }
        do {
            try LoginItem.set(enabled)
            model.loginError = nil
        } catch {
            model.loginError = error.localizedDescription
        }
        SpikeLog.shared.add("Open at Login \(enabled ? "on" : "off"): status \(LoginItem.status.rawValue)")
        reload()
    }

    private func setHotKey(_ hotKey: HotKey?) {
        store.update { $0.hotKey = hotKey }
        model.hotKey = hotKey
        model.hotKeyRefused = !hotKeys.register(hotKey)
    }

    private func setAutoCollapse(_ seconds: Int?) {
        store.update { $0.autoCollapseSeconds = seconds }
        model.autoCollapseSeconds = seconds
        watcher.autoCollapse.delaySeconds = seconds
    }
}
