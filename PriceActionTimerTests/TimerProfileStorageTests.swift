//
//  TimerProfileStorageTests.swift
//  PriceActionTimerTests
//

import Foundation
import Testing
@testable import PriceActionTimer

@MainActor
struct TimerProfileStorageTests {
    @Test
    func roundTripsProfilesThroughUserDefaults() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TimerProfileStorage(userDefaults: defaults, legacyFileURL: nil)
        let profile = makeProfile(cycleDuration: 90)

        storage.saveProfiles([profile])

        #expect(storage.loadProfiles() == [profile])
    }

    @Test
    func clearingSelectionRemovesStoredValue() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TimerProfileStorage(userDefaults: defaults, legacyFileURL: nil)
        let id = UUID()

        storage.selectedProfileID = id
        #expect(storage.selectedProfileID == id)

        storage.selectedProfileID = nil

        #expect(storage.selectedProfileID == nil)
        #expect(defaults.object(forKey: "com.m.PriceActionTimer.selectedProfile") == nil)
    }

    @Test
    func importsProfilesFromLegacyFile() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PriceActionTimerStorageTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: legacyFileURL) }

        let profile = makeProfile(cycleDuration: 120)
        try JSONEncoder().encode([profile]).write(to: legacyFileURL)

        let storage = TimerProfileStorage(userDefaults: defaults, legacyFileURL: legacyFileURL)

        #expect(storage.loadProfiles() == [profile])
        #expect(defaults.data(forKey: "com.m.PriceActionTimer.profiles") != nil)
        #expect(defaults.bool(forKey: "com.m.PriceActionTimer.migratedFromFile"))
    }

    @Test
    func doesNotImportLegacyFileWhenUserDefaultsHasData() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PriceActionTimerStorageTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: legacyFileURL) }

        let existingProfile = makeProfile(cycleDuration: 180)
        let legacyProfile = makeProfile(cycleDuration: 240)
        let existingData = try JSONEncoder().encode([existingProfile])
        defaults.set(existingData, forKey: "com.m.PriceActionTimer.profiles")
        try JSONEncoder().encode([legacyProfile]).write(to: legacyFileURL)

        let storage = TimerProfileStorage(userDefaults: defaults, legacyFileURL: legacyFileURL)

        #expect(storage.loadProfiles() == [existingProfile])
        #expect(!defaults.bool(forKey: "com.m.PriceActionTimer.migratedFromFile"))
    }

    @Test
    func doesNotOverwriteUndecodableExistingData() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TimerProfileStorage(userDefaults: defaults, legacyFileURL: nil)
        let invalidData = Data("not-json".utf8)
        defaults.set(invalidData, forKey: "com.m.PriceActionTimer.profiles")

        #expect(storage.loadProfiles() == nil)
        #expect(defaults.data(forKey: "com.m.PriceActionTimer.profiles") == invalidData)
    }

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "TimerProfileStorageTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makeProfile(cycleDuration: TimeInterval) -> TimerProfile {
        TimerProfile(
            cycleDuration: cycleDuration,
            warningLeadTime: 15,
            watchStart: DateComponents(hour: 9, minute: 30),
            watchEnd: DateComponents(hour: 16, minute: 0),
            enabledWeekdays: [2, 3, 4, 5, 6],
            timezoneIdentifier: "UTC"
        )
    }
}
