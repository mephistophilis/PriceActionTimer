//
//  TimerProfile.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import Foundation

struct TimerProfile: Identifiable, Equatable, Codable {
    let id: UUID
    var cycleDuration: TimeInterval
    var warningLeadTime: TimeInterval
    var isEnabled: Bool
    var watchStart: DateComponents
    var watchEnd: DateComponents
    var enabledWeekdays: Set<Int> // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    var timezoneIdentifier: String // Timezone identifier, e.g., "America/New_York"

    var timezone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? .current
    }

    init(
        id: UUID = UUID(),
        cycleDuration: TimeInterval,
        warningLeadTime: TimeInterval,
        isEnabled: Bool = true,
        watchStart: DateComponents = DateComponents(hour: 9, minute: 30),
        watchEnd: DateComponents = DateComponents(hour: 16, minute: 0),
        enabledWeekdays: Set<Int> = [2, 3, 4, 5, 6], // Mon-Fri by default
        timezoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.cycleDuration = cycleDuration
        self.warningLeadTime = warningLeadTime
        self.isEnabled = isEnabled
        self.watchStart = watchStart
        self.watchEnd = watchEnd
        self.enabledWeekdays = enabledWeekdays
        self.timezoneIdentifier = timezoneIdentifier
    }

    static let initial = TimerProfile(
        cycleDuration: 60,
        warningLeadTime: 10,
        isEnabled: true,
        watchStart: DateComponents(hour: 9, minute: 30),
        watchEnd: DateComponents(hour: 16, minute: 0),
        enabledWeekdays: [2, 3, 4, 5, 6], // Mon-Fri
        timezoneIdentifier: TimeZone.current.identifier
    )

    func normalized() -> TimerProfile {
        var profile = self
        profile.cycleDuration = cycleDuration.isFinite ? min(max(60, cycleDuration), 86400) : 60
        profile.warningLeadTime = warningLeadTime.isFinite ? min(max(3, warningLeadTime), profile.cycleDuration) : 10
        return profile
    }

    func timeRangeDescription(calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.timeZone = timezone

        guard let startDate = cal.date(from: watchStart),
              let endDate = cal.date(from: watchEnd) else {
            return "No window set"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timezone

        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        // Show timezone abbreviation if not local
        if timezone.identifier != TimeZone.current.identifier {
            let tzAbbr = timezone.abbreviation() ?? timezone.identifier
            return "Open \(startStr) · Close \(endStr) (\(tzAbbr))"
        }

        return "Open \(startStr) · Close \(endStr)"
    }

    func generatedName(calendar: Calendar = .current) -> String {
        let timeRange = timeRangeDescription(calendar: calendar)
        let minutes = Int(cycleDuration) / 60
        let seconds = Int(cycleDuration) % 60
        let cycle: String
        if minutes > 0 && seconds > 0 {
            cycle = "\(minutes)m\(seconds)s"
        } else if minutes > 0 {
            cycle = "\(minutes)m"
        } else {
            cycle = "\(seconds)s"
        }
        return "\(cycle) · Warn \(Int(warningLeadTime))s · \(timeRange)"
    }
}
