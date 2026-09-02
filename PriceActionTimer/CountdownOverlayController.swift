import AppKit
import Combine
import SwiftUI

@MainActor
final class CountdownOverlayController: ObservableObject {
    let settings: CountdownOverlaySettings
    private(set) var entries: [CountdownOverlayEntry] = []

    private let timerStore: TimerStore
    private let presentsWindows: Bool
    private let now: () -> Date
    private var panel: CountdownPanel?
    private var subscriptions: [AnyCancellable] = []
    private var timerSubscriptions: [UUID: AnyCancellable] = [:]
    private var refreshQueued = false
    private var isStopped = false
    private var previewDeadline: Date?
    private var previewTimer: DispatchSourceTimer?
    private var renderedEntries: [CountdownOverlayEntry] = []
    private var renderedHiddenCount = 0

    init(
        timerStore: TimerStore,
        settings: CountdownOverlaySettings,
        presentsWindows: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.timerStore = timerStore
        self.settings = settings
        self.presentsWindows = presentsWindows
        self.now = now

        subscriptions = [
            timerStore.objectWillChange.sink { [weak self] _ in self?.queueRefresh() },
            settings.objectWillChange.sink { [weak self] _ in self?.queueRefresh() },
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.queueRefresh() }
        ]
        // StateObject can initialize during a SwiftUI graph update; create windows on the next turn.
        queueRefresh()
    }

    func preview() {
        guard !isStopped, settings.isEnabled else { return }
        previewDeadline = now().addingTimeInterval(10)
        previewTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.refresh() }
        previewTimer = timer
        timer.resume()
        refresh()
    }

    func stop() {
        isStopped = true
        previewTimer?.cancel()
        previewTimer = nil
        subscriptions.removeAll()
        timerSubscriptions.removeAll()
        entries = []
        panel?.orderOut(nil)
        panel = nil
    }

    private func queueRefresh() {
        guard !refreshQueued, !isStopped else { return }
        refreshQueued = true
        // ObservableObject publishes before mutation; coalesce updates and read the completed state.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.refresh()
        }
    }

    func refresh() {
        guard !isStopped else { return }
        syncTimerSubscriptions()
        var updated: [CountdownOverlayEntry] = []
        if settings.isEnabled {
            updated = timerStore.profiles.compactMap { profile in
                guard profile.isEnabled,
                      let manager = timerStore.manager(for: profile.id),
                      manager.phase == .warning, manager.remainingTime > 0 else { return nil }
                return CountdownOverlayEntry(
                    id: profile.id.uuidString,
                    title: manager.formattedCycleLength(),
                    seconds: Int(ceil(manager.remainingTime))
                )
            }
        }

        if let deadline = previewDeadline {
            let remaining = Int(ceil(deadline.timeIntervalSince(now())))
            if remaining <= 0 || !settings.isEnabled {
                previewDeadline = nil
                previewTimer?.cancel()
                previewTimer = nil
            } else if updated.isEmpty {
                let cycle = timerStore.manager(for: timerStore.selectedProfileID)?.formattedCycleLength() ?? "1m"
                updated = [CountdownOverlayEntry(id: "preview", title: cycle, seconds: remaining)]
            }
        }

        entries = updated
        guard presentsWindows else { return }
        guard !entries.isEmpty, let screen = NSScreen.screens.first else {
            panel?.orderOut(nil)
            return
        }

        let panel = panel ?? makePanel()
        let availableHeight = screen.visibleFrame.height - 48
        var maximumRows = max(1, Int((availableHeight - 2 * CountdownOverlayView.inset + CountdownOverlayView.spacing)
            / (CountdownOverlayView.rowHeight + CountdownOverlayView.spacing)))
        if entries.count > maximumRows {
            maximumRows = max(1, Int((availableHeight - 2 * CountdownOverlayView.inset - CountdownOverlayView.summaryHeight)
                / (CountdownOverlayView.rowHeight + CountdownOverlayView.spacing)))
        }
        let visibleEntries = Array(entries.prefix(maximumRows))
        let hiddenCount = entries.count - visibleEntries.count
        if renderedEntries != visibleEntries || renderedHiddenCount != hiddenCount || panel.contentView == nil {
            let view = CountdownOverlayView(entries: visibleEntries, hiddenCount: hiddenCount)
            if let hostingView = panel.contentView as? NSHostingView<CountdownOverlayView> {
                hostingView.rootView = view
            } else {
                panel.contentView = NSHostingView(rootView: view)
            }
            renderedEntries = visibleEntries
            renderedHiddenCount = hiddenCount
        }
        let size = CGSize(
            width: CountdownOverlayView.width + 2 * CountdownOverlayView.inset,
            height: CGFloat(visibleEntries.count) * CountdownOverlayView.rowHeight
                + CGFloat(visibleEntries.count - 1) * CountdownOverlayView.spacing + 2 * CountdownOverlayView.inset
                + (hiddenCount > 0 ? CountdownOverlayView.summaryHeight + CountdownOverlayView.spacing : 0)
        )
        let frame = Self.frame(for: size, in: screen.visibleFrame, corner: settings.corner)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    static func frame(for size: CGSize, in visibleFrame: CGRect, corner: CountdownCorner) -> CGRect {
        let margin: CGFloat = 24
        let isLeft = corner == .topLeft || corner == .bottomLeft
        let isTop = corner == .topLeft || corner == .topRight
        return CGRect(
            x: isLeft ? visibleFrame.minX + margin : visibleFrame.maxX - size.width - margin,
            y: isTop ? visibleFrame.maxY - size.height - margin : visibleFrame.minY + margin,
            width: size.width,
            height: size.height
        )
    }

    private func syncTimerSubscriptions() {
        let ids = Set(timerStore.profiles.map(\.id))
        for id in timerSubscriptions.keys.filter({ !ids.contains($0) }) {
            timerSubscriptions[id] = nil
        }
        for profile in timerStore.profiles where timerSubscriptions[profile.id] == nil {
            guard let manager = timerStore.manager(for: profile.id) else { continue }
            timerSubscriptions[profile.id] = manager.objectWillChange.sink { [weak self] _ in self?.queueRefresh() }
        }
    }

    private func makePanel() -> CountdownPanel {
        let panel = CountdownPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.title = "Desktop countdown"
        self.panel = panel
        return panel
    }

    deinit {
        previewTimer?.cancel()
    }
}

private final class CountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
