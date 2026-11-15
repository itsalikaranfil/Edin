//
//  AppleCalendarExport.swift
//  One
//

import Foundation
import EventKit
import CoreData
import UIKit

/// One Edin occurrence as it should appear in the "Edin" Apple calendar.
private struct EdinCalendarEntry {
    let key: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String?
}

/// Mirrors Edin events and incomplete reminders into a calendar named "Edin".
/// Each occurrence becomes its own Apple Calendar event keyed by its URL, so edits, deletes,
/// skipped repeats, and completions in Edin are reflected on the next sync. Changes made to
/// these events inside Apple Calendar are overwritten, since Edin is the source of truth.
extension AppleCalendarStore {
    private static let exportPastDays = 14
    private static let exportFutureDays = 120
    private static let defaultEventDuration: TimeInterval = 60 * 60
    private static let defaultReminderDuration: TimeInterval = 30 * 60
    private static let edinCalendarTitle = "Edin"

    /// Debounced sync, so bursts of Core Data saves trigger a single pass.
    func scheduleExport() {
        guard isExportActive else { return }
        pendingExport?.cancel()
        pendingExport = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.exportNow()
        }
    }

    func exportNow() {
        guard isExportActive, let edinCalendar = edinCalendar() else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let windowStart = cal.date(byAdding: .day, value: -Self.exportPastDays, to: today),
              let windowEnd = cal.date(byAdding: .day, value: Self.exportFutureDays, to: today) else { return }

        let desired = desiredEntries(from: windowStart, to: windowEnd, calendar: cal)

        var existingByKey: [String: EKEvent] = [:]
        var stale: [EKEvent] = []
        let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: [edinCalendar])
        for event in eventStore.events(matching: predicate) {
            if let key = event.url?.absoluteString, existingByKey[key] == nil {
                existingByKey[key] = event
            } else {
                stale.append(event)
            }
        }

        var hasChanges = false
        for entry in desired {
            let event: EKEvent
            if let existing = existingByKey.removeValue(forKey: entry.key) {
                guard needsUpdate(existing, to: entry) else { continue }
                event = existing
            } else {
                event = EKEvent(eventStore: eventStore)
                event.calendar = edinCalendar
                event.url = URL(string: entry.key)
            }
            event.title = entry.title
            event.isAllDay = entry.isAllDay
            event.startDate = entry.startDate
            event.endDate = entry.endDate
            event.notes = entry.notes
            if (try? eventStore.save(event, span: .thisEvent, commit: false)) != nil {
                hasChanges = true
            }
        }

        for event in stale + Array(existingByKey.values) {
            if (try? eventStore.remove(event, span: .thisEvent, commit: false)) != nil {
                hasChanges = true
            }
        }

        if hasChanges {
            try? eventStore.commit()
        }
    }

    func removeEdinCalendar() {
        if let calendar = existingEdinCalendar() {
            try? eventStore.removeCalendar(calendar, commit: true)
        }
        edinCalendarID = nil
    }

    // MARK: Desired state

    private func desiredEntries(from start: Date, to end: Date, calendar cal: Calendar) -> [EdinCalendarEntry] {
        guard let lastDay = cal.date(byAdding: .day, value: -1, to: end) else { return [] }
        let context = PersistenceController.shared.container.viewContext
        var entries: [EdinCalendarEntry] = []

        let events = (try? context.fetch(NSFetchRequest<Event>(entityName: "Event"))) ?? []
        for event in events {
            guard let id = event.id?.uuidString, let baseDate = event.date else { continue }
            let title = Self.nonEmpty(event.title) ?? String(localized: "Untitled Event")
            let days = occurrenceDays(
                baseDate: baseDate,
                repeatOption: event.repeatOption,
                excludedDates: event.excludedDatesStorage,
                from: start,
                through: lastDay,
                calendar: cal
            )
            for day in days {
                let key = Self.entryKey(kind: "event", id: id, day: day)
                if event.isAllDay || event.startTime == nil {
                    entries.append(EdinCalendarEntry(key: key, title: title, startDate: day, endDate: day, isAllDay: true, notes: event.notes))
                    continue
                }
                guard let startTime = event.startTime else { continue }
                let startDate = cal.combining(day: day, andTimeFrom: startTime)
                var endDate = event.endTime.map { cal.combining(day: day, andTimeFrom: $0) }
                    ?? startDate.addingTimeInterval(Self.defaultEventDuration)
                if endDate < startDate {
                    // Ends after midnight.
                    endDate = cal.date(byAdding: .day, value: 1, to: endDate) ?? startDate.addingTimeInterval(Self.defaultEventDuration)
                } else if endDate == startDate {
                    endDate = startDate.addingTimeInterval(Self.defaultEventDuration)
                }
                entries.append(EdinCalendarEntry(key: key, title: title, startDate: startDate, endDate: endDate, isAllDay: false, notes: event.notes))
            }
        }

        let reminderRequest = NSFetchRequest<Reminder>(entityName: "Reminder")
        reminderRequest.predicate = NSPredicate(format: "isCompleted == NO")
        let reminders = (try? context.fetch(reminderRequest)) ?? []
        for reminder in reminders {
            guard let id = reminder.id?.uuidString, let baseDate = reminder.date else { continue }
            let title = Self.nonEmpty(reminder.title) ?? String(localized: "Untitled Reminder")
            let days = occurrenceDays(
                baseDate: baseDate,
                repeatOption: reminder.repeatOption,
                excludedDates: reminder.excludedDatesStorage,
                from: start,
                through: lastDay,
                calendar: cal
            )
            for day in days {
                let key = Self.entryKey(kind: "reminder", id: id, day: day)
                if let time = reminder.time {
                    let startDate = cal.combining(day: day, andTimeFrom: time)
                    entries.append(EdinCalendarEntry(
                        key: key,
                        title: title,
                        startDate: startDate,
                        endDate: startDate.addingTimeInterval(Self.defaultReminderDuration),
                        isAllDay: false,
                        notes: reminder.notes
                    ))
                } else {
                    entries.append(EdinCalendarEntry(key: key, title: title, startDate: day, endDate: day, isAllDay: true, notes: reminder.notes))
                }
            }
        }

        return entries
    }

    private func occurrenceDays(
        baseDate: Date,
        repeatOption: String?,
        excludedDates: String?,
        from start: Date,
        through lastDay: Date,
        calendar cal: Calendar
    ) -> [Date] {
        let option = Recurrence.option(from: repeatOption)
        if option == .never {
            let day = cal.startOfDay(for: baseDate)
            return day >= start && day <= lastDay ? [day] : []
        }
        return Recurrence.occurrenceDates(
            from: start,
            through: lastDay,
            baseDate: baseDate,
            option: option,
            excludedDates: excludedDates,
            calendar: cal
        )
    }

    private func needsUpdate(_ event: EKEvent, to entry: EdinCalendarEntry) -> Bool {
        if event.title != entry.title { return true }
        if event.isAllDay != entry.isAllDay { return true }
        if (event.notes ?? "") != (entry.notes ?? "") { return true }
        if event.startDate != entry.startDate { return true }
        // EventKit normalizes all-day end dates, so only timed events compare their end.
        if !entry.isAllDay && event.endDate != entry.endDate { return true }
        return false
    }

    private static func entryKey(kind: String, id: String, day: Date) -> String {
        "oneapp://item/\(kind)/\(id)/\(Recurrence.dayKey(for: day))"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    // MARK: Edin calendar

    private func existingEdinCalendar() -> EKCalendar? {
        if let id = edinCalendarID, let calendar = eventStore.calendar(withIdentifier: id) {
            return calendar
        }
        return nil
    }

    private func edinCalendar() -> EKCalendar? {
        if let calendar = existingEdinCalendar() {
            return calendar
        }
        // Calendar identifiers can change after a full iCloud resync; reuse the calendar by name first.
        if let calendar = eventStore.calendars(for: .event).first(where: {
            $0.title == Self.edinCalendarTitle && $0.allowsContentModifications
        }) {
            edinCalendarID = calendar.calendarIdentifier
            return calendar
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = Self.edinCalendarTitle
        calendar.cgColor = UIColor(red: 1, green: 25 / 255, blue: 25 / 255, alpha: 1).cgColor
        for source in candidateSources() {
            calendar.source = source
            if (try? eventStore.saveCalendar(calendar, commit: true)) != nil {
                edinCalendarID = calendar.calendarIdentifier
                return calendar
            }
        }
        return nil
    }

    /// Prefer the account new events go to (usually iCloud), then iCloud, then On My iPhone.
    private func candidateSources() -> [EKSource] {
        var ordered: [EKSource] = []
        if let source = eventStore.defaultCalendarForNewEvents?.source {
            ordered.append(source)
        }
        ordered += eventStore.sources.filter { $0.sourceType == .calDAV && $0.title == "iCloud" }
        ordered += eventStore.sources.filter { $0.sourceType == .local }
        ordered += eventStore.sources.filter { $0.sourceType == .calDAV || $0.sourceType == .exchange }

        var seen = Set<String>()
        return ordered.filter { seen.insert($0.sourceIdentifier).inserted }
    }
}
