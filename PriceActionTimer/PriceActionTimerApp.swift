//
//  PriceActionTimerApp.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct PriceActionTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timerStore: TimerStore
    @StateObject private var countdownOverlay: CountdownOverlayController

    init() {
        let store = Self.isTesting ? TimerStore.preview : TimerStore()
        let defaults = Self.isTesting ? UserDefaults(suiteName: "com.m.PriceActionTimer.preview")! : .standard
        _timerStore = StateObject(wrappedValue: store)
        _countdownOverlay = StateObject(wrappedValue: CountdownOverlayController(
            timerStore: store,
            settings: CountdownOverlaySettings(userDefaults: defaults),
            presentsWindows: !Self.isTesting
        ))
    }

    var body: some Scene {
        let overlay = countdownOverlay
        MenuBarExtra {
            ContentView(timerStore: timerStore, displayMode: .menu)
                .padding()
                .frame(width: 280)
        } label: {
            MenuBarCountdownIcon(timerStore: timerStore)
        }

        WindowGroup {
            ContentView(timerStore: timerStore, displayMode: .main)
        }
        .windowResizability(.contentSize)

        #if os(macOS)
        Settings {
            SettingsView(timerStore: timerStore, overlaySettings: overlay.settings, previewCountdown: overlay.preview)
        }
        #endif
    }

    static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

private struct MenuBarCountdownIcon: View {
    @ObservedObject var timerStore: TimerStore

    var body: some View {
        if let profile = timerStore.selectedProfile,
           let manager = timerStore.manager(for: profile.id) {
            MenuBarCountdownRing(manager: manager)
        } else {
            Image(nsImage: MenuBarRingImage.make())
                .resizable()
                .renderingMode(.template)
                .frame(width: 16, height: 16)
                .accessibilityLabel("PriceAction Timer")
                .accessibilityValue("No enabled timer")
        }
    }
}

private struct MenuBarCountdownRing: View {
    @ObservedObject var manager: TimerManager

    private var remainingProgress: Double {
        guard manager.phase != .idle, manager.cycleDuration > 0 else { return 0 }
        return min(max(manager.remainingTime / manager.cycleDuration, 0), 1)
    }

    private var stage: MenuBarCountdownStage {
        guard manager.phase != .idle else { return .idle }
        if manager.remainingTime <= TimerWarning.finalSecondsThreshold { return .finalSeconds }
        if manager.phase == .warning { return .warning }
        return .running
    }

    var body: some View {
        Image(nsImage: MenuBarRingImage.make(
            progress: manager.phase == .idle ? nil : remainingProgress,
            color: stage.color
        ))
            .resizable()
            .renderingMode(.original)
            .frame(width: 16, height: 16)
            .accessibilityLabel("PriceAction Timer")
            .accessibilityValue(manager.phase == .idle ? "Idle" : "\(stage.label), \(manager.compactLabel())")
    }
}

private enum MenuBarCountdownStage {
    case idle
    case running
    case warning
    case finalSeconds

    var color: NSColor {
        switch self {
        case .idle: return .secondaryLabelColor
        case .running: return .systemGreen
        case .warning: return .systemOrange
        case .finalSeconds: return .systemRed
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .warning: return "Warning"
        case .finalSeconds: return "Final 5 seconds"
        }
    }
}

private enum MenuBarRingImage {
    @MainActor
    static func make(progress: Double? = nil, color: NSColor = .secondaryLabelColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let ringRect = NSRect(x: 2, y: 2, width: 12, height: 12)
            let background = NSBezierPath(ovalIn: ringRect)
            background.lineWidth = 2.75
            color.withAlphaComponent(progress == nil ? 0.8 : 0.42).setStroke()
            background.stroke()

            if let progress, progress > 0 {
                let arc = NSBezierPath()
                arc.lineWidth = 2.75
                arc.lineCapStyle = .round
                arc.appendArc(
                    withCenter: NSPoint(x: 8, y: 8),
                    radius: 6,
                    startAngle: 90,
                    endAngle: 90 - 360 * min(max(progress, 0), 1),
                    clockwise: true
                )
                color.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PriceActionTimerApp.isTesting else { return }
        // Check if another instance is already running
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if runningApps.count > 1 {
            // Another instance is running, activate it and terminate this one
            for app in runningApps where app != NSRunningApplication.current {
                app.activate()
            }
            NSApp.terminate(nil)
            return
        }
    }
}
#endif
