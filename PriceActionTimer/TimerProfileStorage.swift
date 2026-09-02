//
//  TimerProfileStorage.swift
//  PriceActionTimer
//

import Foundation

@MainActor
final class TimerProfileStorage {
    private let userDefaults: UserDefaults
    private let legacyFileURL: URL?

    private let profilesKey = "com.m.PriceActionTimer.profiles"
    private let selectedProfileKey = "com.m.PriceActionTimer.selectedProfile"
    private let migrationKey = "com.m.PriceActionTimer.migratedFromFile"

    init(
        userDefaults: UserDefaults = .standard,
        legacyFileURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PriceActionTimer", isDirectory: true)
            .appendingPathComponent("profiles.json")
    ) {
        self.userDefaults = userDefaults
        self.legacyFileURL = legacyFileURL
    }

    func loadProfiles() -> [TimerProfile]? {
        migrateFromFileStorageIfNeeded()

        guard let data = userDefaults.data(forKey: profilesKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode([TimerProfile].self, from: data)
        } catch {
            print("Failed to load profiles: \(error)")
            return nil
        }
    }

    func saveProfiles(_ profiles: [TimerProfile]) {
        do {
            let data = try JSONEncoder().encode(profiles)
            userDefaults.set(data, forKey: profilesKey)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }

    var selectedProfileID: UUID? {
        get {
            guard let value = userDefaults.string(forKey: selectedProfileKey) else {
                return nil
            }
            return UUID(uuidString: value)
        }
        set {
            if let newValue {
                userDefaults.set(newValue.uuidString, forKey: selectedProfileKey)
            } else {
                userDefaults.removeObject(forKey: selectedProfileKey)
            }
        }
    }

    private func migrateFromFileStorageIfNeeded() {
        guard let legacyFileURL,
              !userDefaults.bool(forKey: migrationKey),
              userDefaults.data(forKey: profilesKey) == nil else {
            return
        }

        do {
            let data = try Data(contentsOf: legacyFileURL)
            let profiles = try JSONDecoder().decode([TimerProfile].self, from: data)
            let encodedData = try JSONEncoder().encode(profiles)
            userDefaults.set(encodedData, forKey: profilesKey)
            print("Migrated \(profiles.count) profiles from file storage to UserDefaults")
        } catch {
            print("Failed to migrate profiles from file storage: \(error)")
        }

        userDefaults.set(true, forKey: migrationKey)
    }
}
