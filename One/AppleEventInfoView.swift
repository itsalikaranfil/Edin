//
//  AppleEventInfoView.swift
//  One
//

import SwiftUI
import EventKit

/// Edits an Apple Calendar event with the same layout as Edin's own event info sheet.
/// Changes are written back to the event's calendar when the sheet closes.
struct AppleEventInfoView: View {
    let event: EKEvent

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var isAllDay = false
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var alertOption: AlertOption = .none
    @State private var hasLoaded = false
    @State private var isDeleted = false
    @State private var showRepeatDeleteConfirmation = false

    private var calendarColor: Color {
        event.calendar.map { Color(cgColor: $0.cgColor) } ?? Color.importedEventBlue
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                scheduleSection
                alertSection
                notesSection
                deleteSection
            }
            .tint(.secondary)
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .listSectionSpacing(12)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton {
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .repeatDeleteConfirmation(
                isPresented: $showRepeatDeleteConfirmation,
                onDeleteThis: { delete(allOccurrences: false) },
                onDeleteAll: { delete(allOccurrences: true) }
            )
            .onAppear(perform: loadFields)
            .onDisappear(perform: saveChanges)
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(Color.importedEventBlue)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.primaryText)

                    if let calendarTitle = event.calendar?.title, !calendarTitle.isEmpty {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(calendarColor)
                                .frame(width: 6, height: 6)
                            Text(calendarTitle)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(calendarColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(calendarColor.opacity(0.14))
                        .clipShape(Capsule())
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var scheduleSection: some View {
        Section {
            DatePicker(selection: $date, displayedComponents: .date) {
                Label {
                    Text("Date")
                } icon: {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                }
            }
            .foregroundColor(Color.primaryText)
            .tint(.blue)

            Toggle("All Day", isOn: $isAllDay)
                .foregroundColor(Color.primaryText)
                .tint(.green)
                .sensoryFeedback(.selection, trigger: isAllDay)

            if !isAllDay {
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                    .foregroundColor(Color.primaryText)
                    .tint(.blue)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                    .foregroundColor(Color.primaryText)
                    .tint(.blue)
            }
        }
    }

    private var alertSection: some View {
        Section {
            Picker(selection: $alertOption) {
                ForEach(AlertOption.allCases, id: \.self) { option in
                    Text(option.localizedTitle).tag(option)
                }
            } label: {
                Label {
                    Text("Alert")
                } icon: {
                    Image(systemName: "alarm")
                        .font(.system(size: 16))
                }
            }
            .foregroundColor(Color.primaryText)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .foregroundColor(Color.primaryText)
                .lineLimit(3...6)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                if event.hasRecurrenceRules {
                    showRepeatDeleteConfirmation = true
                } else {
                    delete(allOccurrences: false)
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Delete")
                    Spacer()
                }
                .foregroundStyle(.red)
            }
            .tint(.red)
        }
    }

    // MARK: Loading and saving

    private func loadFields() {
        guard !hasLoaded else { return }
        hasLoaded = true
        title = event.title ?? ""
        notes = event.notes ?? ""
        isAllDay = event.isAllDay
        date = Calendar.current.startOfDay(for: event.startDate)
        startTime = event.startDate
        endTime = event.endDate
        alertOption = Self.alertOption(for: event.alarms?.first)
    }

    private func saveChanges() {
        guard hasLoaded, !isDeleted else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        let newStart: Date
        let newEnd: Date
        if isAllDay {
            newStart = day
            newEnd = day
        } else {
            newStart = calendar.combining(day: day, andTimeFrom: startTime)
            var end = calendar.combining(day: day, andTimeFrom: endTime)
            if end < newStart {
                end = calendar.date(byAdding: .day, value: 1, to: end) ?? newStart.addingTimeInterval(3600)
            } else if end == newStart {
                end = newStart.addingTimeInterval(3600)
            }
            newEnd = end
        }

        let currentAlert = Self.alertOption(for: event.alarms?.first)
        let changed = title != (event.title ?? "")
            || notes != (event.notes ?? "")
            || isAllDay != event.isAllDay
            || newStart != event.startDate
            || (!isAllDay && newEnd != event.endDate)
            || alertOption != currentAlert
        guard changed else { return }

        event.title = title
        event.notes = notes.isEmpty ? nil : notes
        event.isAllDay = isAllDay
        event.startDate = newStart
        event.endDate = newEnd
        if alertOption != currentAlert {
            event.alarms = Self.offset(for: alertOption).map { [EKAlarm(relativeOffset: $0)] }
        }
        AppleCalendarStore.shared.save(event)
    }

    private func delete(allOccurrences: Bool) {
        isDeleted = true
        AppleCalendarStore.shared.delete(event, allOccurrences: allOccurrences)
        dismiss()
    }

    // MARK: Alerts

    private static func offset(for option: AlertOption) -> TimeInterval? {
        switch option {
        case .none: return nil
        case .atTime: return 0
        case .fiveMinutes: return -5 * 60
        case .fifteenMinutes: return -15 * 60
        case .thirtyMinutes: return -30 * 60
        case .oneHour: return -60 * 60
        case .twoHours: return -2 * 60 * 60
        case .oneDay: return -24 * 60 * 60
        }
    }

    private static func alertOption(for alarm: EKAlarm?) -> AlertOption {
        guard let alarm, alarm.absoluteDate == nil else { return .none }
        return AlertOption.allCases.first { offset(for: $0) == alarm.relativeOffset } ?? .none
    }
}
