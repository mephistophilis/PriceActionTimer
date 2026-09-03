//
//  TimerStore.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import Foundation
import Combine
import AppKit

@MainActor
final class TimerStore: ObservableObject {
    @Published private(set) var profiles: [TimerProfile]
    @Published var selectedProfileID: UUID? {
        didSet {
            refreshSelectionAfterChange()
        }
    }

    private var managers: [UUID: TimerManager] = [:]
    private var managerSubscriptions: [UUID: AnyCancellable] = [:]
    private var clockSubscriptions: [AnyCancellable] = []
    private var schedulerTimer: DispatchSourceTimer?
    private let storage: TimerProfileStorage
    private let now: () -> Date
    private let soundPlayer: TimerSoundPlayer
    private let automaticallySchedules: Bool
    private var isStopped = false

    var selectedProfile: TimerProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID && $0.isEnabled })
    }

    var hasEnabledProfile: Bool {
        profiles.contains(where: { $0.isEnabled })
    }

    init(
        profiles: [TimerProfile]? = nil,
        storage: TimerProfileStorage? = nil,
        now: @escaping () -> Date = Date.init,
        soundPlayer: TimerSoundPlayer? = nil,
        automaticallySchedules: Bool = true
    ) {
        let storage = storage ?? TimerProfileStorage()
        self.storage = storage
        self.now = now
        self.soundPlayer = soundPlayer ?? TimerSoundPlayer()
        self.automaticallySchedules = automaticallySchedules
        self.profiles = (profiles ?? storage.loadProfiles() ?? [.initial]).map { $0.normalized() }
        self.selectedProfileID = storage.selectedProfileID

        syncManagersWithProfiles()
        refreshSelectionAfterChange()
        if automaticallySchedules { observeClockChanges() }
        refresh()
    }

    func addProfile() {
        let profile = TimerProfile(cycleDuration: 60, warningLeadTime: 10)
        setProfiles(profiles + [profile])
        selectedProfileID = profile.id
    }

    func updateProfile(_ profile: TimerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profiles
        updated[index] = profile.normalized()
        setProfiles(updated)
    }

    func removeProfiles(at offsets: IndexSet) {
        let remaining = profiles.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        setProfiles(remaining)
    }

    private func setProfiles(_ updated: [TimerProfile]) {
        guard profiles != updated else { return }
        profiles = updated
        storage.saveProfiles(profiles)
        syncManagersWithProfiles()
        refreshSelectionAfterChange()
        refresh()
    }

    func manager(for id: UUID?) -> TimerManager? {
        guard let id else { return nil }
        return managers[id]
    }

    /// One clock sample drives every timer, including timers that were idle before a wake-up.
    func refresh() {
        guard !isStopped else { return }
        let date = now()
        for manager in managers.values {
            manager.update(at: date)
            if manager.phase != .warning { soundPlayer.cancel(for: manager.profile.id) }
        }
        scheduleNextRefresh(after: date)
    }

    /// Shut down this store's scheduler and pending sounds.
    func stop() {
        isStopped = true
        schedulerTimer?.cancel()
        schedulerTimer = nil
        clockSubscriptions.removeAll()
        soundPlayer.cancelAll()
        managers.values.forEach { $0.stop() }
    }

    private func refreshSelectionAfterChange() {
        let selection = selectedProfile?.id ?? profiles.first(where: { $0.isEnabled })?.id
        if selectedProfileID != selection {
            selectedProfileID = selection
            return
        }
        storage.selectedProfileID = selection
    }

    private func syncManagersWithProfiles() {
        let profileIDs = Set(profiles.map(\.id))
        let staleIDs = managers.keys.filter { !profileIDs.contains($0) }
        for id in staleIDs {
            soundPlayer.cancel(for: id)
            managers[id]?.stop()
            managers[id] = nil
            managerSubscriptions[id] = nil
        }

        for profile in profiles {
            if let manager = managers[profile.id] {
                manager.apply(profile: profile)
            } else {
                let manager = TimerManager(profile: profile, notify: soundPlayer.enqueue)
                managers[profile.id] = manager
                // Parent views need phase changes; countdown updates stay in each dashboard.
                managerSubscriptions[profile.id] = manager.$phase
                    .removeDuplicates()
                    .dropFirst()
                    .sink { [weak self] _ in self?.objectWillChange.send() }
            }
        }
    }

    private func scheduleNextRefresh(after date: Date) {
        schedulerTimer?.cancel()
        schedulerTimer = nil
        guard automaticallySchedules else { return }

        let delay: TimeInterval
        if managers.values.contains(where: { $0.phase != .idle }) {
            delay = 0.25
        } else if let nextStart = profiles.compactMap({ TimerSchedule(profile: $0).nextStart(after: date) }).min() {
            delay = max(0.01, nextStart.timeIntervalSince(date))
        } else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in self?.refresh() }
        schedulerTimer = timer
        timer.resume()
    }

    private func observeClockChanges() {
        let wake = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        let clock = NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
        let timezone = NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
        clockSubscriptions = [wake, clock, timezone].map { publisher in
            publisher.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
        }
    }

    static var preview: TimerStore {
        TimerStore(
            profiles: [.initial],
            storage: TimerProfileStorage(userDefaults: UserDefaults(suiteName: "com.m.PriceActionTimer.preview")!, legacyFileURL: nil),
            soundPlayer: TimerSoundPlayer(playSound: {}),
            automaticallySchedules: false
        )
    }

    deinit {
        schedulerTimer?.cancel()
    }
}
