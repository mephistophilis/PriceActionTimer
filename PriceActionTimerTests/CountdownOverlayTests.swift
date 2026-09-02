import AppKit
import Foundation
import Testing
@testable import PriceActionTimer

@MainActor
struct CountdownOverlayTests {
    @Test func warningCountdownAppearsUpdatesAndDisappearsAtNextCycle() async throws {
        let fixture = OverlayFixture(at: "2026-09-02T09:30:49Z")
        defer { fixture.close() }
        #expect(fixture.overlay.entries.isEmpty)

        fixture.clock.date = date("2026-09-02T09:30:50Z")
        fixture.store.refresh()
        try await settle()
        #expect(fixture.overlay.entries.first?.seconds == 10)
        fixture.clock.date = date("2026-09-02T09:30:51Z")
        fixture.store.refresh()
        try await settle()
        #expect(fixture.overlay.entries.first?.seconds == 9)
        fixture.clock.date = date("2026-09-02T09:31:00Z")
        fixture.store.refresh()
        try await settle()
        #expect(fixture.overlay.entries.isEmpty)
    }

    @Test func overlayUsesConfiguredWarningTimeAndRoundsSecondsUp() async throws {
        let profile = TimerProfile(cycleDuration: 60, warningLeadTime: 20, timezoneIdentifier: "UTC")
        let fixture = OverlayFixture(at: "2026-09-02T09:30:40Z", profiles: [profile])
        defer { fixture.close() }
        try await settle()
        #expect(fixture.overlay.entries.first?.seconds == 20)
        fixture.clock.date.addTimeInterval(0.25)
        fixture.store.refresh()
        fixture.overlay.refresh()
        #expect(fixture.overlay.entries.first?.seconds == 20)
    }

    @Test func disablingOverlayAndStoppingStoreHideTheCountdown() async throws {
        let fixture = OverlayFixture()
        defer { fixture.close() }
        try await settle()
        #expect(fixture.overlay.entries.count == 1)
        fixture.settings.isEnabled = false
        try await settle()
        #expect(fixture.overlay.entries.isEmpty)
        fixture.settings.isEnabled = true
        try await settle()
        #expect(fixture.overlay.entries.count == 1)
        fixture.store.stop()
        try await settle()
        #expect(fixture.overlay.entries.isEmpty)
    }

    @Test func multipleWarningsTrackProfileDeletionAndNewTimers() async throws {
        let first = TimerProfile(cycleDuration: 60, warningLeadTime: 10, timezoneIdentifier: "UTC")
        let second = TimerProfile(cycleDuration: 120, warningLeadTime: 70, timezoneIdentifier: "UTC")
        let fixture = OverlayFixture(profiles: [first, second])
        defer { fixture.close() }
        try await settle()
        #expect(fixture.overlay.entries.map(\.id) == [first.id.uuidString, second.id.uuidString])
        fixture.store.removeProfiles(at: IndexSet(integer: 0))
        try await settle()
        #expect(fixture.overlay.entries.map(\.id) == [second.id.uuidString])

        fixture.store.addProfile()
        var added = try #require(fixture.store.profiles.last)
        added.timezoneIdentifier = "UTC"
        fixture.store.updateProfile(added)
        try await settle()
        #expect(fixture.overlay.entries.map(\.id) == [second.id.uuidString, added.id.uuidString])
        fixture.clock.date = date("2026-09-02T09:30:51Z")
        fixture.store.refresh()
        try await settle()
        #expect(fixture.overlay.entries.last?.seconds == 9)
    }

    @Test func previewExpiresAndYieldsToRealWarnings() {
        let fixture = OverlayFixture(at: "2026-09-02T09:30:40Z")
        defer { fixture.close() }
        fixture.overlay.preview()
        #expect(fixture.overlay.entries.first?.id == "preview")
        #expect(fixture.overlay.entries.first?.seconds == 10)
        fixture.clock.date = date("2026-09-02T09:30:49Z")
        fixture.overlay.refresh()
        #expect(fixture.overlay.entries.first?.seconds == 1)
        fixture.clock.date = date("2026-09-02T09:30:50Z")
        fixture.overlay.refresh()
        #expect(fixture.overlay.entries.isEmpty)
        fixture.store.refresh()
        fixture.overlay.preview()
        #expect(fixture.overlay.entries.first?.id == fixture.store.profiles[0].id.uuidString)
        #expect(fixture.overlay.entries.first?.seconds == 10)
    }

    @Test(arguments: CountdownCorner.allCases)
    func cornerPlacementRespectsScreenOriginAndVisibleArea(corner: CountdownCorner) {
        let visible = CGRect(x: -1600, y: 40, width: 1600, height: 860)
        let size = CGSize(width: 264, height: 120)
        let frame = CountdownOverlayController.frame(for: size, in: visible, corner: corner)
        #expect(visible.contains(frame))
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        #expect(left ? frame.minX == visible.minX + 24 : frame.maxX == visible.maxX - 24)
        #expect(top ? frame.maxY == visible.maxY - 24 : frame.minY == visible.minY + 24)
    }

    @Test func desktopPanelIsTransparentClickThroughAndMovesLive() async throws {
        let fixture = OverlayFixture(presentsWindows: true)
        defer { fixture.close() }
        #expect(!NSApp.windows.contains { $0.title == "Desktop countdown" && $0.isVisible })
        try await settle()
        let panel = try #require(NSApp.windows.first { $0.title == "Desktop countdown" && $0.isVisible })
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor.alphaComponent == 0)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.isKeyWindow)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        let screen = try #require(NSScreen.screens.first)
        for corner in CountdownCorner.allCases {
            fixture.settings.corner = corner
            try await settle()
            #expect(panel.frame == CountdownOverlayController.frame(for: panel.frame.size, in: screen.visibleFrame, corner: corner))
        }
        fixture.settings.isEnabled = false
        try await settle()
        #expect(!panel.isVisible)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(30))
    }
}

@MainActor
private final class OverlayFixture {
    let suiteName = "CountdownOverlayTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: CountdownOverlaySettings
    let store: TimerStore
    let overlay: CountdownOverlayController
    let clock: OverlayClock

    init(at value: String = "2026-09-02T09:30:50Z", profiles: [TimerProfile]? = nil, presentsWindows: Bool = false) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = CountdownOverlaySettings(userDefaults: defaults)
        let clock = OverlayClock(date: ISO8601DateFormatter().date(from: value)!)
        self.clock = clock
        store = TimerStore(
            profiles: profiles ?? [TimerProfile(cycleDuration: 60, warningLeadTime: 10, timezoneIdentifier: "UTC")],
            storage: TimerProfileStorage(userDefaults: defaults, legacyFileURL: nil),
            now: { clock.date },
            notifications: TimerNotificationAggregator(deliver: { _ in }),
            automaticallySchedules: false
        )
        overlay = CountdownOverlayController(timerStore: store, settings: settings, presentsWindows: presentsWindows, now: { clock.date })
    }

    func close() {
        overlay.stop()
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class OverlayClock {
    var date: Date
    init(date: Date) { self.date = date }
}
