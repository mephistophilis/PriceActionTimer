//
//  CountdownOverlaySettingsTests.swift
//  PriceActionTimerTests
//

import Foundation
import Testing
@testable import PriceActionTimer

@MainActor
struct CountdownOverlaySettingsTests {
    @Test
    func defaultsToEnabledBottomRight() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = CountdownOverlaySettings(userDefaults: defaults)

        #expect(settings.isEnabled)
        #expect(settings.corner == .bottomRight)
    }

    @Test
    func roundTripsDisabledAndCorner() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = CountdownOverlaySettings(userDefaults: defaults)
        settings.isEnabled = false
        settings.corner = .topLeft

        let restored = CountdownOverlaySettings(userDefaults: defaults)

        #expect(!restored.isEnabled)
        #expect(restored.corner == .topLeft)
    }

    @Test
    func invalidCornerFallsBackToBottomRight() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("center", forKey: "com.m.PriceActionTimer.overlay.corner")

        let settings = CountdownOverlaySettings(userDefaults: defaults)

        #expect(settings.corner == .bottomRight)
    }

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "CountdownOverlaySettingsTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
