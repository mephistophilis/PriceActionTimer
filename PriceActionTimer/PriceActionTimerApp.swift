//
//  PriceActionTimerApp.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import SwiftUI

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
            Circle()
                .stroke(.secondary.opacity(0.55), lineWidth: 2)
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

    private var progressColor: Color {
        manager.phase == .warning ? .orange : .primary
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: remainingProgress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel("PriceAction Timer")
        .accessibilityValue(manager.phase == .idle ? "Idle" : manager.compactLabel())
    }
}

#if os(macOS)
import AppKit

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
