import Foundation
import UserNotifications

struct TimerWarning {
    let profileID: UUID
    let duration: String
    let remaining: String
}

@MainActor
final class TimerNotificationAggregator {
    private var pending: [UUID: TimerWarning] = [:]
    private var sendTask: Task<Void, Never>?
    private let deliver: (UNNotificationRequest) -> Void

    init(deliver: @escaping (UNNotificationRequest) -> Void = { request in
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification error: \(error.localizedDescription)")
            }
        }
    }) {
        self.deliver = deliver
    }

    func enqueue(_ warning: TimerWarning) {
        pending[warning.profileID] = warning
        guard sendTask == nil else { return }
        sendTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.sendCombined()
        }
    }

    func cancel(for profileID: UUID) {
        pending[profileID] = nil
        if pending.isEmpty { cancelAll() }
    }

    func cancelAll() {
        sendTask?.cancel()
        sendTask = nil
        pending.removeAll()
    }

    private func sendCombined() {
        let notifications = Array(pending.values)
        pending.removeAll()
        sendTask = nil
        guard !notifications.isEmpty else { return }

        let content = UNMutableNotificationContent()
        if notifications.count == 1, let first = notifications.first {
            content.title = "Timer ending soon"
            content.body = "\(first.duration) cycle - \(first.remaining) left"
        } else {
            content.title = "Timers ending soon"
            content.body = notifications.map { "\($0.duration) (\($0.remaining))" }.joined(separator: ", ")
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        deliver(request)
    }

    deinit {
        sendTask?.cancel()
    }
}
