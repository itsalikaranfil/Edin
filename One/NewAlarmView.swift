//
//  NewAlarmView.swift
//  One
//

import SwiftUI
import CoreData

struct NewAlarmView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    var alarmToEdit: Alarm? = nil
    var onSaved: () -> Void

    @State private var time: Date = Self.nextMinute(from: Date())
    /// Empty = Never (one-shot). Populated = fire on those Calendar weekday ints.
    @State private var selectedWeekdays: Set<Int> = []
    @State private var label: String = "Alarm"
    @State private var sound: AlarmSound = .default
    @State private var snoozeEnabled: Bool = true
    @State private var snoozeDuration: AlarmSnoozeDuration = .nine
    /// Prevents `onAppear` from resetting edits when popping back from the Repeat picker.
    @State private var didLoadExisting = false

    private var isEditing: Bool { alarmToEdit != nil }

    private var repeatSummary: String {
        AlarmWeekdays.displayTitle(for: selectedWeekdays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .foregroundColor(Color.primaryText)
                        .tint(.blue)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section {
                    NavigationLink {
                        AlarmWeekdayPickerView(selectedWeekdays: $selectedWeekdays)
                    } label: {
                        HStack {
                            Label {
                                Text("Repeat")
                            } icon: {
                                Image(systemName: "repeat")
                                    .font(.system(size: 16))
                            }
                            Spacer()
                            Text(repeatSummary)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(Color.primaryText)

                    LabeledContent {
                        TextField("Alarm", text: $label)
                            .foregroundColor(Color.primaryText)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("Label")
                            .foregroundColor(Color.primaryText)
                    }

                    Picker(selection: $sound) {
                        ForEach(AlarmSound.allCases) { option in
                            Text(option.localizedTitle).tag(option)
                        }
                    } label: {
                        Label {
                            Text("Sound")
                        } icon: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(Color.primaryText)
                }

                Section {
                    Toggle(isOn: $snoozeEnabled) {
                        Label {
                            Text("Snooze")
                        } icon: {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(Color.primaryText)
                    .tint(.green)
                    .sensoryFeedback(.selection, trigger: snoozeEnabled)

                    if snoozeEnabled {
                        Picker(selection: $snoozeDuration) {
                            ForEach(AlarmSnoozeDuration.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        } label: {
                            Label {
                                Text("Snooze Duration")
                            } icon: {
                                Image(systemName: "timer")
                                    .font(.system(size: 16))
                            }
                        }
                        .foregroundColor(Color.primaryText)
                    }
                }
            }
            .tint(.secondary)
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .navigationTitle(isEditing ? "Edit Alarm" : "New Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton(action: saveAlarm)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard !didLoadExisting else { return }
        didLoadExisting = true
        guard let alarm = alarmToEdit else { return }
        if let alarmTime = alarm.time {
            time = alarmTime
        }
        label = alarm.label ?? "Alarm"
        selectedWeekdays = AlarmWeekdays.resolved(for: alarm)
        sound = AlarmSound(rawValue: alarm.sound ?? "") ?? .default
        snoozeEnabled = alarm.snoozeEnabled
        snoozeDuration = AlarmSnoozeDuration.from(minutes: alarm.snoozeDurationMinutes)
    }

    private func saveAlarm() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let alarm = alarmToEdit ?? Alarm(context: viewContext)
        if alarm.id == nil {
            alarm.id = UUID()
        }
        if alarmToEdit == nil {
            alarm.isEnabled = true
        }
        alarm.time = time
        alarm.label = trimmed.isEmpty ? "Alarm" : trimmed
        AlarmWeekdays.setWeekdays(selectedWeekdays, on: alarm)
        alarm.sound = sound.rawValue
        alarm.snoozeEnabled = snoozeEnabled
        alarm.snoozeDurationMinutes = Int16(snoozeDuration.rawValue)

        PersistenceController.shared.save()
        Task {
            await AlarmKitScheduler.schedule(alarm: alarm)
        }
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        onSaved()
        dismiss()
    }

    private static func nextMinute(from date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        let floored = calendar.date(from: components) ?? date
        return calendar.date(byAdding: .minute, value: 1, to: floored) ?? date
    }
}

/// Apple Clock–style weekday multi-select for alarm repeat.
private struct AlarmWeekdayPickerView: View {
    @Binding var selectedWeekdays: Set<Int>

    private var orderedDays: [Int] {
        AlarmWeekdays.orderedWeekdays()
    }

    var body: some View {
        List {
            ForEach(orderedDays, id: \.self) { weekday in
                Button {
                    Haptics.selection()
                    var days = selectedWeekdays
                    if days.contains(weekday) {
                        days.remove(weekday)
                    } else {
                        days.insert(weekday)
                    }
                    selectedWeekdays = days
                } label: {
                    HStack {
                        Text("Every \(AlarmWeekdays.fullSymbol(for: weekday))")
                            .foregroundColor(Color.primaryText)
                        Spacer()
                        if selectedWeekdays.contains(weekday) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundColor(Color.eventBlue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.screenBackground)
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
