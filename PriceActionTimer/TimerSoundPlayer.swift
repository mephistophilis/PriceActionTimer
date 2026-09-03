import Foundation
import AppKit

struct TimerWarning {
    let profileID: UUID
    let duration: String
    let remaining: String
}

@MainActor
final class TimerSoundPlayer {
    private var pending: Set<UUID> = []
    private var playTask: Task<Void, Never>?
    private let playSound: () -> Void

    init(playSound: @escaping () -> Void = {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }) {
        self.playSound = playSound
    }

    func enqueue(_ warning: TimerWarning) {
        pending.insert(warning.profileID)
        guard playTask == nil else { return }
        playTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.playPending()
        }
    }

    func cancel(for profileID: UUID) {
        pending.remove(profileID)
        if pending.isEmpty { cancelAll() }
    }

    func cancelAll() {
        playTask?.cancel()
        playTask = nil
        pending.removeAll()
    }

    private func playPending() {
        let hasWarnings = !pending.isEmpty
        pending.removeAll()
        playTask = nil
        guard hasWarnings else { return }
        playSound()
    }

    deinit {
        playTask?.cancel()
    }
}
