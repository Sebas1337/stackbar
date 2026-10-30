import SwiftUI
import StackbarCore

/// What the onboarding window shows: the step and the live permission state.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, accessibility, screenRecording, done
    }

    var step = Step.welcome
    var permissions = PermissionState.current
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onRelaunch: () -> Void = {}
    @ObservationIgnored var onFinish: () -> Void = {}

    func next() {
        step = Step(rawValue: step.rawValue + 1) ?? .done
    }
}

/// First run (docs/PLAN.md M4): what Stackbar does, the two permissions, how to assign items.
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
                footer { Button("Continue") { model.next() }.keyboardShortcut(.defaultAction) }
            case .accessibility:
                page(
                    symbol: "accessibility",
                    title: "Accessibility",
                    text: "Lets Stackbar see which app owns each menu bar item, open their menus from the "
                        + "dropdown and move items for you. Turn Stackbar on in System Settings → "
                        + "Privacy & Security → Accessibility."
                )
                status(model.permissions.accessibility)
                footer {
                    if !model.permissions.accessibility {
                        Button("Open System Settings") { PermissionState.requestAccessibility(alertIfGranted: false) }
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
                        + "reopen Stackbar after turning it on, and asks again now and then whether "
                        + "Stackbar may keep capturing."
                )
                status(model.permissions.screenRecording)
                footer {
                    if !model.permissions.screenRecording {
                        Button("Relaunch Stackbar") { model.onRelaunch() }
                        Button("Open System Settings") { PermissionState.requestScreenRecording(alertIfGranted: false) }
                    }
                    Button("Continue") { model.next() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.permissions.screenRecording)
                }
            case .done:
                page(
                    symbol: "checkmark.circle",
                    title: "All set",
                    text: "Open Settings and drag the items you want out of sight into the Dropdown list. "
                        + "Click the Stackbar icon to open the dropdown; right-click it for Settings."
                )
                footer {
                    Button("Open Settings") {
                        model.onFinish()
                        model.onOpenSettings()
                    }
                    Button("Done") { model.onFinish() }.keyboardShortcut(.defaultAction)
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
            Text("Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            buttons()
        }
    }
}
