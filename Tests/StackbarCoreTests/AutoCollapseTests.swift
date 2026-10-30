import Foundation
import Testing
@testable import StackbarCore

struct AutoCollapseTests {
    static let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// Ticks at `seconds` after `start` (`#expect` can't call mutating members).
    static func tick(_ policy: inout AutoCollapse, _ seconds: Double, collapsed: Bool = false, idle: Double = 10, busy: Bool = false) -> Bool {
        policy.tick(now: start.addingTimeInterval(seconds), isCollapsed: collapsed, idleSeconds: idle, isBusy: busy)
    }

    @Test func collapsesOnceTheDelayHasPassed() {
        var policy = AutoCollapse(delaySeconds: 10)
        let first = Self.tick(&policy, 0)
        let early = Self.tick(&policy, 8)
        let due = Self.tick(&policy, 10)
        #expect(!first && !early && due)
        // Starts over: the next expand gets the full delay again.
        let afterwards = Self.tick(&policy, 12)
        #expect(!afterwards)
    }

    @Test func neverWithoutADelay() {
        var policy = AutoCollapse()
        _ = Self.tick(&policy, 0)
        let later = Self.tick(&policy, 1000)
        #expect(!later)
    }

    @Test func collapsingResetsTheTimer() {
        var policy = AutoCollapse(delaySeconds: 10)
        _ = Self.tick(&policy, 0)
        _ = Self.tick(&policy, 6, collapsed: true)
        _ = Self.tick(&policy, 8)
        let tooSoon = Self.tick(&policy, 12)
        let due = Self.tick(&policy, 18)
        #expect(!tooSoon && due)
    }

    @Test func waitsForTheUserAndForStackbar() {
        var policy = AutoCollapse(delaySeconds: 10)
        _ = Self.tick(&policy, 0)
        let active = Self.tick(&policy, 20, idle: 4)
        let busy = Self.tick(&policy, 22, busy: true)
        let idle = Self.tick(&policy, 24)
        #expect(!active && !busy && idle)
    }
}
