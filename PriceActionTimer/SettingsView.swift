//
//  SettingsView.swift
//  PriceActionTimer
//
//  Created by Mephisto Mephisto on 2025/12/21.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @ObservedObject var timerStore: TimerStore
    @State private var selection: UUID?
    private let controlWidth: CGFloat = 220

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(timerStore.profiles) { profile in
                    SettingsListRow(
                        profile: profile,
                        isRunning: timerStore.manager(for: profile.id)?.phase != .idle
                    )
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
        .onAppear {
            // Bring settings window to front
            NSApp.activate()
        }
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
                SettingsCard(title: "Timer", systemImage: "clock") {
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
                                        profile.wrappedValue.cycleDuration = min(max(60, newValue), 86400)
                                        profile.wrappedValue.warningLeadTime = min(profile.wrappedValue.warningLeadTime, profile.wrappedValue.cycleDuration)
                                    }
                                ), in: 60...86400, step: 60) {
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
                }

                SettingsCard(title: "Schedule", systemImage: "calendar") {
                    SettingsRow(title: "Timezone") {
                        TimezonePicker(selectedTimezone: Binding(
                            get: { profile.wrappedValue.timezoneIdentifier },
                            set: { profile.wrappedValue.timezoneIdentifier = $0 }
                        ))
                        .frame(width: controlWidth, alignment: .trailing)
                    }

                    Divider().padding(.leading, 12)
                    SettingsRow(title: "Active days") {
                        VStack(alignment: .trailing, spacing: 8) {
                            WeekdayPicker(selectedWeekdays: Binding(
                                get: { profile.wrappedValue.enabledWeekdays },
                                set: { profile.wrappedValue.enabledWeekdays = $0 }
                            ))
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
                        profile.wrappedValue.cycleDuration = max(60, match + 60)
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
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(cycleName())
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(profile.timeRangeDescription())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func cycleName() -> String {
        let minutes = Int(profile.cycleDuration) / 60
        let seconds = Int(profile.cycleDuration) % 60
        let cycle: String
        if minutes > 0 && seconds > 0 {
            cycle = "\(minutes)m\(seconds)s"
        } else if minutes > 0 {
            cycle = "\(minutes)m"
        } else {
            cycle = "\(seconds)s"
        }
        return "\(cycle) cycle"
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

private struct WeekdayPicker: View {
    @Binding var selectedWeekdays: Set<Int>

    private let weekdays: [(Int, String)] = [
        (2, "Mon"),
        (3, "Tue"),
        (4, "Wed"),
        (5, "Thu"),
        (6, "Fri"),
        (7, "Sat"),
        (1, "Sun")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekdays, id: \.0) { weekday in
                WeekdayButton(
                    day: weekday.1,
                    isSelected: selectedWeekdays.contains(weekday.0)
                ) {
                    if selectedWeekdays.contains(weekday.0) {
                        selectedWeekdays.remove(weekday.0)
                    } else {
                        selectedWeekdays.insert(weekday.0)
                    }
                }
            }
        }
    }
}

private struct WeekdayButton: View {
    let day: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(width: 30, height: 28)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TimezonePicker: View {
    @Binding var selectedTimezone: String
    @State private var showingPopover = false
    @State private var searchText = ""

    // Common timezones for quick selection
    private let baseCommonTimezones: [(String, String)] = [
        ("Local", TimeZone.current.identifier),
        ("New York (EST)", "America/New_York"),
        ("Chicago (CST)", "America/Chicago"),
        ("Los Angeles (PST)", "America/Los_Angeles"),
        ("London (GMT)", "Europe/London"),
        ("Frankfurt (CET)", "Europe/Berlin"),
        ("Hong Kong (HKT)", "Asia/Hong_Kong"),
        ("Tokyo (JST)", "Asia/Tokyo"),
        ("Shanghai (CST)", "Asia/Shanghai"),
        ("Singapore (SGT)", "Asia/Singapore"),
        ("Sydney (AEDT)", "Australia/Sydney"),
    ]

    // Deduplicated common timezones
    private var commonTimezones: [(String, String)] {
        let currentTZ = TimeZone.current.identifier
        var seen = Set<String>()
        var result: [(String, String)] = []

        for (label, identifier) in baseCommonTimezones {
            if seen.contains(identifier) {
                continue
            }

            if label == "Local" {
                result.append((label, identifier))
                seen.insert(identifier)
            } else {
                // Skip if this timezone is same as Local
                if identifier == currentTZ {
                    continue
                }
                result.append((label, identifier))
                seen.insert(identifier)
            }
        }

        return result
    }

    private var displayName: String {
        if let match = baseCommonTimezones.first(where: { $0.1 == selectedTimezone }) {
            return match.0
        }
        let tz = TimeZone(identifier: selectedTimezone)
        let abbr = tz?.abbreviation() ?? ""
        let name = selectedTimezone.replacingOccurrences(of: "_", with: " ")
        return "\(name) (\(abbr))"
    }

    private var filteredTimezones: [(String, String)] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let commonIdentifiers = Set(commonTimezones.map { $0.1 })

        return TimeZone.knownTimeZoneIdentifiers
            .filter { identifier in
                // Exclude common timezones
                if commonIdentifiers.contains(identifier) {
                    return false
                }
                // Match search text
                let displayName = identifier.replacingOccurrences(of: "_", with: " ").lowercased()
                let tz = TimeZone(identifier: identifier)
                let abbr = (tz?.abbreviation() ?? "").lowercased()
                return displayName.contains(query) || abbr.contains(query)
            }
            .prefix(20) // Limit results for performance
            .map { identifier -> (String, String) in
                let tz = TimeZone(identifier: identifier)
                let abbreviation = tz?.abbreviation() ?? ""
                let displayName = identifier.replacingOccurrences(of: "_", with: " ")
                return ("\(displayName) (\(abbreviation))", identifier)
            }
    }

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            HStack {
                Text(displayName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search timezone...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Common timezones section
                        Text("Common")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)

                        ForEach(commonTimezones, id: \.1) { tz in
                            timezoneRow(label: tz.0, identifier: tz.1)
                        }

                        // Search results section
                        if !searchText.isEmpty {
                            if filteredTimezones.isEmpty {
                                Text("No results for \"\(searchText)\"")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            } else {
                                Divider()
                                    .padding(.vertical, 4)

                                Text("Search Results")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)

                                ForEach(filteredTimezones, id: \.1) { tz in
                                    timezoneRow(label: tz.0, identifier: tz.1)
                                }
                            }
                        } else {
                            Text("Type to search all timezones")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 280)
            .padding(.bottom, 8)
        }
    }

    private func timezoneRow(label: String, identifier: String) -> some View {
        Button {
            selectedTimezone = identifier
            showingPopover = false
            searchText = ""
        } label: {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                if selectedTimezone == identifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selectedTimezone == identifier ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}
