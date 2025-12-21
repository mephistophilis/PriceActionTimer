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
    var autoRestart: Bool
    var isEnabled: Bool
    var watchStart: DateComponents
    var watchEnd: DateComponents

    init(
        id: UUID = UUID(),
        cycleDuration: TimeInterval,
        warningLeadTime: TimeInterval,
        autoRestart: Bool,
        isEnabled: Bool = true,
        watchStart: DateComponents = DateComponents(hour: 9, minute: 30),
        watchEnd: DateComponents = DateComponents(hour: 16, minute: 0)
    ) {
        self.id = id
        self.cycleDuration = cycleDuration
        self.warningLeadTime = warningLeadTime
        self.autoRestart = autoRestart
        self.isEnabled = isEnabled
        self.watchStart = watchStart
        self.watchEnd = watchEnd
    }

    static let initial = TimerProfile(
        cycleDuration: 60,
        warningLeadTime: 10,
        autoRestart: true,
        isEnabled: true,
        watchStart: DateComponents(hour: 9, minute: 30),
        watchEnd: DateComponents(hour: 16, minute: 0)
    )

    func timeRangeDescription(calendar: Calendar = .current) -> String {
        guard let startDate = calendar.date(from: watchStart),
              let endDate = calendar.date(from: watchEnd) else {
            return "No window set"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return "Open \(formatter.string(from: startDate)) · Close \(formatter.string(from: endDate))"
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
