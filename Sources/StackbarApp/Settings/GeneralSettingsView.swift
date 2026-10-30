import SwiftUI
import StackbarCore

/// Settings → General: Open at Login, the shortcut, auto-collapse and updates (docs/PLAN.md M5).
struct GeneralSettingsView: View {
    @Bindable var model: GeneralSettingsModel

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Open Stackbar at login", isOn: Binding(get: { model.opensAtLogin }, set: { model.onOpensAtLogin($0) }))
                if model.loginNeedsApproval {
                    HStack {
                        Text("Allow Stackbar in System Settings → General → Login Items.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Login Items") { model.onOpenLoginItems() }
                    }
                }
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            SwiftUI.Section {
                LabeledContent("Open the dropdown") {
                    HStack {
                        Button(shortcutTitle) {
                            model.isRecording ? model.stopRecording() : model.startRecording()
                        }
                        .frame(minWidth: 120)
                        if model.hotKey != nil, !model.isRecording {
                            Button("Clear") { model.onHotKey(nil) }
                        }
                    }
                }
                if let hint = model.recordingHint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                } else if model.isRecording {
                    Text("Press the shortcut. Esc cancels, Delete removes it.").font(.caption).foregroundStyle(.secondary)
                } else if model.hotKeyRefused {
                    Text("macOS refused this shortcut: another app or the system uses it. Pick another.")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Keyboard Shortcut")
            }
            SwiftUI.Section {
                Picker("Collapse the menu bar again", selection: Binding(get: { model.autoCollapseSeconds }, set: { model.onAutoCollapse($0) })) {
                    Text("Never").tag(Int?.none)
                    ForEach(AutoCollapse.choices, id: \.self) { seconds in
                        Text(Self.describe(seconds)).tag(Int?.some(seconds))
                    }
                }
                Text("Once the menu bar has been expanded this long (Show All Items) and you haven't used mouse or keyboard for 5 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Auto-Collapse")
            }
            SwiftUI.Section {
                Toggle("Check for updates automatically", isOn: Binding(get: { model.checksForUpdates }, set: { model.onChecksForUpdates($0) }))
                HStack {
                    Text(model.updateStatus ?? "Once a day, on GitHub Releases.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { model.onCheckNow() }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        // Switching to the Items tab ends a recording.
        .onDisappear { model.stopRecording() }
        .frame(minWidth: 560, minHeight: 380)
    }

    private var shortcutTitle: String {
        if model.isRecording { return "Recording…" }
        return model.hotKey?.displayString ?? "Record Shortcut"
    }

    private static func describe(_ seconds: Int) -> String {
        seconds < 60 ? "After \(seconds) seconds" : "After \(seconds / 60) minute\(seconds == 60 ? "" : "s")"
    }
}
