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
            Label("PriceAction", systemImage: "timer")
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
