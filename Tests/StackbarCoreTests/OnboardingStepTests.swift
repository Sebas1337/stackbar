import Testing
@testable import StackbarCore

struct OnboardingStepTests {
    private static let none = PermissionInfo(accessibility: false, screenRecording: false)
    private static let accessibility = PermissionInfo(accessibility: true, screenRecording: false)
    private static let both = PermissionInfo(accessibility: true, screenRecording: true)

    @Test func freshInstallStartsWithTheWelcomePage() {
        #expect(OnboardingStep.first(welcomeDone: false, permissions: Self.none) == .welcome)
        // Granted from an earlier install: the welcome page (Open at Login) still shows once.
        #expect(OnboardingStep.first(welcomeDone: false, permissions: Self.both) == .welcome)
    }

    @Test func goesThroughThePermissionsInOrder() {
        #expect(OnboardingStep.next(after: .welcome, permissions: Self.none) == .accessibility)
        #expect(OnboardingStep.next(after: .accessibility, permissions: Self.accessibility) == .screenRecording)
        #expect(OnboardingStep.next(after: .screenRecording, permissions: Self.both) == nil)
    }

    @Test func skipsGrantedPermissions() {
        #expect(OnboardingStep.next(after: .welcome, permissions: Self.accessibility) == .screenRecording)
        #expect(OnboardingStep.next(after: .welcome, permissions: Self.both) == nil)
        // Only Screen Recording granted (Accessibility missing): ask for Accessibility, then done.
        let screenOnly = PermissionInfo(accessibility: false, screenRecording: true)
        #expect(OnboardingStep.next(after: .welcome, permissions: screenOnly) == .accessibility)
        #expect(OnboardingStep.next(after: .accessibility, permissions: Self.both) == nil)
    }

    /// The Screen Recording relaunch: the welcome page and Accessibility were done before it.
    @Test func resumesAfterARelaunch() {
        #expect(OnboardingStep.first(welcomeDone: true, permissions: Self.both) == nil)
        #expect(OnboardingStep.first(welcomeDone: true, permissions: Self.accessibility) == .screenRecording)
        #expect(OnboardingStep.first(welcomeDone: true, permissions: Self.none) == .accessibility)
    }
}
