import Combine
import Foundation
import Testing
@testable import PriceActionTimer

@MainActor
struct TimerStoreTests {
    @Test(arguments: [true, false])
    func cloningPreservesSettingsWithAnIndependentIdentity(isEnabled: Bool) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        var source = fixture.store.profiles[0]
        source.cycleDuration = 900
        source.warningLeadTime = 30
        source.isEnabled = isEnabled
        source.watchStart = DateComponents(hour: 8, minute: 15)
        source.watchEnd = DateComponents(hour: 17, minute: 45)
        source.enabledWeekdays = [2, 4, 6]
        source.timezoneIdentifier = "America/New_York"
        fixture.store.updateProfile(source)
        let originalManager = try #require(fixture.store.manager(for: source.id))

        let cloneID = try #require(fixture.store.cloneProfile(source.id))
        var clone = try #require(fixture.store.profiles.first { $0.id == cloneID })
        #expect(cloneID != source.id)
        #expect(fixture.store.profiles.count == 2)
        #expect(clone.cycleDuration == source.cycleDuration)
        #expect(clone.warningLeadTime == source.warningLeadTime)
        #expect(clone.isEnabled == source.isEnabled)
        #expect(clone.watchStart == source.watchStart)
        #expect(clone.watchEnd == source.watchEnd)
        #expect(clone.enabledWeekdays == source.enabledWeekdays)
        #expect(clone.timezoneIdentifier == source.timezoneIdentifier)
        #expect(fixture.storage.loadProfiles() == [source, clone])
        let clonedManager = try #require(fixture.store.manager(for: cloneID))
        #expect(clonedManager !== originalManager)
        #expect(clonedManager.profile == clone)
        if isEnabled {
            #expect(fixture.store.selectedProfileID == cloneID)
            #expect(fixture.storage.selectedProfileID == cloneID)
        }

        clone.cycleDuration = 300
        clone.enabledWeekdays.insert(3)
        fixture.store.updateProfile(clone)
        #expect(fixture.store.profiles.first == source)
        #expect(originalManager.profile == source)
        #expect(clonedManager.profile == clone)
        #expect(fixture.storage.loadProfiles() == [source, clone])

        fixture.store.removeProfiles(at: IndexSet(integer: 1))
        #expect(fixture.store.profiles == [source])
        #expect(fixture.store.manager(for: source.id) === originalManager)
        #expect(fixture.store.manager(for: cloneID) == nil)
    }

    @Test func cloningAMissingTimerLeavesProfilesAndSelectionUnchanged() {
        let fixture = Fixture()
        defer { fixture.close() }
        let profiles = fixture.store.profiles
        let selection = fixture.store.selectedProfileID
        let savedProfiles = fixture.storage.loadProfiles()
        #expect(fixture.store.cloneProfile(UUID()) == nil)
        #expect(fixture.store.profiles == profiles)
        #expect(fixture.store.selectedProfileID == selection)
        #expect(fixture.storage.loadProfiles() == savedProfiles)
    }

    @Test func profileEditsPersistAndUpdateTheExistingManager() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let original = fixture.store.profiles[0]
        let manager = try #require(fixture.store.manager(for: original.id))
        var edited = original
        edited.cycleDuration = 300
        fixture.store.updateProfile(edited)
        #expect(fixture.store.manager(for: original.id) === manager)
        #expect(manager.remainingTime == 160)
        #expect(fixture.storage.loadProfiles() == [edited])

        edited.cycleDuration = 1
        edited.warningLeadTime = 500
        fixture.store.updateProfile(edited)
        #expect(fixture.store.profiles[0].cycleDuration == manager.cycleDuration)
        #expect(fixture.store.profiles[0].warningLeadTime == manager.warningLeadTime)
        #expect(fixture.storage.loadProfiles() == fixture.store.profiles)
    }

    @Test func disablingAndDeletingProfilesUpdatesManagersAndSelection() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = fixture.store.profiles[0]
        fixture.store.addProfile()
        let second = fixture.store.profiles[1]
        fixture.store.selectedProfileID = first.id
        var disabled = first
        disabled.isEnabled = false
        fixture.store.updateProfile(disabled)
        #expect(fixture.store.manager(for: first.id)?.phase == .idle)
        #expect(fixture.store.selectedProfileID == second.id)
        #expect(fixture.storage.selectedProfileID == second.id)

        let removed = try #require(fixture.store.manager(for: second.id))
        fixture.store.removeProfiles(at: IndexSet(integer: 1))
        #expect(fixture.store.manager(for: second.id) == nil)
        #expect(removed.phase == .idle)
        #expect(fixture.store.selectedProfileID == nil)
        #expect(fixture.storage.selectedProfileID == nil)
        fixture.store.removeProfiles(at: IndexSet(integer: 0))
        #expect(fixture.store.profiles.isEmpty)
        fixture.store.updateProfile(second)
        #expect(fixture.store.profiles.isEmpty)
    }

    @Test func deletingLastTimerPersistsEmptyStateAndAllowsAddingAgain() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let profile = fixture.store.profiles[0]
        let manager = try #require(fixture.store.manager(for: profile.id))

        fixture.store.removeProfiles(at: IndexSet(integer: 0))
        #expect(fixture.store.profiles.isEmpty)
        #expect(fixture.store.manager(for: profile.id) == nil)
        #expect(manager.phase == .idle)
        #expect(fixture.store.selectedProfileID == nil)
        #expect(fixture.storage.loadProfiles() == [])

        let restored = TimerStore(storage: fixture.storage, soundPlayer: TimerSoundPlayer(playSound: { _ in }), automaticallySchedules: false)
        defer { restored.stop() }
        #expect(restored.profiles.isEmpty)
        restored.addProfile()
        #expect(restored.profiles.count == 1)
        #expect(restored.selectedProfileID == restored.profiles.first?.id)
    }

    @Test func deletingAllTimersDoesNotCreateAReplacement() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.store.addProfile()
        fixture.store.removeProfiles(at: IndexSet(integersIn: 0..<2))
        #expect(fixture.store.profiles.isEmpty)
        #expect(fixture.storage.loadProfiles() == [])
    }

    @Test func refreshRecoversIdleTimersAfterWakeAndStopsOutsideWindow() {
        let fixture = Fixture(at: "2026-09-02T09:00:00Z")
        defer { fixture.close() }
        let manager = fixture.store.manager(for: fixture.store.profiles[0].id)
        #expect(manager?.phase == .idle)
        fixture.clock.date = date("2026-09-02T09:32:20Z")
        fixture.store.refresh()
        #expect(manager?.phase == .running)
        #expect(manager?.remainingTime == 40)
        fixture.clock.date = date("2026-09-02T16:00:00Z")
        fixture.store.refresh()
        #expect(manager?.phase == .idle)
        fixture.clock.date = date("2026-09-03T09:32:20Z")
        fixture.store.refresh()
        #expect(manager?.remainingTime == 40)
    }

    @Test func stopPreventsRefreshFromRestartingTimers() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.store.stop()
        fixture.store.refresh()
        #expect(fixture.store.manager(for: fixture.store.profiles[0].id)?.phase == .idle)
    }

    @Test func schedulerStartsAtOpeningAndStaysStopped() async throws {
        let fixture = Fixture(at: "2026-09-02T09:29:59Z", automaticallySchedules: true)
        defer { fixture.close() }
        let manager = try #require(fixture.store.manager(for: fixture.store.profiles[0].id))
        #expect(manager.phase == .idle)

        fixture.clock.date = date("2026-09-02T09:30:10Z")
        try await Task.sleep(for: .milliseconds(1200))
        #expect(manager.phase == .running)
        #expect(manager.remainingTime == 50)

        fixture.store.stop()
        try await Task.sleep(for: .milliseconds(400))
        #expect(manager.phase == .idle)
    }

    @Test func selectionChangesDoNotRewriteProfiles() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.store.addProfile()
        let savedData = try #require(fixture.defaults.data(forKey: "com.m.PriceActionTimer.profiles"))
        fixture.store.selectedProfileID = fixture.store.profiles[0].id
        #expect(fixture.defaults.data(forKey: "com.m.PriceActionTimer.profiles") == savedData)
        #expect(fixture.storage.selectedProfileID == fixture.store.profiles[0].id)
    }

    @Test(arguments: ["stop", "disable", "delete"], ["2026-09-02T09:30:50Z", "2026-09-02T09:30:55Z"])
    func invalidatedTimersCancelPendingSounds(action: String, warningTime: String) async throws {
        var playCount = 0
        let soundPlayer = TimerSoundPlayer(playSound: { _ in playCount += 1 })
        let fixture = Fixture(at: warningTime, soundPlayer: soundPlayer)
        defer { fixture.close() }
        switch action {
        case "stop":
            fixture.store.stop()
        case "disable":
            var profile = fixture.store.profiles[0]
            profile.isEnabled = false
            fixture.store.updateProfile(profile)
        default:
            fixture.store.removeProfiles(at: IndexSet(integer: 0))
        }
        try await Task.sleep(for: .milliseconds(600))
        #expect(playCount == 0)
    }

    @Test func activeTimerPlaysOneSoundDuringWarning() async throws {
        var playedKinds: [TimerWarning.Kind] = []
        let soundPlayer = TimerSoundPlayer(playSound: { playedKinds.append($0) })
        let fixture = Fixture(at: "2026-09-02T09:30:50Z", soundPlayer: soundPlayer)
        defer { fixture.close() }
        fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.initial])
    }

    @Test func activeTimerPlaysFinalSecondsSoundOncePerCycle() async throws {
        var playedKinds: [TimerWarning.Kind] = []
        let soundPlayer = TimerSoundPlayer(playSound: { playedKinds.append($0) })
        let fixture = Fixture(at: "2026-09-02T09:30:50Z", soundPlayer: soundPlayer)
        defer { fixture.close() }

        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.initial])

        fixture.clock.date = date("2026-09-02T09:30:55Z")
        fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.initial, .finalSeconds])

        fixture.clock.date = date("2026-09-02T09:30:59Z")
        fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.initial, .finalSeconds])

        fixture.clock.date = date("2026-09-02T09:31:50Z")
        fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.initial, .finalSeconds, .initial])
    }

    @Test(arguments: [false, true])
    func simultaneousTimersPlayOneSoundPerCycle(deleteOneBeforePlayback: Bool) async throws {
        var playedKinds: [TimerWarning.Kind] = []
        let soundPlayer = TimerSoundPlayer(playSound: { playedKinds.append($0) })
        let fixture = Fixture(at: "2026-09-02T09:30:50Z", soundPlayer: soundPlayer)
        defer { fixture.close() }
        fixture.store.addProfile()
        var second = try #require(fixture.store.profiles.last)
        second.timezoneIdentifier = "UTC"
        fixture.store.updateProfile(second)
        for profile in fixture.store.profiles {
            #expect(fixture.store.manager(for: profile.id)?.phase == .warning)
        }
        if deleteOneBeforePlayback {
            fixture.store.removeProfiles(at: IndexSet(integer: 0))
        }
        fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.initial])

        fixture.clock.date = date("2026-09-02T09:31:50Z")
        fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.initial, .initial])
    }

    @Test func soundPlayerCoalescesSameBatchAndFavorsFinalSeconds() async throws {
        var playedKinds: [TimerWarning.Kind] = []
        let soundPlayer = TimerSoundPlayer(playSound: { playedKinds.append($0) })
        let firstID = UUID()
        let secondID = UUID()

        soundPlayer.enqueue(TimerWarning(profileID: firstID, duration: "1m", remaining: "10s", kind: .initial))
        soundPlayer.enqueue(TimerWarning(profileID: secondID, duration: "1m", remaining: "5s", kind: .finalSeconds))
        try await Task.sleep(for: .milliseconds(600))

        #expect(playedKinds == [.finalSeconds])
    }

    @Test func cancellingOneProfilePreservesOtherPendingSound() async throws {
        var playedKinds: [TimerWarning.Kind] = []
        let soundPlayer = TimerSoundPlayer(playSound: { playedKinds.append($0) })
        let cancelledID = UUID()
        let remainingID = UUID()

        soundPlayer.enqueue(TimerWarning(profileID: cancelledID, duration: "1m", remaining: "5s", kind: .finalSeconds))
        soundPlayer.enqueue(TimerWarning(profileID: remainingID, duration: "1m", remaining: "10s", kind: .initial))
        soundPlayer.cancel(for: cancelledID)
        try await Task.sleep(for: .milliseconds(600))

        #expect(playedKinds == [.initial])
    }

    @Test func shorteningWarningLeadCancelsOldWarningAndUsesNewThreshold() async throws {
        var playedKinds: [TimerWarning.Kind] = []
        let soundPlayer = TimerSoundPlayer(playSound: { playedKinds.append($0) })
        let fixture = Fixture(at: "2026-09-02T09:30:50Z", soundPlayer: soundPlayer)
        defer { fixture.close() }
        var profile = fixture.store.profiles[0]
        profile.warningLeadTime = 3
        fixture.store.updateProfile(profile)
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds.isEmpty)

        fixture.clock.date = date("2026-09-02T09:30:57Z")
        fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        #expect(playedKinds == [.finalSeconds])
    }

    @Test func countdownDoesNotInvalidateTheWholeStore() {
        let fixture = Fixture()
        defer { fixture.close() }
        var changes = 0
        let subscription = fixture.store.objectWillChange.sink { changes += 1 }
        fixture.clock.date = date("2026-09-02T09:32:21Z")
        fixture.store.refresh()
        #expect(changes == 0)
        fixture.clock.date = date("2026-09-02T09:32:50Z")
        fixture.store.refresh()
        #expect(changes == 1)
        withExtendedLifetime(subscription) {}
    }

    @Test func startupDoesNotOverwriteUndecodableProfiles() {
        let fixture = Fixture()
        defer { fixture.close() }
        let invalid = Data("not-json".utf8)
        fixture.defaults.set(invalid, forKey: "com.m.PriceActionTimer.profiles")
        let store = TimerStore(storage: fixture.storage, soundPlayer: TimerSoundPlayer(playSound: { _ in }), automaticallySchedules: false)
        defer { store.stop() }
        #expect(!store.profiles.isEmpty)
        #expect(fixture.defaults.data(forKey: "com.m.PriceActionTimer.profiles") == invalid)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

@MainActor
private final class Fixture {
    let suiteName = "TimerStoreTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let storage: TimerProfileStorage
    let store: TimerStore
    let clock: TestClock

    init(at value: String = "2026-09-02T09:32:20Z", automaticallySchedules: Bool = false, soundPlayer: TimerSoundPlayer? = nil) {
        defaults = UserDefaults(suiteName: suiteName)!
        storage = TimerProfileStorage(userDefaults: defaults, legacyFileURL: nil)
        let clock = TestClock(date: ISO8601DateFormatter().date(from: value)!)
        self.clock = clock
        let profile = TimerProfile(cycleDuration: 60, warningLeadTime: 10, timezoneIdentifier: "UTC")
        store = TimerStore(profiles: [profile], storage: storage, now: { clock.date }, soundPlayer: soundPlayer ?? TimerSoundPlayer(playSound: { _ in }), automaticallySchedules: automaticallySchedules)
    }

    func close() {
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class TestClock {
    var date: Date
    init(date: Date) { self.date = date }
}
