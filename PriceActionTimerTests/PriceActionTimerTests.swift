import Foundation
import Testing
@testable import PriceActionTimer

@MainActor
struct PriceActionTimerTests {
    @Test func finalCycleEndsAtCloseAndWarnsBeforeClose() {
        let profile = makeProfile(cycle: 86400)
        var warnings: [TimerWarning] = []
        let manager = TimerManager(profile: profile, notify: { warnings.append($0) })

        manager.update(at: date("2026-09-02T15:59:55Z"))
        #expect(manager.remainingTime == 5)
        #expect(manager.phase == .warning)
        #expect(warnings.count == 1)
        #expect(warnings.first?.remaining == "5s")
        #expect(warnings.first?.kind == .finalSeconds)

        manager.update(at: date("2026-09-02T16:00:00Z"))
        #expect(manager.phase == .idle)
        #expect(warnings.count == 1)
    }

    @Test func partialFinalCycleIsTruncatedAtClose() {
        var profile = makeProfile(cycle: 300)
        profile.watchEnd = DateComponents(hour: 16, minute: 2)
        let manager = TimerManager(profile: profile, notify: { _ in })
        manager.update(at: date("2026-09-02T16:01:00Z"))
        #expect(manager.remainingTime == 60)
    }

    @Test func changingCycleImmediatelyRealignsDeadline() {
        var profile = makeProfile(cycle: 300)
        let manager = TimerManager(profile: profile, notify: { _ in })
        let now = date("2026-09-02T09:32:20Z")
        manager.update(at: now)
        #expect(manager.remainingTime == 160)

        profile.cycleDuration = 60
        manager.apply(profile: profile)
        manager.update(at: now)
        #expect(manager.cycleDuration == 60)
        #expect(manager.remainingTime == 40)
    }

    @Test func changingOpenTimeRealignsCycleAnchor() {
        var profile = makeProfile(cycle: 300)
        let manager = TimerManager(profile: profile, notify: { _ in })
        let now = date("2026-09-02T09:32:20Z")
        manager.update(at: now)
        profile.watchStart = DateComponents(hour: 9, minute: 31)
        manager.apply(profile: profile)
        manager.update(at: now)
        #expect(manager.remainingTime == 220)
    }

    @Test func warningIsEmittedOncePerDeadline() {
        let profile = makeProfile()
        var warnings: [TimerWarning] = []
        let manager = TimerManager(profile: profile, notify: { warnings.append($0) })
        manager.update(at: date("2026-09-02T09:30:50Z"))
        manager.apply(profile: profile)
        manager.update(at: date("2026-09-02T09:30:51Z"))
        #expect(warnings.count == 1)
        #expect(warnings.first?.kind == .initial)
        var edited = profile
        edited.warningLeadTime = 11
        manager.apply(profile: edited)
        manager.update(at: date("2026-09-02T09:30:52Z"))
        #expect(warnings.count == 1)
        manager.update(at: date("2026-09-02T09:31:00Z"))
        #expect(manager.remainingTime == 60)
        #expect(manager.phase == .running)
        #expect(warnings.count == 1)
        manager.update(at: date("2026-09-02T09:31:50Z"))
        #expect(warnings.count == 2)
        #expect(warnings.last?.kind == .initial)
    }

    @Test func warningMovesFromInitialToFinalSecondsOncePerDeadline() {
        let profile = makeProfile()
        var warnings: [TimerWarning] = []
        let manager = TimerManager(profile: profile, notify: { warnings.append($0) })

        manager.update(at: date("2026-09-02T09:30:50Z"))
        #expect(manager.remainingTime == 10)
        #expect(warnings.map(\.kind) == [.initial])

        manager.update(at: date("2026-09-02T09:30:54Z").addingTimeInterval(0.5))
        #expect(manager.remainingTime > 5)
        #expect(warnings.map(\.kind) == [.initial])

        manager.update(at: date("2026-09-02T09:30:55Z"))
        #expect(manager.remainingTime == 5)
        #expect(warnings.map(\.kind) == [.initial, .finalSeconds])

        for offset in [0.2, 0.8, 2.9, 4.9] {
            manager.update(at: date("2026-09-02T09:30:55Z").addingTimeInterval(offset))
        }
        var edited = profile
        edited.warningLeadTime = 20
        manager.apply(profile: edited)
        manager.update(at: date("2026-09-02T09:30:59Z").addingTimeInterval(0.9))
        #expect(warnings.map(\.kind) == [.initial, .finalSeconds])

        manager.update(at: date("2026-09-02T09:31:00Z"))
        #expect(manager.phase == .running)
        manager.update(at: date("2026-09-02T09:31:50Z"))
        manager.update(at: date("2026-09-02T09:31:55Z"))
        #expect(warnings.map(\.kind) == [.initial, .finalSeconds, .initial, .finalSeconds])
    }

    @Test func startingInsideFinalSecondsEmitsOnlyFinalWarning() {
        var warnings: [TimerWarning] = []
        let manager = TimerManager(profile: makeProfile(), notify: { warnings.append($0) })

        manager.update(at: date("2026-09-02T09:30:57Z"))

        #expect(manager.phase == .warning)
        #expect(warnings.map(\.kind) == [.finalSeconds])
        manager.update(at: date("2026-09-02T09:30:58Z"))
        #expect(warnings.map(\.kind) == [.finalSeconds])
    }

    @Test func shortWarningLeadStillEntersWarningAtFiveSeconds() {
        var profile = makeProfile()
        profile.warningLeadTime = 3
        var warnings: [TimerWarning] = []
        let manager = TimerManager(profile: profile, notify: { warnings.append($0) })

        manager.update(at: date("2026-09-02T09:30:54Z"))
        #expect(manager.remainingTime == 6)
        #expect(manager.phase == .running)
        #expect(warnings.isEmpty)

        manager.update(at: date("2026-09-02T09:30:55Z"))
        #expect(manager.phase == .warning)
        #expect(warnings.map(\.kind) == [.finalSeconds])
        manager.update(at: date("2026-09-02T09:30:56Z"))
        #expect(warnings.map(\.kind) == [.finalSeconds])
        manager.update(at: date("2026-09-02T09:30:57Z"))
        #expect(warnings.map(\.kind) == [.finalSeconds])
    }

    @Test func delayedTicksSkipExpiredWarnings() {
        var warnings: [TimerWarning] = []
        let manager = TimerManager(profile: makeProfile(), notify: { warnings.append($0) })
        manager.update(at: date("2026-09-02T09:30:49Z"))
        manager.update(at: date("2026-09-02T09:34:01Z"))
        #expect(manager.remainingTime == 59)
        #expect(manager.phase == .running)
        #expect(warnings.isEmpty)
        manager.update(at: date("2026-09-02T09:34:51Z"))
        #expect(warnings.count == 1)
        #expect(warnings.first?.remaining == "9s")
        #expect(warnings.first?.kind == .initial)
    }

    @Test func timezoneAndEnabledWeekdaysUseTheProfileCalendar() {
        var profile = makeProfile()
        profile.timezoneIdentifier = "America/New_York"
        let manager = TimerManager(profile: profile, notify: { _ in })
        manager.update(at: date("2026-09-02T13:30:00Z"))
        #expect(manager.phase == .running)
        #expect(manager.remainingTime == 60)
        manager.update(at: date("2026-09-05T13:30:00Z"))
        #expect(manager.phase == .idle)
    }

    @Test func nextStartIncludesTheSameWeekdayNextWeek() {
        var profile = makeProfile()
        profile.enabledWeekdays = [4]
        let next = TimerSchedule(profile: profile).nextStart(after: date("2026-09-02T16:00:00Z"))
        #expect(next == date("2026-09-09T09:30:00Z"))
    }

    @Test func nextStartPreservesLocalOpeningTimeAcrossDaylightSaving() {
        var profile = makeProfile()
        profile.timezoneIdentifier = "America/New_York"
        let next = TimerSchedule(profile: profile).nextStart(after: date("2026-03-06T21:00:00Z"))
        #expect(next == date("2026-03-09T13:30:00Z"))
    }

    @Test func invalidOrDisabledWindowsHaveNoScheduledStart() {
        var profile = makeProfile()
        let now = date("2026-09-02T09:30:00Z")
        profile.watchEnd = profile.watchStart
        #expect(TimerSchedule(profile: profile).nextStart(after: now) == nil)
        #expect(TimerSchedule(profile: profile).activeWindow(at: now) == nil)
        profile.watchEnd = DateComponents(hour: 8, minute: 0)
        #expect(TimerSchedule(profile: profile).nextStart(after: now) == nil)
        profile = makeProfile()
        profile.enabledWeekdays = []
        #expect(TimerSchedule(profile: profile).nextStart(after: now) == nil)
        profile = makeProfile()
        profile.isEnabled = false
        #expect(TimerSchedule(profile: profile).nextStart(after: now) == nil)
    }

    @Test func profileNormalizationKeepsRuntimeAndStoredValuesConsistent() {
        var profile = makeProfile(cycle: 1)
        profile.warningLeadTime = 500
        let normalized = profile.normalized()
        #expect(normalized.cycleDuration == 60)
        #expect(normalized.warningLeadTime == 60)
        profile.cycleDuration = .infinity
        profile.warningLeadTime = .nan
        #expect(profile.normalized().cycleDuration == 60)
        #expect(profile.normalized().warningLeadTime == 10)
    }

    private func makeProfile(cycle: TimeInterval = 60) -> TimerProfile {
        TimerProfile(cycleDuration: cycle, warningLeadTime: 10, timezoneIdentifier: "UTC")
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
