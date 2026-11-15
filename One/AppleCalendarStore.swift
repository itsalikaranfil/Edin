//
//  AppleCalendarStore.swift
//  One
//

import SwiftUI
import EventKit
import Combine
import CoreData
import UIKit

/// Read-only snapshot of one Apple Calendar event occurrence.
struct AppleCalendarEvent: Identifiable, Hashable {
    let id: String
    let eventIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let color: Color

    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        if startDate >= dayStart && startDate < dayEnd { return true }
        return startDate < dayStart && endDate > dayStart
    }

    /// Sort key on a given day: all-day and earlier-day starts sort to the top of that day.
    func sortDate(on day: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        if isAllDay || startDate < dayStart { return dayStart }
        return startDate
    }

    var timeText: String {
        if isAllDay { return String(localized: "All day") }
        let start = startDate.formatted(date: .omitted, time: .shortened)
        let end = endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

/// A group of calendars as shown on the Calendar Events settings page.
struct AppleCalendarGroup: Identifiable {
    let title: String
    let calendars: [EKCalendar]

    var id: String { title }
}

/// Shows events from the user's Apple calendars next to Edin items, and can copy Edin
/// events and reminders into a dedicated "Edin" calendar (see AppleCalendarExport.swift).
/// Calendars are visible unless turned off, so newly added calendars show up automatically.
@MainActor
final class AppleCalendarStore: ObservableObject {
    static let shared = AppleCalendarStore()

    private static let enabledKey = "showAppleCalendarEvents"
    private static let hiddenCalendarsKey = "hiddenAppleCalendarIDs"
    private static let exportEnabledKey = "exportToAppleCalendar"
    static let edinCalendarIDKey = "edinAppleCalendarID"

    let eventStore = EKEventStore()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isEnabled: Bool
    @Published private(set) var hiddenCalendarIDs: Set<String>
    @Published private(set) var isExportEnabled: Bool
    /// Bumped whenever shown events may have changed (settings, access, or Calendar database edits).
    @Published private(set) var revision = 0

    private var storeChangedObserver: NSObjectProtocol?
    private var exportObservers: [NSObjectProtocol] = []
    var pendingExport: Task<Void, Never>?

    var hasAccess: Bool { authorizationStatus == .fullAccess }
    var isActive: Bool { isEnabled && hasAccess }
    var isExportActive: Bool { isExportEnabled && hasAccess }

    /// Identifier of the calendar Edin writes to; it's never shown back inside Edin.
    var edinCalendarID: String? {
        get { UserDefaults.standard.string(forKey: Self.edinCalendarIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.edinCalendarIDKey) }
    }
    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenCalendarsKey) ?? [])
        isExportEnabled = UserDefaults.standard.bool(forKey: Self.exportEnabledKey)
        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        exportObservers = [
            NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleExport() }
            },
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleExport() }
            }
        ]
        scheduleExport()
    }

    /// Re-reads access, e.g. after the user returns from the Settings app.
    func refresh() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        revision += 1
    }

    /// Turns the feature on (asking for Calendar access the first time) or off.
    func setEnabled(_ enabled: Bool) async {
        if enabled && !hasAccess {
            _ = try? await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
        isEnabled = enabled && hasAccess
        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        revision += 1
    }

    /// Turns copying Edin events and reminders into Apple Calendar on or off.
    /// Turning it off removes the "Edin" calendar and everything Edin put in it.
    func setExportEnabled(_ enabled: Bool) async {
        if enabled && !hasAccess {
            _ = try? await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
        isExportEnabled = enabled && hasAccess
        UserDefaults.standard.set(isExportEnabled, forKey: Self.exportEnabledKey)
        if isExportEnabled {
            exportNow()
        } else {
            pendingExport?.cancel()
            removeEdinCalendar()
        }
        revision += 1
    }

    var calendarGroups: [AppleCalendarGroup] {
        guard hasAccess else { return [] }
        var grouped: [String: [EKCalendar]] = [:]
        for calendar in eventStore.calendars(for: .event) where calendar.calendarIdentifier != edinCalendarID {
            grouped[groupTitle(for: calendar), default: []].append(calendar)
        }
        return grouped
            .map { AppleCalendarGroup(title: $0.key, calendars: $0.value.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }) }
            .sorted { groupOrder($0.title) < groupOrder($1.title) }
    }

    func isVisible(_ calendar: EKCalendar) -> Bool {
        !hiddenCalendarIDs.contains(calendar.calendarIdentifier)
    }

    func setVisible(_ visible: Bool, for calendar: EKCalendar) {
        if visible {
            hiddenCalendarIDs.remove(calendar.calendarIdentifier)
        } else {
            hiddenCalendarIDs.insert(calendar.calendarIdentifier)
        }
        UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Self.hiddenCalendarsKey)
        revision += 1
    }

    /// Occurrences overlapping `start..<end` from the visible calendars; empty when the feature is off.
    func events(from start: Date, to end: Date) -> [AppleCalendarEvent] {
        guard isActive, start < end else { return [] }
        let edinID = edinCalendarID
        let calendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.calendarIdentifier != edinID && isVisible(calendar)
        }
        guard !calendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate)
            .map { event in
                let identifier: String = event.eventIdentifier ?? UUID().uuidString
                let rawTitle: String = event.title ?? ""
                let calendar: EKCalendar? = event.calendar
                return AppleCalendarEvent(
                    id: "\(identifier)-\(Int(event.startDate.timeIntervalSince1970))",
                    eventIdentifier: identifier,
                    title: rawTitle.isEmpty ? String(localized: "New Event") : rawTitle,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: calendar?.title ?? "",
                    color: calendar.map { Color(cgColor: $0.cgColor) } ?? Color.eventBlue
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func event(withIdentifier identifier: String) -> EKEvent? {
        eventStore.event(withIdentifier: identifier)
    }

    private func groupTitle(for calendar: EKCalendar) -> String {
        switch calendar.type {
        case .birthday: return String(localized: "Birthdays")
        case .subscription: return String(localized: "Subscribed")
        default:
            let source: EKSource? = calendar.source
            return source?.title ?? String(localized: "Other")
        }
    }

    private func groupOrder(_ title: String) -> String {
        // iCloud first, then accounts by name, with Birthdays and Subscribed after them.
        if title == "iCloud" { return "0" }
        if title == String(localized: "Birthdays") { return "2" }
        if title == String(localized: "Subscribed") { return "3" }
        return "1\(title)"
    }
}
