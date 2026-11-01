import Foundation
import CoreData
import WidgetKit

/// Builds a JSON snapshot of today's and tomorrow's items and writes it to the
/// shared App Group container so the widget extension can read it without touching
/// the Core Data / CloudKit stack directly.
final class WidgetSnapshotExporter {
    static let shared = WidgetSnapshotExporter()
    private init() {}

    private var pendingExport: DispatchWorkItem?
    private let exportQueue = DispatchQueue(label: "com.ali.OneApp.widgetExport", qos: .utility)

    /// Schedule a debounced export (0.5 s) so rapid saves don't thrash disk writes.
    func scheduleExport() {
        pendingExport?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performExport()
        }
        pendingExport = work
        exportQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Private

    private func performExport() {
        let context = PersistenceController.shared.container.viewContext
        context.perform { [weak self] in
            guard let self else { return }
            let snapshot = self.buildSnapshot(context: context)
            self.write(snapshot)
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// Future titled day sections starting the calendar day after tomorrow; medium widget shows first two after-today blocks only.
    private static let maxFutureDaySectionsWhenNoTomorrow = 3
    /// Additional dated sections after a non-empty Tomorrow block (keeps snapshots small).
    private static let maxExtraFutureDaySectionsWhenTomorrowHasItems = 2
    private static let futureScanHorizonDays = 365

    private func buildSnapshot(context: NSManagedObjectContext) -> WidgetSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: today)!
        let todayRows = fetchRows(from: today, to: tomorrow, context: context)
        let tomorrowRows = fetchRows(from: tomorrow, to: dayAfter, context: context)

        var sections: [WidgetDatedSection] = []
        if !tomorrowRows.isEmpty {
            sections.append(WidgetDatedSection(title: "Tomorrow", rows: tomorrowRows))
        }
        let futureCap = tomorrowRows.isEmpty
            ? Self.maxFutureDaySectionsWhenNoTomorrow
            : Self.maxExtraFutureDaySectionsWhenTomorrowHasItems
        sections.append(contentsOf: buildNearestFutureDaySections(
            calendar: cal,
            startAfterTomorrow: dayAfter,
            context: context,
            maxSections: futureCap
        ))

        let afterTodaySections: [WidgetDatedSection]? = sections.isEmpty ? nil : sections
        let todayHadCompleted = hasCompletedItemsToday(from: today, to: tomorrow, context: context)

        return WidgetSnapshot(
            generatedAt: Date(),
            todayRows: todayRows,
            tomorrowRows: tomorrowRows,
            afterTodaySections: afterTodaySections,
            todayHadCompletedItems: todayHadCompleted
        )
    }

    /// Whether any reminder or habit for today is already done (used for empty Today copy).
    private func hasCompletedItemsToday(from start: Date, to end: Date, context: NSManagedObjectContext) -> Bool {
        let reminderRequest = NSFetchRequest<Reminder>(entityName: "Reminder")
        reminderRequest.predicate = NSPredicate(
            format: "date >= %@ AND date < %@ AND isCompleted == YES",
            start as NSDate,
            end as NSDate
        )
        reminderRequest.fetchLimit = 1
        if let count = try? context.count(for: reminderRequest), count > 0 {
            return true
        }

        let habitRequest = NSFetchRequest<Habit>(entityName: "Habit")
        habitRequest.predicate = NSPredicate(format: "date < %@", end as NSDate)
        guard let habits = try? context.fetch(habitRequest) else { return false }
        return habits.contains { $0.isCompleted(on: start) }
    }

    /// Earliest future calendar days with items starting at `startAfterTomorrow` (first moment after tomorrow ends), capped per `maxSections`.
    private func buildNearestFutureDaySections(
        calendar cal: Calendar,
        startAfterTomorrow: Date,
        context: NSManagedObjectContext,
        maxSections: Int
    ) -> [WidgetDatedSection] {
        var sections: [WidgetDatedSection] = []
        var dayStart = startAfterTomorrow
        for _ in 0..<Self.futureScanHorizonDays {
            if sections.count >= maxSections { break }
            guard let nextStart = cal.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let rows = fetchRows(from: dayStart, to: nextStart, context: context)
            if !rows.isEmpty {
                sections.append(WidgetDatedSection(title: formatSectionDate(dayStart), rows: rows))
            }
            dayStart = nextStart
        }
        return sections
    }

    private func formatSectionDate(_ dayStart: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM"
        return f.string(from: dayStart)
    }

    private func fetchRows(from start: Date, to end: Date, context: NSManagedObjectContext) -> [WidgetRow] {
        var rows: [WidgetRow] = []
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let isTodayWindow = start == todayStart

        // Events
        let er = NSFetchRequest<Event>(entityName: "Event")
        er.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        if let events = try? context.fetch(er) {
            for event in events {
                var subtitle: String?
                if !event.isAllDay, let s = event.startTime, let e = event.endTime {
                    subtitle = formatTime(s) + " - " + formatTime(e)
                } else if !event.isAllDay, let s = event.startTime {
                    subtitle = formatTime(s)
                }
                rows.append(WidgetRow(
                    id: event.id?.uuidString ?? UUID().uuidString,
                    kind: .event,
                    title: event.title ?? "",
                    subtitle: subtitle,
                    sortDate: event.startTime ?? event.date ?? start
                ))
            }
        }

        // Incomplete reminders only
        let rr = NSFetchRequest<Reminder>(entityName: "Reminder")
        rr.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND isCompleted == NO", start as NSDate, end as NSDate)
        if let reminders = try? context.fetch(rr) {
            for reminder in reminders {
                let subtitle = reminder.time.map { formatTime($0) }
                rows.append(WidgetRow(
                    id: reminder.id?.uuidString ?? UUID().uuidString,
                    kind: .reminder,
                    title: reminder.title ?? "",
                    subtitle: subtitle,
                    sortDate: reminder.time ?? reminder.date ?? start
                ))
            }
        }

        // Incomplete habit occurrences for this day window
        let hr = NSFetchRequest<Habit>(entityName: "Habit")
        hr.predicate = NSPredicate(format: "date < %@", end as NSDate)
        if let habits = try? context.fetch(hr) {
            for habit in habits {
                guard let baseDate = habit.date else { continue }
                let option = Recurrence.option(from: habit.repeatOption)
                let baseID = habit.id?.uuidString ?? habit.objectID.uriRepresentation().absoluteString

                let occurrenceDay: Date?
                if Recurrence.occurs(
                    on: start,
                    baseDate: baseDate,
                    option: option,
                    excludedDates: habit.excludedDatesStorage,
                    calendar: cal
                ), !habit.isCompleted(on: start) {
                    occurrenceDay = start
                } else if isTodayWindow,
                          option == .never,
                          !habit.isCompleted,
                          cal.startOfDay(for: baseDate) < todayStart,
                          !habit.isCompleted(on: cal.startOfDay(for: baseDate)) {
                    // Overdue one-off habits still surface under Today.
                    occurrenceDay = todayStart
                } else {
                    occurrenceDay = nil
                }

                guard let day = occurrenceDay else { continue }
                let sortDate: Date
                if let time = habit.time {
                    sortDate = cal.combining(day: day, andTimeFrom: time)
                } else {
                    sortDate = day
                }
                rows.append(WidgetRow(
                    id: "\(baseID)-\(Recurrence.dayKey(for: day))",
                    kind: .habit,
                    title: habit.title ?? "",
                    subtitle: habit.time.map { formatTime($0) },
                    sortDate: sortDate,
                    occurrenceDayKey: Recurrence.dayKey(for: day)
                ))
            }
        }

        rows.sort { $0.sortDate < $1.sortDate }
        return rows
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func write(_ snapshot: WidgetSnapshot) {
        guard let url = WidgetSnapshot.snapshotURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        let tmp = url.deletingLastPathComponent().appendingPathComponent("widgetSnapshot.tmp.json")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? data.write(to: url)
        }
    }
}
