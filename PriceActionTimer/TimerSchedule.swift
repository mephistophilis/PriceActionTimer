import Foundation

/// The shared calendar rules for starting timers and aligning their cycles.
struct TimerSchedule {
    let profile: TimerProfile

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = profile.timezone
        return calendar
    }

    func activeWindow(at date: Date) -> DateInterval? {
        guard let window = window(on: date),
              date >= window.start, date < window.end else { return nil }
        return window
    }

    func nextStart(after date: Date) -> Date? {
        if activeWindow(at: date) != nil { return date }

        let today = calendar.startOfDay(for: date)
        // Include the same weekday next week when today's window has closed.
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let window = window(on: day), window.start > date else { continue }
            return window.start
        }
        return nil
    }

    func cycleDeadline(at date: Date, in window: DateInterval) -> Date {
        let elapsed = date.timeIntervalSince(window.start)
        let cycle = floor(elapsed / profile.cycleDuration) + 1
        return min(window.start.addingTimeInterval(cycle * profile.cycleDuration), window.end)
    }

    private func window(on date: Date) -> DateInterval? {
        guard profile.isEnabled,
              profile.enabledWeekdays.contains(calendar.component(.weekday, from: date)),
              let startHour = profile.watchStart.hour, let startMinute = profile.watchStart.minute,
              let endHour = profile.watchEnd.hour, let endMinute = profile.watchEnd.minute,
              (0...23).contains(startHour), (0...59).contains(startMinute),
              (0...23).contains(endHour), (0...59).contains(endMinute),
              startHour * 60 + startMinute < endHour * 60 + endMinute else { return nil }

        // Profiles describe a same-day window in their own timezone.
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = startHour
        components.minute = startMinute
        guard let start = calendar.date(from: components) else { return nil }
        components.hour = endHour
        components.minute = endMinute
        guard let end = calendar.date(from: components), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}
