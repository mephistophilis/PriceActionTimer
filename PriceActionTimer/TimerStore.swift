//
//  TimerStore.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class TimerStore: ObservableObject {
    @Published var profiles: [TimerProfile] {
        didSet {
            syncManagersWithProfiles()
            refreshSelectionAfterChange()
        }
    }
    @Published var selectedProfileID: UUID? {
        didSet {
            refreshSelectionAfterChange()
        }
    }

    private var managers: [UUID: TimerManager] = [:]
    private var managerSubscriptions: [UUID: AnyCancellable] = [:]
    private let userDefaults = UserDefaults.standard
    private let profilesKey = "com.m.PriceActionTimer.profiles"
    private let selectedProfileKey = "com.m.PriceActionTimer.selectedProfile"

    var selectedProfile: TimerProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID && $0.isEnabled })
    }
    var hasEnabledProfile: Bool {
        profiles.contains(where: { $0.isEnabled })
    }

    init(profiles: [TimerProfile]? = nil) {
        // Try to migrate from old file-based storage if needed
        Self.migrateFromFileStorageIfNeeded()

        let initialProfiles = profiles ?? Self.loadProfiles() ?? [TimerProfile.initial]
        self.profiles = initialProfiles

        // Load selected profile ID from UserDefaults
        if let savedID = userDefaults.string(forKey: selectedProfileKey),
           let uuid = UUID(uuidString: savedID) {
            self.selectedProfileID = uuid
        } else {
            self.selectedProfileID = initialProfiles.first(where: { $0.isEnabled })?.id
        }

        syncManagersWithProfiles()
        refreshSelectionAfterChange()
    }

    func addProfile() {
        let profile = TimerProfile(
            cycleDuration: 60,
            warningLeadTime: 10,
            isEnabled: true,
            watchStart: DateComponents(hour: 9, minute: 30),
            watchEnd: DateComponents(hour: 16, minute: 0),
            enabledWeekdays: [2, 3, 4, 5, 6], // Mon-Fri
            timezoneIdentifier: TimeZone.current.identifier
        )
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    func removeProfiles(at offsets: IndexSet) {
        guard profiles.count > 1 else { return }
        profiles.remove(atOffsets: offsets)
        if profiles.isEmpty {
            profiles = [TimerProfile.initial]
        }
        refreshSelectionAfterChange()
    }

    func stop() {
        managers.values.forEach { $0.stop() }
    }

    private func refreshSelectionAfterChange() {
        saveProfiles()
        if let currentSelection = selectedProfileID {
            if let current = profiles.first(where: { $0.id == currentSelection }) {
                if !current.isEnabled {
                    selectedProfileID = profiles.first(where: { $0.isEnabled })?.id
                    return
                }
            } else {
                selectedProfileID = profiles.first(where: { $0.isEnabled })?.id
                return
            }
        } else {
            selectedProfileID = profiles.first(where: { $0.isEnabled })?.id
        }

        // Save selected profile ID to UserDefaults
        if let selectedProfileID {
            userDefaults.set(selectedProfileID.uuidString, forKey: selectedProfileKey)
        } else {
            userDefaults.removeObject(forKey: selectedProfileKey)
        }
    }

    private func ensureSelection() {
        if selectedProfile == nil {
            selectedProfileID = profiles.first(where: { $0.isEnabled })?.id
        }
    }

    func manager(for id: UUID?) -> TimerManager? {
        guard let id else { return nil }
        return managers[id]
    }

    private func syncManagersWithProfiles() {
        let profileIDs = Set(profiles.map(\.id))

        // Remove managers for deleted profiles
        let staleIDs = managers.keys.filter { !profileIDs.contains($0) }
        for staleID in staleIDs {
            managers[staleID]?.stop()
            managers[staleID] = nil
            managerSubscriptions[staleID] = nil
        }

        // Create or update managers for each profile
        for profile in profiles {
            let manager: TimerManager

            if let existing = managers[profile.id] {
                // Manager already exists
                manager = existing
            } else {
                // Create new manager
                manager = TimerManager()
                managers[profile.id] = manager

                // Set up subscription once for new manager
                managerSubscriptions[profile.id] = manager.objectWillChange.sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
            }

            // Apply profile settings (only updates properties, doesn't restart)
            manager.apply(profile: profile)

            // Control manager state based on profile enabled state
            if profile.isEnabled {
                // Only start if idle (prevents restarting running timers)
                if manager.phase == .idle {
                    manager.start()
                }
            } else {
                // Stop if disabled
                manager.stop()
            }
        }

        objectWillChange.send()
    }

    private func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            userDefaults.set(data, forKey: profilesKey)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }

    private static func loadProfiles() -> [TimerProfile]? {
        guard let data = UserDefaults.standard.data(forKey: "com.m.PriceActionTimer.profiles") else {
            return nil
        }
        return try? JSONDecoder().decode([TimerProfile].self, from: data)
    }

    private static func migrateFromFileStorageIfNeeded() {
        let userDefaults = UserDefaults.standard
        let profilesKey = "com.m.PriceActionTimer.profiles"
        let migrationKey = "com.m.PriceActionTimer.migratedFromFile"

        // Skip if already migrated or data exists in UserDefaults
        if userDefaults.bool(forKey: migrationKey) || userDefaults.data(forKey: profilesKey) != nil {
            return
        }

        // Try to load from old file location
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = base?.appendingPathComponent("PriceActionTimer", isDirectory: true)
        guard let url = dir?.appendingPathComponent("profiles.json"),
              let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([TimerProfile].self, from: data) else {
            userDefaults.set(true, forKey: migrationKey)
            return
        }

        // Migrate to UserDefaults
        if let encodedData = try? JSONEncoder().encode(profiles) {
            userDefaults.set(encodedData, forKey: profilesKey)
            print("Migrated \(profiles.count) profiles from file storage to UserDefaults")
        }

        userDefaults.set(true, forKey: migrationKey)
    }
}
