import SwiftUI
import StackbarCore

/// What the onboarding window shows: the page and the live permission state.
@MainActor
@Observable
final class OnboardingModel {
    var step = OnboardingStep.welcome
    var permissions = PermissionState.current
    /// The welcome page's checkbox: register Stackbar as a login item when leaving it.
    var opensAtLogin = true
    /// macOS runs this copy from a temporary location (App Translocation): it was opened where it
    /// was downloaded or copied without Finder. Updates can't install there.
    var isTranslocated = false
    @ObservationIgnored var onWelcomeDone: (_ opensAtLogin: Bool) -> Void = { _ in }
    @ObservationIgnored var onRelaunch: () -> Void = {}
    @ObservationIgnored var onFinish: (_ openSettings: Bool) -> Void = { _ in }

    /// The next page that still needs the user (granted permissions are skipped), or finish.
    func next() {
        // A translocated copy is about to be moved (the welcome page says so): registering it as a
        // login item would register the temporary copy. Not done: the welcome page shows again after
        // the move unless setup finishes here (then Settings → General has Open at Login).
        if step == .welcome, !isTranslocated { onWelcomeDone(opensAtLogin) }
        if let next = OnboardingStep.next(after: step, permissions: permissions) {
            step = next
        } else {
            onFinish(true)
        }
    }
}

/// First run (docs/PLAN.md, Decisions → First run): what Stackbar does and Open at Login, then
/// Accessibility, then Screen Recording. Pages whose permission is granted are skipped.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.step {
            case .welcome:
                page(
                    symbol: "rectangle.stack",
                    title: "Welcome to Stackbar",
                    text: "Stackbar keeps the menu bar items you rarely use in a dropdown under its icon, "
                        + "and gets back the ones lost behind the notch. It needs two permissions first."
                )
                if model.isTranslocated {
                    Label(
                        "macOS runs this copy of Stackbar from a temporary location, so it can't update itself. "
                            + "Quit it, drag Stackbar into Applications in Finder and open it from there.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Open Stackbar at login", isOn: $model.opensAtLogin)
                footer { Button("Continue") { model.next() }.keyboardShortcut(.defaultAction) }
            case .accessibility:
                page(
                    symbol: "accessibility",
                    title: "Accessibility",
                    text: "Lets Stackbar see which app owns each menu bar item, open their menus from the "
                        + "dropdown and move items for you. Turn Stackbar on in System Settings → "
                        + "Privacy & Security → Accessibility; macOS's question and the button below both take you there."
                )
                // macOS's own question comes with the page; the button below goes to System Settings.
                .onAppear { PermissionState.promptAccessibility() }
                status(model.permissions.accessibility)
                footer {
                    if !model.permissions.accessibility {
                        Button("Open System Settings") { PermissionState.openAccessibilitySettings() }
                    }
                    Button("Continue") { model.next() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.permissions.accessibility)
                }
            case .screenRecording:
                page(
                    symbol: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    text: "Lets Stackbar show images of the items in the dropdown and tell items of the same "
                        + "app apart. Stackbar only captures menu bar items. macOS may ask you to quit and "
                        + "reopen Stackbar after turning it on; setup continues here afterwards. Once a month "
                        + "macOS asks whether Stackbar may \u{201C}bypass the system private window picker\u{201D}: "
                        + "allow it to keep the images up to date."
                )
                status(model.permissions.screenRecording)
                if model.permissions.screenRecording {
                    Text("All set. Open Settings and drag the items you want out of sight into the Dropdown "
                        + "list. Click the Stackbar icon to open the dropdown; right-click it for Settings.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                footer {
                    if model.permissions.screenRecording {
                        Button("Done") { model.onFinish(false) }
                        Button("Open Settings") { model.onFinish(true) }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Relaunch Stackbar") { model.onRelaunch() }
                        Button("Open System Settings") { PermissionState.requestScreenRecording(alertIfGranted: false) }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .topLeading)
    }

    private func page(symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Color.accentColor)
            Text(title).font(.title2.bold())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func status(_ granted: Bool) -> some View {
        Label(granted ? "Granted" : "Not granted yet", systemImage: granted ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(granted ? Color.green : Color.secondary)
    }

    private func footer(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack {
            Text("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            buttons()
        }
    }
}
