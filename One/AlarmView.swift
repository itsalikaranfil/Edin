//
//  AlarmView.swift
//  One
//

import SwiftUI
import CoreData

private struct AlarmEditPresentation: Identifiable {
    let alarm: Alarm
    var id: NSManagedObjectID { alarm.objectID }
}

struct AlarmView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var coordinator = AlarmSheetCoordinator.shared

    @Binding var isPresented: Bool
    var bottomContentInset: CGFloat = 0

    @State private var alarms: [Alarm] = []
    @State private var showNewAlarm = false
    @State private var alarmToEdit: AlarmEditPresentation?

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                ForEach(Array(alarms.enumerated()), id: \.element.objectID) { index, alarm in
                    AlarmListRow(
                        alarm: alarm,
                        onToggle: { enabled in
                            alarm.isEnabled = enabled
                            if enabled, AlarmWeekdays.resolved(for: alarm).isEmpty, let time = alarm.time {
                                // Re-arm a spent one-shot onto the next fire day so reload won't flip it off.
                                let calendar = Calendar.current
                                let nextDay = AlarmDaySchedule.nextNeverFireDay(time: time, calendar: calendar)
                                alarm.time = calendar.combining(day: nextDay, andTimeFrom: time)
                            }
                            PersistenceController.shared.save()
                            Task {
                                await AlarmKitScheduler.schedule(alarm: alarm)
                            }
                            NotificationCenter.default.post(name: .dataDidChange, object: nil)
                        },
                        onTap: {
                            alarmToEdit = AlarmEditPresentation(alarm: alarm)
                        }
                    )
                    .id(alarmRowID(alarm))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(index == alarms.count - 1 ? .hidden : .visible, edges: .bottom)
                    .listRowBackground(Color.calendarSheetSurface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteAlarm(alarm)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.bottom, bottomContentInset)
            .overlay {
                if alarms.isEmpty {
                    Text("No alarms set")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .offset(y: -48)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.calendarSheetSurface)
        .onAppear(perform: reloadAlarms)
        .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
            reloadAlarms()
        }
        .onChange(of: coordinator.requestAddAlarm) { _, requested in
            guard requested else { return }
            alarmToEdit = nil
            showNewAlarm = true
            coordinator.consumeAddAlarmRequest()
        }
        .sheet(item: $alarmToEdit, onDismiss: reloadAlarms) { presentation in
            NewAlarmView(alarmToEdit: presentation.alarm, onSaved: reloadAlarms)
                .environment(\.managedObjectContext, viewContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewAlarm, onDismiss: reloadAlarms) {
            NewAlarmView(alarmToEdit: nil, onSaved: reloadAlarms)
                .environment(\.managedObjectContext, viewContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Alarms")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.primaryText)

            Spacer()

            SheetClosePill {
                isPresented = false
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func alarmRowID(_ alarm: Alarm) -> String {
        let timeKey = alarm.time.map { String($0.timeIntervalSince1970) } ?? "nil"
        let labelKey = alarm.label ?? ""
        let repeatKey = AlarmWeekdays.encode(AlarmWeekdays.resolved(for: alarm)) ?? (alarm.repeatOption ?? "")
        let enabledKey = alarm.isEnabled ? "1" : "0"
        return "\(alarm.objectID.uriRepresentation().absoluteString)|\(timeKey)|\(labelKey)|\(repeatKey)|\(enabledKey)"
    }

    private func reloadAlarms() {
        guard NSEntityDescription.entity(forEntityName: "Alarm", in: viewContext) != nil else {
            alarms = []
            return
        }
        viewContext.processPendingChanges()
        let request = NSFetchRequest<Alarm>(entityName: "Alarm")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Alarm.time, ascending: true)]
        let fetched = (try? viewContext.fetch(request)) ?? []

        // One-shot alarms whose day has passed should look off so they don't seem still active.
        var didDisableSpent = false
        for alarm in fetched where alarm.isEnabled && AlarmDaySchedule.isSpentOneShot(alarm) {
            alarm.isEnabled = false
            if let id = alarm.id {
                AlarmKitScheduler.cancel(id: id)
            }
            didDisableSpent = true
        }
        if didDisableSpent {
            PersistenceController.shared.save()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }

        alarms = fetched
    }

    private func deleteAlarm(_ alarm: Alarm) {
        if let id = alarm.id {
            AlarmKitScheduler.cancel(id: id)
            NotificationManager.shared.cancelAllNotifications(for: id.uuidString, itemType: "alarm")
        }
        viewContext.delete(alarm)
        PersistenceController.shared.save()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        reloadAlarms()
    }
}

private struct AlarmListRow: View {
    @ObservedObject var alarm: Alarm
    var onToggle: (Bool) -> Void
    var onTap: () -> Void

    private var timeText: String {
        guard let time = alarm.time else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }

    private var subtitle: String {
        let name = (alarm.label?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Alarm"
        let days = AlarmWeekdays.resolved(for: alarm)
        guard !days.isEmpty else { return name }
        return "\(name), \(AlarmWeekdays.displayTitle(for: days))"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText)
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(alarm.isEnabled ? Color.primaryText : Color.primaryText.opacity(0.45))

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(alarm.isEnabled ? Color.primaryText : .gray)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .tint(.green)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
