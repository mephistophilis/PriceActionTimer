//
//  TimerManager.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import Foundation
import Combine

@MainActor
final class TimerManager: ObservableObject {
    enum Phase {
        case idle
        case running
        case warning
    }

    @Published private(set) var profile: TimerProfile
    @Published private(set) var remainingTime: TimeInterval
    @Published private(set) var phase: Phase = .idle

    var cycleDuration: TimeInterval { profile.cycleDuration }
    var warningLeadTime: TimeInterval { profile.warningLeadTime }

    private var warnedDeadline: Date?
    private let notify: (TimerWarning) -> Void

    init(profile: TimerProfile, notify: @escaping (TimerWarning) -> Void) {
        let profile = profile.normalized()
        self.profile = profile
        self.remainingTime = profile.cycleDuration
        self.notify = notify
    }

    func apply(profile: TimerProfile) {
        let profile = profile.normalized()
        guard self.profile != profile else { return }
        self.profile = profile
    }

    /// Recompute from wall time so edits, delayed ticks and wake-ups cannot retain a stale deadline.
    func update(at date: Date) {
        let schedule = TimerSchedule(profile: profile)
        guard let window = schedule.activeWindow(at: date) else {
            stop()
            return
        }

        let deadline = schedule.cycleDeadline(at: date, in: window)
        remainingTime = deadline.timeIntervalSince(date)
        let isWarning = remainingTime <= warningLeadTime
        // A warning withdrawn before its threshold can be requested at the new threshold.
        if !isWarning, warnedDeadline == deadline { warnedDeadline = nil }
        let nextPhase: Phase = isWarning ? .warning : .running
        if phase != nextPhase { phase = nextPhase }

        if isWarning, warnedDeadline != deadline {
            warnedDeadline = deadline
            notify(TimerWarning(profileID: profile.id, duration: formattedCycleLength(), remaining: formatted(seconds: ceil(remainingTime))))
        }
    }

    func stop() {
        if phase != .idle { phase = .idle }
        if remainingTime != cycleDuration { remainingTime = cycleDuration }
        warnedDeadline = nil
    }

    func formattedRemainingTime() -> String {
        formatted(seconds: remainingTime)
    }

    func compactLabel() -> String {
        let seconds = Int(max(remainingTime, 0))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func formattedCycleLength() -> String {
        formatted(seconds: cycleDuration)
    }

    func formattedWarningLength() -> String {
        "\(Int(warningLeadTime))s"
    }

    var statusText: String {
        switch phase {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .warning:
            return "⚠️ Ending soon"
        }
    }

    func formatted(seconds: TimeInterval) -> String {
        let rounded = Int(max(seconds, 0))
        let minutes = rounded / 60
        let secs = rounded % 60
        if minutes == 0 {
            return "\(secs)s"
        }
        if secs == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(secs)s"
    }
}
