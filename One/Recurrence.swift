//
//  Recurrence.swift
//  One
//
//  Expands repeatOption into calendar-day occurrences.
//

import Foundation
import CoreData

enum Recurrence {
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    static func dayKey(for day: Date, calendar: Calendar = .current) -> String {
        dayKeyFormatter.string(from: calendar.startOfDay(for: day))
    }

    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        guard let date = dayKeyFormatter.date(from: key) else { return nil }
        return calendar.startOfDay(for: date)
    }
    
    static func parseExcludedDates(_ raw: String?) -> Set<String> {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }
    
    static func encodeExcludedDates(_ keys: Set<String>) -> String? {
        guard !keys.isEmpty else { return nil }
        let sorted = keys.sorted()
        guard let data = try? JSONEncoder().encode(sorted),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    static func isExcluded(day: Date, excludedDates: String?, calendar: Calendar = .current) -> Bool {
        let keys = parseExcludedDates(excludedDates)
        guard !keys.isEmpty else { return false }
        return keys.contains(dayKey(for: day, calendar: calendar))
    }
    
    /// Whether an item with `baseDate` and `option` occurs on `day` (any time that calendar day).
    static func occurs(
        on day: Date,
        baseDate: Date,
        option: RepeatOption,
        excludedDates: String? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        if isExcluded(day: day, excludedDates: excludedDates, calendar: calendar) {
            return false
        }
        
        let dayStart = calendar.startOfDay(for: day)
        let baseStart = calendar.startOfDay(for: baseDate)
        
        switch option {
        case .never:
            return calendar.isDate(dayStart, inSameDayAs: baseStart)
            
        case .daily:
            return dayStart >= baseStart
            
        case .weekly:
            guard dayStart >= baseStart else { return false }
            return calendar.component(.weekday, from: dayStart)
                == calendar.component(.weekday, from: baseStart)
            
        case .monthly:
            guard dayStart >= baseStart else { return false }
            let baseDay = calendar.component(.day, from: baseStart)
            let dayOfMonth = calendar.component(.day, from: dayStart)
            let daysInMonth = calendar.range(of: .day, in: .month, for: dayStart)?.count ?? baseDay
            let targetDay = min(baseDay, daysInMonth)
            return dayOfMonth == targetDay
            
        case .yearly:
            guard dayStart >= baseStart else { return false }
            let baseMonth = calendar.component(.month, from: baseStart)
            let baseDay = calendar.component(.day, from: baseStart)
            let month = calendar.component(.month, from: dayStart)
            let dayOfMonth = calendar.component(.day, from: dayStart)
            guard month == baseMonth else { return false }
            let daysInMonth = calendar.range(of: .day, in: .month, for: dayStart)?.count ?? baseDay
            return dayOfMonth == min(baseDay, daysInMonth)
        }
    }
    
    /// Next occurrence strictly after `after` (compared at start-of-day).
    static func nextDate(
        after after: Date,
        baseDate: Date,
        option: RepeatOption,
        excludedDates: String? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        guard option != .never else { return nil }
        
        let afterStart = calendar.startOfDay(for: after)
        guard let cursor = calendar.date(byAdding: .day, value: 1, to: afterStart) else { return nil }
        
        let limitDays: Int
        switch option {
        case .never: return nil
        case .daily: limitDays = 400
        case .weekly: limitDays = 400
        case .monthly: limitDays = 400
        case .yearly: limitDays = 400
        }
        
        var day = cursor
        for _ in 0..<limitDays {
            if occurs(on: day, baseDate: baseDate, option: option, excludedDates: excludedDates, calendar: calendar) {
                return day
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
    
    /// Occurrence days in `[from, through]` inclusive (start-of-day).
    static func occurrenceDates(
        from: Date,
        through: Date,
        baseDate: Date,
        option: RepeatOption,
        excludedDates: String? = nil,
        calendar: Calendar = .current
    ) -> [Date] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return [] }
        
        var dates: [Date] = []
        var day = start
        while day <= end {
            if occurs(on: day, baseDate: baseDate, option: option, excludedDates: excludedDates, calendar: calendar) {
                dates.append(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }
    
    static func option(from raw: String?) -> RepeatOption {
        RepeatOption(rawValue: raw ?? RepeatOption.never.rawValue) ?? .never
    }
    
    static func excludedDatesValue(from object: NSManagedObject) -> String? {
        guard object.entity.attributesByName["excludedDates"] != nil else { return nil }
        return object.value(forKey: "excludedDates") as? String
    }
    
    static func setExcludedDates(_ raw: String?, on object: NSManagedObject) {
        guard object.entity.attributesByName["excludedDates"] != nil else { return }
        object.setValue(raw, forKey: "excludedDates")
    }
    
    static func exclude(day: Date, on object: NSManagedObject, calendar: Calendar = .current) {
        var keys = parseExcludedDates(excludedDatesValue(from: object))
        keys.insert(dayKey(for: day, calendar: calendar))
        setExcludedDates(encodeExcludedDates(keys), on: object)
    }
}

extension Reminder {
    var excludedDatesStorage: String? {
        get { Recurrence.excludedDatesValue(from: self) }
        set { Recurrence.setExcludedDates(newValue, on: self) }
    }
    
    /// Complete a reminder; repeating reminders roll `date` forward instead of staying completed.
    @discardableResult
    func completeOrRollForward(calendar: Calendar = .current) -> Bool {
        let option = Recurrence.option(from: repeatOption)
        guard option != .never, let baseDate = date,
              let next = Recurrence.nextDate(
                after: Date(),
                baseDate: baseDate,
                option: option,
                excludedDates: excludedDatesStorage,
                calendar: calendar
              ) else {
            isCompleted = true
            completionDate = Date()
            if let id = id?.uuidString {
                NotificationManager.shared.cancelAllNotifications(for: id, itemType: "reminder")
            }
            return true
        }
        
        date = calendar.startOfDay(for: next)
        if let time {
            self.time = calendar.combining(day: next, andTimeFrom: time)
        }
        isCompleted = false
        completionDate = nil
        
        if let id = id?.uuidString {
            NotificationManager.shared.cancelAllNotifications(for: id, itemType: "reminder")
            NotificationManager.shared.scheduleNotification(for: self)
        }
        return false
    }
}

extension Habit {
    var excludedDatesStorage: String? {
        get { Recurrence.excludedDatesValue(from: self) }
        set { Recurrence.setExcludedDates(newValue, on: self) }
    }

    var completedDatesStorage: String? {
        get {
            guard entity.attributesByName["completedDates"] != nil else { return nil }
            return value(forKey: "completedDates") as? String
        }
        set {
            guard entity.attributesByName["completedDates"] != nil else { return }
            setValue(newValue, forKey: "completedDates")
        }
    }

    /// Whether this habit is completed for a specific occurrence day.
    func isCompleted(on day: Date, calendar: Calendar = .current) -> Bool {
        let keys = Recurrence.parseExcludedDates(completedDatesStorage)
        return keys.contains(Recurrence.dayKey(for: day, calendar: calendar))
    }

    /// Toggle completion for one occurrence day only (other days stay unchanged).
    func setCompleted(_ completed: Bool, on day: Date, calendar: Calendar = .current) {
        var keys = Recurrence.parseExcludedDates(completedDatesStorage)
        let key = Recurrence.dayKey(for: day, calendar: calendar)
        if completed {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        completedDatesStorage = Recurrence.encodeExcludedDates(keys)

        let option = Recurrence.option(from: repeatOption)
        if option == .never {
            isCompleted = completed
            completionDate = completed ? Date() : nil
        } else {
            // Repeating habits stay active for other days; track latest completion for Completed list sorting.
            isCompleted = false
            if completed {
                completionDate = Date()
            } else if keys.isEmpty {
                completionDate = nil
            }
        }

        if let id = id?.uuidString {
            NotificationManager.shared.cancelAllNotifications(for: id, itemType: "habit")
            if !completed || option != .never {
                NotificationManager.shared.scheduleNotification(for: self)
            }
        }
    }

    /// Completed occurrence days for the Completed list.
    func completedOccurrenceDays(calendar: Calendar = .current) -> [Date] {
        Recurrence.parseExcludedDates(completedDatesStorage)
            .compactMap { Recurrence.date(fromDayKey: $0, calendar: calendar) }
            .sorted()
    }

    /// Consecutive completed days ending today, or yesterday if today is not completed yet.
    func currentStreak(calendar: Calendar = .current) -> Int {
        let completed = Set(
            completedOccurrenceDays(calendar: calendar).map {
                calendar.startOfDay(for: $0)
            }
        )
        guard !completed.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        var cursor = today
        if !completed.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  completed.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while completed.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}

extension Event {
    var excludedDatesStorage: String? {
        get { Recurrence.excludedDatesValue(from: self) }
        set { Recurrence.setExcludedDates(newValue, on: self) }
    }
}
