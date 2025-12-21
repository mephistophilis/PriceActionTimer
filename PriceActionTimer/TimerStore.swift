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
    private let storageURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = base?.appendingPathComponent("PriceActionTimer", isDirectory: true)
        let url = dir?.appendingPathComponent("profiles.json")
        return url ?? URL(fileURLWithPath: "/tmp/PriceActionTimer-profiles.json")
    }()
    var selectedProfile: TimerProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID && $0.isEnabled })
    }
    var hasEnabledProfile: Bool {
        profiles.contains(where: { $0.isEnabled })
    }

    init(profiles: [TimerProfile]? = nil) {
        let initialProfiles = profiles ?? Self.loadProfiles(from: storageURL) ?? [TimerProfile.initial]
        self.profiles = initialProfiles.map {
            var copy = $0
            copy.autoRestart = true
            return copy
        }
        self.selectedProfileID = initialProfiles.first(where: { $0.isEnabled })?.id
        syncManagersWithProfiles()
        refreshSelectionAfterChange()
        // Don't call start() here - syncManagersWithProfiles already started the managers
    }

    func addProfile() {
        let profile = TimerProfile(
            cycleDuration: 60,
            warningLeadTime: 10,
            autoRestart: true,
            isEnabled: true,
            watchStart: DateComponents(hour: 9, minute: 30),
            watchEnd: DateComponents(hour: 16, minute: 0)
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

    func start() {
        ensureSelection()
        syncManagersWithProfiles()
        objectWillChange.send()
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
    }

    private func ensureSelection() {
        if selectedProfile == nil {
            selectedProfileID = profiles.first(where: { $0.isEnabled })?.id
        }
    }

    func manager(for id: UUID?) -> TimerManager? {
        guard let id else { return nil }
        if let existing = managers[id] { return existing }
        let manager = TimerManager()
        managers[id] = manager

        // Set up subscription for the new manager
        managerSubscriptions[id] = manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        return manager
    }

    private func syncManagersWithProfiles() {
        let ids = Set(profiles.map(\.id))
        let stale = managers.keys.filter { !ids.contains($0) }
        stale.forEach { managers[$0] = nil }
        stale.forEach { managerSubscriptions[$0] = nil }

        var needsRefresh = false
        for profile in profiles {
            let manager = manager(for: profile.id) ?? TimerManager()
            managers[profile.id] = manager
            manager.apply(profile: profile)

            if profile.isEnabled {
                manager.start()
            } else {
                manager.stop()
            }
            needsRefresh = true

            managerSubscriptions[profile.id] = manager.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        if needsRefresh {
            objectWillChange.send()
        }
    }

    private func saveProfiles() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }

    private static func loadProfiles(from url: URL) -> [TimerProfile]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([TimerProfile].self, from: data)
    }
}
