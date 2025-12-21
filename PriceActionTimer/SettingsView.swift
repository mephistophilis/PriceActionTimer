//
//  SettingsView.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var timerStore: TimerStore
    @State private var selection: UUID?
    private let controlWidth: CGFloat = 220

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(timerStore.profiles) { profile in
                    SettingsListRow(profile: profile)
                        .tag(profile.id)
                }
                .onDelete(perform: timerStore.removeProfiles)
            }
            .frame(minWidth: 220)
            .navigationTitle("Timers")
            .toolbar {
                ToolbarItem {
                    Button {
                        let previousSelection = selection
                        timerStore.addProfile()
                        selection = timerStore.profiles.last?.id ?? previousSelection
                    } label: {
                        Label("New timer", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let binding = binding(for: selection) {
                detailEditor(for: binding)
            } else {
                VStack {
                    Text("Select a timer on the left to edit")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: timerStore.profiles) { _, _ in ensureSelection() }
        .frame(minWidth: 720, minHeight: 420)
    }

    private func format(seconds: TimeInterval) -> String {
        let rounded = Int(max(seconds, 0))
        let minutes = rounded / 60
        let secs = rounded % 60
        if minutes == 0 {
            return "\(secs)s"
        }
        return "\(minutes)m \(secs)s"
    }

    private func detailEditor(for profile: Binding<TimerProfile>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard(title: "Status", systemImage: "sparkles") {
                    SettingsRow(title: "Enabled") {
                        Toggle("", isOn: profile.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .frame(width: controlWidth, alignment: .trailing)
                    }
                    Divider().padding(.leading, 12)
                    SettingsRow(title: "Summary", subtitle: "Generated from your settings") {
                        Text(profile.wrappedValue.generatedName())
                            .font(.callout)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .frame(width: controlWidth, alignment: .trailing)
                    }
                }

                let presets: [TimeInterval] = [60, 180, 300, 900]
                SettingsCard(title: "Time", systemImage: "clock") {
                    SettingsRow(title: "Cycle") {
                        VStack(alignment: .trailing, spacing: 8) {
                            Picker("", selection: cycleSelection(for: profile, presets: presets)) {
                                ForEach(presets, id: \.self) { value in
                                    Text(formatPreset(value)).tag(tag(for: value))
                                }
                                Text("Custom").tag("custom")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: controlWidth, alignment: .trailing)

                            if cycleSelection(for: profile, presets: presets).wrappedValue == "custom" {
                                Stepper(value: Binding(
                                    get: { profile.wrappedValue.cycleDuration },
                                    set: { newValue in
                                        profile.wrappedValue.cycleDuration = max(15, newValue)
                                        profile.wrappedValue.warningLeadTime = min(profile.wrappedValue.warningLeadTime, profile.wrappedValue.cycleDuration)
                                    }
                                ), in: 15...3600, step: 15) {
                                    Text(format(seconds: profile.wrappedValue.cycleDuration))
                                }
                                .frame(width: controlWidth, alignment: .trailing)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Divider().padding(.leading, 12)
                    SettingsRow(title: "Warn before end") {
                        Stepper(value: Binding(
                            get: { profile.wrappedValue.warningLeadTime },
                            set: { newValue in
                            profile.wrappedValue.warningLeadTime = min(max(3, newValue), profile.wrappedValue.cycleDuration)
                        }
                    ), in: 3...300, step: 1) {
                        Text("\(Int(profile.wrappedValue.warningLeadTime))s")
                    }
                    .frame(width: controlWidth, alignment: .trailing)
                    }

                    Divider().padding(.leading, 12)
                    SettingsRow(title: "Open time") {
                        DatePicker(
                            "",
                            selection: dateBinding(for: profile.watchStart),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(width: controlWidth, alignment: .trailing)
                    }

                    Divider().padding(.leading, 12)
                    SettingsRow(title: "Close time") {
                        DatePicker(
                            "",
                            selection: dateBinding(for: profile.watchEnd),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(width: controlWidth, alignment: .trailing)
                    }
                }

                SettingsCard(title: "Danger", systemImage: "exclamationmark.triangle") {
                    SettingsRow(title: "Delete timer") {
                        Button(role: .destructive) {
                            deleteCurrent(profileID: profile.wrappedValue.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(timerStore.profiles.count <= 1)
                        .frame(width: controlWidth, alignment: .trailing)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Settings")
    }

    private func binding(for id: UUID?) -> Binding<TimerProfile>? {
        guard let id,
              let index = timerStore.profiles.firstIndex(where: { $0.id == id }) else { return nil }
        return $timerStore.profiles[index]
    }

    private func cycleSelection(for profile: Binding<TimerProfile>, presets: [TimeInterval]) -> Binding<String> {
        Binding<String>(
            get: {
                if let match = presets.first(where: { abs($0 - profile.wrappedValue.cycleDuration) < 0.1 }) {
                    return tag(for: match)
                }
                return "custom"
            },
            set: { newValue in
                if newValue == "custom" {
                    if let match = presets.first(where: { abs($0 - profile.wrappedValue.cycleDuration) < 0.1 }) {
                        profile.wrappedValue.cycleDuration = max(15, match + 15)
                        profile.wrappedValue.warningLeadTime = min(profile.wrappedValue.warningLeadTime, profile.wrappedValue.cycleDuration)
                    }
                    return
                }
                if let presetValue = Double(newValue), presets.contains(presetValue) {
                    profile.wrappedValue.cycleDuration = presetValue
                    profile.wrappedValue.warningLeadTime = min(profile.wrappedValue.warningLeadTime, presetValue)
                }
            }
        )
    }

    private func tag(for preset: TimeInterval) -> String {
        String(Int(preset))
    }

    private func formatPreset(_ preset: TimeInterval) -> String {
        let intVal = Int(preset)
        if intVal % 60 == 0 {
            return "\(intVal / 60)m"
        }
        return "\(intVal)s"
    }

    private func ensureSelection() {
        if let selection,
           timerStore.profiles.contains(where: { $0.id == selection }) {
            return
        }
        selection = timerStore.profiles.first?.id
    }

    private func deleteCurrent(profileID: UUID) {
        if let index = timerStore.profiles.firstIndex(where: { $0.id == profileID }) {
            timerStore.profiles.remove(at: index)
            ensureSelection()
        }
    }

    private func dateBinding(for components: Binding<DateComponents>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(from: components.wrappedValue)
                ?? Calendar.current.startOfDay(for: Date())
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                components.wrappedValue.hour = parts.hour
                components.wrappedValue.minute = parts.minute
            }
        )
    }
}

#Preview {
    SettingsView(timerStore: TimerStore())
}

private struct SettingsListRow: View {
    let profile: TimerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.generatedName())
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 6) {
                Chip(text: formatted(time: profile.watchStart))
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Chip(text: formatted(time: profile.watchEnd))
                Spacer()
            }
            .padding(.top, 2)
            HStack {
                Text("\(formatDuration(profile.cycleDuration)) · Warn \(Int(profile.warningLeadTime))s · Looping\(profile.isEnabled ? "" : " · Disabled")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func formatted(time: DateComponents) -> String {
        guard let date = Calendar.current.date(from: time) else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private struct Chip: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let rounded = Int(max(seconds, 0))
        let minutes = rounded / 60
        let secs = rounded % 60
        if minutes == 0 {
            return "\(secs)s"
        }
        return "\(minutes)m \(secs)s"
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.primary)
                }
                Text(title)
                    .font(.headline)
            }
            VStack(spacing: 0) {
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            content
                .frame(maxWidth: 240, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
