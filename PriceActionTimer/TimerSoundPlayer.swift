import Foundation
import AppKit

struct TimerWarning {
    enum Kind: Equatable {
        case initial
        case finalSeconds
    }

    static let finalSecondsThreshold: TimeInterval = 5

    let profileID: UUID
    let duration: String
    let remaining: String
    let kind: Kind

    init(profileID: UUID, duration: String, remaining: String, kind: Kind = .initial) {
        self.profileID = profileID
        self.duration = duration
        self.remaining = remaining
        self.kind = kind
    }
}

@MainActor
final class TimerSoundPlayer {
    private var pending: [UUID: TimerWarning.Kind] = [:]
    private var playTask: Task<Void, Never>?
    private let playSound: (TimerWarning.Kind) -> Void

    init(playSound: @escaping (TimerWarning.Kind) -> Void = { kind in
        let name = kind == .finalSeconds ? "Ping" : "Glass"
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }) {
        self.playSound = playSound
    }

    func enqueue(_ warning: TimerWarning) {
        pending[warning.profileID] = warning.kind
        guard playTask == nil else { return }
        playTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.playPending()
        }
    }

    func cancel(for profileID: UUID) {
        pending[profileID] = nil
        if pending.isEmpty { cancelAll() }
    }

    func cancelAll() {
        playTask?.cancel()
        playTask = nil
        pending.removeAll()
    }

    private func playPending() {
        let hasWarnings = !pending.isEmpty
        let kind: TimerWarning.Kind = pending.values.contains(.finalSeconds) ? .finalSeconds : .initial
        pending.removeAll()
        playTask = nil
        guard hasWarnings else { return }
        playSound(kind)
    }

    deinit {
        playTask?.cancel()
    }
}
