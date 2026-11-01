//
//  NotificationManager.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import Foundation
import UserNotifications
import Combine
import CoreData

/// Manages local notifications for events and reminders
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    /// Request notification permission
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            
            if granted {
                await checkAuthorizationStatus()
            }
        } catch {
            #if DEBUG
            print("Error requesting notification authorization: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Schedule notification for an event
    func scheduleNotification(for event: Event) {
        let eventId = event.id?.uuidString ?? UUID().uuidString
        let alert = AlertOption(rawValue: event.alert ?? "None") ?? .none
        let secondAlert = secondAlertOption(from: event)
        
        // Check if event has a time/date set
        let hasTime = event.startTime != nil || event.date != nil
        
        // Schedule primary alert if set, or default notification if alert is "None" but time is set
        if alert != .none {
            scheduleSingleNotification(
                for: event,
                alert: alert,
                identifier: "event_\(eventId)",
                isSecondAlert: false
            )
            
            // Also fire at the actual time when primary is a before-alert
            if alert.isBeforeAlert, secondAlert != .atTime {
                scheduleSingleNotification(
                    for: event,
                    alert: .atTime,
                    identifier: "event_\(eventId)_atTime",
                    isSecondAlert: false
                )
            }
        } else if hasTime {
            // Default notification at time of event when alert is "None" but time is set
            scheduleSingleNotification(
                for: event,
                alert: .atTime,
                identifier: "event_\(eventId)",
                isSecondAlert: false
            )
        }
        
        // Schedule second alert if set
        if let secondAlert, secondAlert != .none {
            scheduleSingleNotification(
                for: event,
                alert: secondAlert,
                identifier: "event_\(eventId)_second",
                isSecondAlert: true
            )
        }
    }
    
    /// Schedule a single notification for an event
    private func scheduleSingleNotification(for event: Event, alert: AlertOption, identifier: String, isSecondAlert: Bool) {
        guard let notificationDate = calculateNotificationDate(for: event, alert: alert) else {
            #if DEBUG
            print("⚠️ Failed to calculate notification date for event \(event.id?.uuidString ?? "unknown") with alert \(alert.rawValue)")
            #endif
            return
        }
        
        guard let trigger = makeTrigger(for: notificationDate) else {
            #if DEBUG
            print("⚠️ Notification date is in the past for event \(event.id?.uuidString ?? "unknown"): \(notificationDate)")
            #endif
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = event.title ?? "Untitled"
        content.body = alert.notificationBody(itemDate: notificationDate)
        content.sound = .default
        content.userInfo = [
            "type": "event",
            "id": event.id?.uuidString ?? ""
        ]
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                #if DEBUG
                print("❌ Error scheduling notification \(identifier): \(error.localizedDescription)")
                #endif
            } else {
                #if DEBUG
                print("✅ Scheduled notification \(identifier) for \(notificationDate)")
                #endif
            }
        }
    }
    
    /// Schedule notification for a reminder
    func scheduleNotification(for reminder: Reminder) {
        guard !reminder.isCompleted else { return }
        
        let reminderId = reminder.id?.uuidString ?? UUID().uuidString
        let alert = AlertOption(rawValue: reminder.alert ?? "None") ?? .none
        let secondAlert = secondAlertOption(from: reminder)
        
        // Check if reminder has a time/date set
        let hasTime = reminder.time != nil || reminder.date != nil
        
        // Schedule primary alert if set, or default notification if alert is "None" but time is set
        if alert != .none {
            scheduleSingleNotification(
                for: reminder,
                alert: alert,
                identifier: "reminder_\(reminderId)",
                isSecondAlert: false
            )
            
            // Also fire at the actual time when primary is a before-alert
            if alert.isBeforeAlert, secondAlert != .atTime {
                scheduleSingleNotification(
                    for: reminder,
                    alert: .atTime,
                    identifier: "reminder_\(reminderId)_atTime",
                    isSecondAlert: false
                )
            }
        } else if hasTime {
            // Default notification at time of reminder when alert is "None" but time is set
            scheduleSingleNotification(
                for: reminder,
                alert: .atTime,
                identifier: "reminder_\(reminderId)",
                isSecondAlert: false
            )
        }
        
        // Schedule second alert if set
        if let secondAlert, secondAlert != .none {
            scheduleSingleNotification(
                for: reminder,
                alert: secondAlert,
                identifier: "reminder_\(reminderId)_second",
                isSecondAlert: true
            )
        }
    }

    /// Schedule notification for a habit
    func scheduleNotification(for habit: Habit) {
        let today = Calendar.current.startOfDay(for: Date())
        if habit.isCompleted(on: today) { return }

        let habitId = habit.id?.uuidString ?? UUID().uuidString
        let alert = AlertOption(rawValue: habit.alert ?? "None") ?? .none
        let hasTime = habit.time != nil || habit.date != nil

        if alert != .none {
            scheduleSingleNotification(
                for: habit,
                alert: alert,
                identifier: "habit_\(habitId)"
            )
            if alert.isBeforeAlert {
                scheduleSingleNotification(
                    for: habit,
                    alert: .atTime,
                    identifier: "habit_\(habitId)_atTime"
                )
            }
        } else if hasTime {
            scheduleSingleNotification(
                for: habit,
                alert: .atTime,
                identifier: "habit_\(habitId)"
            )
        }
    }
    
    /// Schedule a single notification for a reminder
    private func scheduleSingleNotification(for reminder: Reminder, alert: AlertOption, identifier: String, isSecondAlert: Bool) {
        guard let notificationDate = calculateNotificationDate(for: reminder, alert: alert) else {
            #if DEBUG
            print("⚠️ Failed to calculate notification date for reminder \(reminder.id?.uuidString ?? "unknown") with alert \(alert.rawValue)")
            #endif
            return
        }
        
        guard let trigger = makeTrigger(for: notificationDate) else {
            #if DEBUG
            print("⚠️ Notification date is in the past for reminder \(reminder.id?.uuidString ?? "unknown"): \(notificationDate)")
            #endif
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = reminder.title ?? "Untitled"
        content.body = alert.notificationBody(itemDate: notificationDate)
        content.sound = .default
        content.userInfo = [
            "type": "reminder",
            "id": reminder.id?.uuidString ?? ""
        ]
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                #if DEBUG
                print("❌ Error scheduling notification \(identifier): \(error.localizedDescription)")
                #endif
            } else {
                #if DEBUG
                print("✅ Scheduled notification \(identifier) for \(notificationDate)")
                #endif
            }
        }
    }

    /// Schedule a single notification for a habit
    private func scheduleSingleNotification(for habit: Habit, alert: AlertOption, identifier: String) {
        guard let notificationDate = calculateNotificationDate(for: habit, alert: alert) else {
            #if DEBUG
            print("⚠️ Failed to calculate notification date for habit \(habit.id?.uuidString ?? "unknown") with alert \(alert.rawValue)")
            #endif
            return
        }

        guard let trigger = makeTrigger(for: notificationDate) else {
            #if DEBUG
            print("⚠️ Notification date is in the past for habit \(habit.id?.uuidString ?? "unknown"): \(notificationDate)")
            #endif
            return
        }

        let content = UNMutableNotificationContent()
        content.title = habit.title ?? "Untitled"
        content.body = alert.notificationBody(itemDate: notificationDate)
        content.sound = .default
        content.userInfo = [
            "type": "habit",
            "id": habit.id?.uuidString ?? ""
        ]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                #if DEBUG
                print("❌ Error scheduling notification \(identifier): \(error.localizedDescription)")
                #endif
            } else {
                #if DEBUG
                print("✅ Scheduled notification \(identifier) for \(notificationDate)")
                #endif
            }
        }
    }
    
    /// Calendar triggers are minute-granular. If the calendar match is already past but the
    /// exact fire time is still in the future, fall back to a time-interval trigger.
    /// Already-due times return nil so launch/CloudKit reschedules do not re-fire delivered notifications.
    private func makeTrigger(for notificationDate: Date) -> UNNotificationTrigger? {
        let now = Date()
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notificationDate
        )
        let calendarTrigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        if let next = calendarTrigger.nextTriggerDate(), next > now.addingTimeInterval(0.5) {
            return calendarTrigger
        }
        
        let interval = notificationDate.timeIntervalSince(now)
        if interval > 0 {
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        }
        return nil
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
    
    /// Cancel notification for an item
    func cancelNotification(for identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
    }
    
    /// Cancel all notifications for an item (primary, at-time, and second alerts)
    func cancelAllNotifications(for itemId: String, itemType: String) {
        let prefix: String
        switch itemType {
        case "event": prefix = "event_"
        case "reminder": prefix = "reminder_"
        case "habit": prefix = "habit_"
        case "alarm": prefix = "alarm_"
        default: prefix = "\(itemType)_"
        }
        let identifiers = [
            "\(prefix)\(itemId)",
            "\(prefix)\(itemId)_atTime",
            "\(prefix)\(itemId)_second"
        ]
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        #if DEBUG
        print("🗑️ Cancelled notifications for \(itemType) \(itemId)")
        #endif
    }
    
    private func secondAlertOption(from object: NSManagedObject) -> AlertOption? {
        guard object.entity.attributesByName.keys.contains("secondAlert"),
              let secondAlertValue = object.value(forKey: "secondAlert") as? String else {
            return nil
        }
        return AlertOption(rawValue: secondAlertValue)
    }
    
    /// Calculate notification date based on alert option
    private func calculateNotificationDate(for event: Event, alert: AlertOption) -> Date? {
        guard let eventDate = event.date else { return nil }
        
        let baseDate: Date
        if event.isAllDay {
            // For all-day events, use start of day
            let startOfDay = Calendar.current.startOfDay(for: eventDate)
            // If alert is "At time of event" for all-day, schedule for 9 AM instead of midnight
            if alert == .atTime {
                baseDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: startOfDay) ?? startOfDay
            } else {
                baseDate = startOfDay
            }
        } else if let startTime = event.startTime {
            baseDate = startTime
        } else {
            baseDate = eventDate
        }
        
        return alert.calculateDate(from: baseDate)
    }
    
    /// Calculate notification date for reminder
    private func calculateNotificationDate(for reminder: Reminder, alert: AlertOption) -> Date? {
        guard let day = reminder.date else { return nil }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let baseDate: Date
        if let time = reminder.time {
            // Always pin time-of-day to the reminder's calendar day (DatePicker can leave time on another day).
            baseDate = calendar.combining(day: dayStart, andTimeFrom: time)
        } else {
            // Date-only reminders use 9 AM as the due time for all alerts.
            baseDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        }
        return alert.calculateDate(from: baseDate)
    }

    /// Calculate notification date for habit (same rules as reminder).
    private func calculateNotificationDate(for habit: Habit, alert: AlertOption) -> Date? {
        guard let day = habit.date else { return nil }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let baseDate: Date
        if let time = habit.time {
            baseDate = calendar.combining(day: dayStart, andTimeFrom: time)
        } else {
            baseDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        }
        return alert.calculateDate(from: baseDate)
    }
    
    /// Reschedule all notifications for existing events and reminders
    func rescheduleAllNotifications(context: NSManagedObjectContext) {
        #if DEBUG
        print("🔄 Rescheduling all notifications...")
        #endif
        
        // Fetch all events with non-"None" alerts OR with "None" alert but having a time/date
        let eventFetchRequest = NSFetchRequest<Event>(entityName: "Event")
        let hasNonNoneAlert = NSPredicate(format: "alert != %@ AND alert != nil", "None")
        let hasNoneAlertWithTime = NSPredicate(format: "(alert == %@ OR alert == nil) AND (startTime != nil OR date != nil)", "None")
        eventFetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [hasNonNoneAlert, hasNoneAlertWithTime])
        
        if let events = try? context.fetch(eventFetchRequest) {
            #if DEBUG
            print("📅 Found \(events.count) events with alerts or times")
            #endif
            for event in events {
                // Cancel existing notifications
                if let eventId = event.id?.uuidString {
                    cancelAllNotifications(for: eventId, itemType: "event")
                }
                // Reschedule
                scheduleNotification(for: event)
            }
        }
        
        // Fetch all incomplete reminders with non-"None" alerts OR with "None" alert but having a time/date
        let reminderFetchRequest = NSFetchRequest<Reminder>(entityName: "Reminder")
        let hasNonNoneAlertReminder = NSPredicate(format: "isCompleted == NO AND alert != %@ AND alert != nil", "None")
        let hasNoneAlertWithTimeReminder = NSPredicate(format: "isCompleted == NO AND (alert == %@ OR alert == nil) AND (time != nil OR date != nil)", "None")
        reminderFetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [hasNonNoneAlertReminder, hasNoneAlertWithTimeReminder])
        
        if let reminders = try? context.fetch(reminderFetchRequest) {
            #if DEBUG
            print("📋 Found \(reminders.count) reminders with alerts or times")
            #endif
            for reminder in reminders {
                // Cancel existing notifications
                if let reminderId = reminder.id?.uuidString {
                    cancelAllNotifications(for: reminderId, itemType: "reminder")
                }
                // Reschedule
                scheduleNotification(for: reminder)
            }
        }

        if NSEntityDescription.entity(forEntityName: "Habit", in: context) != nil {
            let habitFetchRequest = NSFetchRequest<Habit>(entityName: "Habit")
            let hasNonNoneAlertHabit = NSPredicate(format: "alert != %@ AND alert != nil", "None")
            let hasNoneAlertWithTimeHabit = NSPredicate(format: "(alert == %@ OR alert == nil) AND (time != nil OR date != nil)", "None")
            habitFetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [hasNonNoneAlertHabit, hasNoneAlertWithTimeHabit])

            if let habits = try? context.fetch(habitFetchRequest) {
                #if DEBUG
                print("🏃 Found \(habits.count) habits with alerts or times")
                #endif
                for habit in habits {
                    if let habitId = habit.id?.uuidString {
                        cancelAllNotifications(for: habitId, itemType: "habit")
                    }
                    scheduleNotification(for: habit)
                }
            }
        }

        // Re-register system alarms via AlarmKit (not local notifications).
        if NSEntityDescription.entity(forEntityName: "Alarm", in: context) != nil {
            let alarmFetchRequest = NSFetchRequest<Alarm>(entityName: "Alarm")
            alarmFetchRequest.predicate = NSPredicate(format: "time != nil")
            if let alarms = try? context.fetch(alarmFetchRequest) {
                Task { @MainActor in
                    await AlarmKitScheduler.rescheduleAll(alarms: alarms)
                }
            }
        }
        
        #if DEBUG
        print("✅ Finished rescheduling notifications")
        #endif
    }
}

/// Alert options for notifications
enum AlertOption: String, CaseIterable {
    case none = "None"
    case atTime = "At time of event"
    case fiveMinutes = "5 minutes before"
    case fifteenMinutes = "15 minutes before"
    case thirtyMinutes = "30 minutes before"
    case oneHour = "1 hour before"
    case twoHours = "2 hours before"
    case oneDay = "1 day before"

    var localizedTitle: String {
        String(localized: String.LocalizationValue(rawValue))
    }
    
    var isBeforeAlert: Bool {
        switch self {
        case .none, .atTime:
            return false
        case .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .oneDay:
            return true
        }
    }
    
    var timeLeftBody: String {
        switch self {
        case .none, .atTime:
            return String(localized: "It's time")
        case .fiveMinutes:
            return String(localized: "5 minutes left")
        case .fifteenMinutes:
            return String(localized: "15 minutes left")
        case .thirtyMinutes:
            return String(localized: "30 minutes left")
        case .oneHour:
            return String(localized: "1 hour left")
        case .twoHours:
            return String(localized: "2 hours left")
        case .oneDay:
            return String(localized: "1 day left")
        }
    }

    func notificationBody(itemDate: Date, now: Date = Date()) -> String {
        switch self {
        case .none, .atTime:
            return Self.relativeDayTimeBody(for: itemDate, now: now)
        default:
            return timeLeftBody
        }
    }

    static func relativeDayTimeBody(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = "HH:mm"
        let timeText = timeFormatter.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today, \(timeText)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday, \(timeText)")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "d MMM"
        return "\(dateFormatter.string(from: date)), \(timeText)"
    }
    
    func calculateDate(from date: Date) -> Date? {
        switch self {
        case .none:
            return nil
        case .atTime:
            return date
        case .fiveMinutes:
            return Calendar.current.date(byAdding: .minute, value: -5, to: date)
        case .fifteenMinutes:
            return Calendar.current.date(byAdding: .minute, value: -15, to: date)
        case .thirtyMinutes:
            return Calendar.current.date(byAdding: .minute, value: -30, to: date)
        case .oneHour:
            return Calendar.current.date(byAdding: .hour, value: -1, to: date)
        case .twoHours:
            return Calendar.current.date(byAdding: .hour, value: -2, to: date)
        case .oneDay:
            return Calendar.current.date(byAdding: .day, value: -1, to: date)
        }
    }
}

/// Repeat options for events and reminders
enum RepeatOption: String, CaseIterable {
    case never = "Never"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"

    var localizedTitle: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

