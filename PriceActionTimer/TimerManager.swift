//
//  TimerManager.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import Foundation
import SwiftUI
import Combine
import UserNotifications
#if os(macOS)
import AppKit
#endif

@MainActor
final class TimerManager: ObservableObject {
    enum Phase {
        case idle
        case running
        case warning
    }

    @Published var cycleDuration: TimeInterval = 60 {
        didSet {
            if cycleDuration < 15 {
                cycleDuration = 15
            }
            if phase == .idle {
                remainingTime = cycleDuration
            }
        }
    }

    @Published var warningLeadTime: TimeInterval = 10 {
        didSet {
            if warningLeadTime < 3 {
                warningLeadTime = 3
            }
            if warningLeadTime > cycleDuration {
                warningLeadTime = max(3, cycleDuration / 2)
            }
        }
    }

    @Published var autoRestart = true
    @Published private(set) var remainingTime: TimeInterval = 60
    @Published private(set) var phase: Phase = .idle
    private var profileName: String = "Timer"
    private var enabledWeekdays: Set<Int> = [2, 3, 4, 5, 6] // Mon-Fri default

    private var timer: DispatchSourceTimer?
    private var deadline: Date?
    private var warned = false
    private var marketStart: Date?
    private var marketEnd: Date?
    private var watchStart = DateComponents(hour: 9, minute: 30)
    private var watchEnd = DateComponents(hour: 16, minute: 0)
    private var timezone: TimeZone = .current
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = timezone
        return cal
    }

    func apply(profile: TimerProfile) {
        cycleDuration = max(15, profile.cycleDuration)
        warningLeadTime = min(max(3, profile.warningLeadTime), cycleDuration)
        autoRestart = true
        watchStart = profile.watchStart
        watchEnd = profile.watchEnd
        profileName = profile.generatedName()
        enabledWeekdays = profile.enabledWeekdays
        timezone = profile.timezone

        // Don't stop - let syncManagersWithProfiles handle start/stop
    }

    func start() {
        // Don't restart if already running
        if phase != .idle {
            return
        }

        warned = false
        let now = Date()
        let window = currentWindow(from: now)
        let nextDeadline = nextCycleDeadline(from: now, window: window)
        deadline = nextDeadline
        marketStart = window.start
        marketEnd = window.end
        remainingTime = max(0, nextDeadline.timeIntervalSince(now))
        phase = .running
        configureTimerIfNeeded()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        phase = .idle
        warned = false
        deadline = nil
        remainingTime = cycleDuration
        marketStart = nil
        marketEnd = nil
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

    private func configureTimerIfNeeded() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        source.schedule(deadline: .now(), repeating: .milliseconds(250))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.resume()
    }

    private func tick() {
        guard let deadline else {
            stop()
            return
        }

        let now = Date()

        // Check if current weekday is enabled
        let weekday = calendar.component(.weekday, from: now)
        if !enabledWeekdays.contains(weekday) {
            stop()
            remainingTime = cycleDuration
            return
        }

        // Check if outside market hours
        if let marketEnd, now >= marketEnd {
            stop()
            remainingTime = 0
            return
        }

        let interval = deadline.timeIntervalSinceNow
        remainingTime = max(0, interval)

        if interval <= warningLeadTime, !warned {
            warned = true
            phase = .warning
            let remaining = formattedWarningLength()
            notifyUser(title: "Timer ending soon", duration: formattedCycleLength(), remaining: remaining)
        }

        if interval <= 0 {
            warned = false
            if autoRestart {
                let window = currentWindow(from: now)
                self.marketEnd = window.end
                self.deadline = nextCycleDeadline(from: now, window: window)
                remainingTime = max(0, self.deadline?.timeIntervalSince(now) ?? cycleDuration)
                phase = .running
            } else {
                stop()
            }
        } else if phase == .warning && interval > warningLeadTime {
            phase = .running
        }
    }

    private func currentWindow(from date: Date) -> (start: Date, end: Date) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var startComponents = components
        startComponents.hour = watchStart.hour
        startComponents.minute = watchStart.minute
        var endComponents = components
        endComponents.hour = watchEnd.hour
        endComponents.minute = watchEnd.minute

        guard let startToday = calendar.date(from: startComponents),
              let endToday = calendar.date(from: endComponents) else {
            let now = Date()
            return (now, now.addingTimeInterval(cycleDuration))
        }

        if date < startToday {
            return (startToday, endToday)
        }
        if date < endToday {
            return (startToday, endToday)
        }

        // Move to next day
        guard let nextStart = calendar.date(byAdding: .day, value: 1, to: startToday),
              let nextEnd = calendar.date(byAdding: .day, value: 1, to: endToday) else {
            return (startToday, endToday)
        }
        return (nextStart, nextEnd)
    }

    private func nextCycleDeadline(from now: Date, window: (start: Date, end: Date)) -> Date {
        if now < window.start {
            return window.start
        }

        let elapsed = now.timeIntervalSince(window.start)
        let cyclesElapsed = floor(elapsed / cycleDuration) + 1
        let nextBoundary = window.start.addingTimeInterval(cyclesElapsed * cycleDuration)

        if nextBoundary >= window.end {
            let nextWindow = currentWindow(from: calendar.date(byAdding: .day, value: 1, to: window.start) ?? now)
            return nextWindow.start
        }

        return nextBoundary
    }

    private func notifyUser(title: String, duration: String, remaining: String) {
        TimerNotificationAggregator.shared.enqueue(title: title, duration: duration, remaining: remaining)
    }
}

private final class TimerNotificationAggregator {
    static let shared = TimerNotificationAggregator()
    private var pending: [(title: String, duration: String, remaining: String)] = []
    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "timer.notification.aggregator", qos: .userInitiated)

    func enqueue(title: String, duration: String, remaining: String) {
        queue.async {
            self.pending.append((title, duration, remaining))
            self.scheduleSend()
        }
    }

    private func scheduleSend() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.sendCombined()
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func sendCombined() {
        let notifications = pending
        pending.removeAll()
        guard !notifications.isEmpty else { return }

        let content = UNMutableNotificationContent()

        if notifications.count == 1, let first = notifications.first {
            content.title = first.title
            content.body = "\(first.duration) cycle - \(first.remaining) left"
        } else {
            // Multiple timers: group by remaining time
            let items = notifications.map { "\($0.duration) (\($0.remaining))" }.joined(separator: ", ")
            content.title = "Timers ending soon"
            content.body = items
        }

        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification error: \(error.localizedDescription)")
            } else {
                print("✅ Notification sent successfully")
            }
        }
    }
}
