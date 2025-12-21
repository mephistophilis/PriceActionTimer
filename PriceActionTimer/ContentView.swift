//
//  ContentView.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import SwiftUI

struct ContentView: View {
    enum DisplayMode {
        case main
        case menu
    }

    @ObservedObject private var timerStore: TimerStore
    private let displayMode: DisplayMode

    init(timerStore: TimerStore, displayMode: DisplayMode = .main) {
        _timerStore = ObservedObject(wrappedValue: timerStore)
        self.displayMode = displayMode
    }

    var body: some View {
        VStack(spacing: 16) {
            if displayMode == .main {
                if timerStore.selectedProfile != nil {
                    Picker("Select timer", selection: $timerStore.selectedProfileID) {
                        ForEach(timerStore.profiles) { profile in
                            Text(profile.generatedName()).tag(Optional(profile.id))
                        }
                    }
                    .pickerStyle(.menu)

                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(timerStore.profiles.filter { $0.isEnabled }) { profile in
                                if let dashManager = timerStore.manager(for: profile.id) {
                                    TimerDashboard(manager: dashManager, profileName: profile.generatedName())
                                        .padding()
                                        .background(.thickMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                } else {
                    Text("No available timer")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                let activeTimers = timerStore.profiles.compactMap { profile -> TimerProfile? in
                    guard profile.isEnabled else { return nil }
                    guard let mgr = timerStore.manager(for: profile.id) else { return nil }
                    guard mgr.phase != .idle else { return nil }
                    return profile
                }

                if activeTimers.isEmpty {
                    Text("No running timers")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Running timers (\(activeTimers.count))")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        ForEach(activeTimers, id: \.id) { profile in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                                Text(profile.generatedName())
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            #if os(macOS)
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.link)
            #endif

            #if os(macOS)
            if displayMode == .menu {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.link)
            }
            #endif
        }
        .padding()
        .frame(minWidth: 320)
    }
}

private struct TimerDashboard: View {
    @ObservedObject var manager: TimerManager
    var profileName: String

    private var progress: Double {
        guard manager.cycleDuration > 0 else { return 0 }
        let ratio = 1 - (manager.remainingTime / manager.cycleDuration)
        return min(max(ratio, 0), 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(manager.formattedRemainingTime())
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundStyle(manager.phase == .warning ? .orange : .primary)
                    .animation(.easeInOut(duration: 0.2), value: manager.phase)
                Text(manager.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)

            VStack(spacing: 8) {
                Label("Cycle \(manager.formattedCycleLength())", systemImage: "clock.arrow.2.circlepath")
                    .font(.callout)
                Label("Warn \(manager.formattedWarningLength()) before", systemImage: "bell")
                    .font(.callout)
            }
        }
    }
}

#Preview {
    ContentView(timerStore: TimerStore(), displayMode: .main)
}
