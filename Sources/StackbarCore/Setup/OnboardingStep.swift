/// The pages of first-run setup (docs/PLAN.md, Decisions → First run), in order: welcome with
/// Open at Login, then Accessibility, then Screen Recording.
///
/// A permission page is skipped while its permission is granted, and setup resumes where it
/// stopped: turning on Screen Recording often needs a relaunch (or macOS relaunches Stackbar
/// itself), after which only what is still missing is shown. With nothing missing setup finishes
/// without a window.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, accessibility, screenRecording

    /// The page to show when setup (re)starts, nil when nothing is left to do.
    /// `welcomeDone`: the user got past the welcome page before (`StackbarConfig`).
    public static func first(welcomeDone: Bool, permissions: PermissionInfo) -> OnboardingStep? {
        welcomeDone ? next(after: .welcome, permissions: permissions) : .welcome
    }

    /// The page after `step`, skipping granted permissions; nil when setup is done.
    public static func next(after step: OnboardingStep, permissions: PermissionInfo) -> OnboardingStep? {
        allCases.first { $0.rawValue > step.rawValue && !$0.isDone(permissions) }
    }

    private func isDone(_ permissions: PermissionInfo) -> Bool {
        switch self {
        case .welcome: false
        case .accessibility: permissions.accessibility
        case .screenRecording: permissions.screenRecording
        }
    }
}
