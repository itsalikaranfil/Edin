//
//  AlarmOptions.swift
//  One
//

import Foundation
import CoreData

enum AlarmSound: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case radar = "Radar"
    case apex = "Apex"
    case chord = "Chord"
    case waves = "Waves"
    case none = "None"

    var id: String { rawValue }

    var localizedTitle: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

enum AlarmSnoozeDuration: Int, CaseIterable, Identifiable {
    case one = 1
    case five = 5
    case nine = 9
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .one: return String(localized: "1 Minute")
        case .five: return String(localized: "5 Minutes")
        case .nine: return String(localized: "9 Minutes")
        case .fifteen: return String(localized: "15 Minutes")
        case .thirty: return String(localized: "30 Minutes")
        case .sixty: return String(localized: "1 Hour")
        }
    }

    static func from(minutes: Int16) -> AlarmSnoozeDuration {
        AlarmSnoozeDuration(rawValue: Int(minutes)) ?? .nine
    }
}

/// Calendar weekday integers (1 = Sunday … 7 = Saturday), matching `Calendar.Component.weekday`.
enum AlarmWeekdays {
    static let all: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    static let weekdays: Set<Int> = [2, 3, 4, 5, 6] // Mon–Fri
    static let weekends: Set<Int> = [1, 7] // Sun, Sat

    static func encode(_ days: Set<Int>) -> String? {
        let valid = days.filter { (1...7).contains($0) }.sorted()
        guard !valid.isEmpty else { return nil }
        return valid.map(String.init).joined(separator: ",")
    }

    static func decode(_ raw: String?) -> Set<Int> {
        guard let raw, !raw.isEmpty else { return [] }
        return Set(
            raw.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...7).contains($0) }
        )
    }

    /// Ordered weekdays for UI, starting at the locale's first weekday.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    static func shortSymbol(for weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    static func fullSymbol(for weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    /// Apple Clock–style summary for the alarm list / Repeat row.
    static func displayTitle(for days: Set<Int>, calendar: Calendar = .current) -> String {
        let valid = days.filter { (1...7).contains($0) }
        if valid.isEmpty { return String(localized: "Never") }
        if valid == all { return String(localized: "Every day") }
        if valid == weekdays { return String(localized: "Weekdays") }
        if valid == weekends { return String(localized: "Weekends") }
        if valid.count == 1, let day = valid.first {
            return String(localized: "Every \(fullSymbol(for: day, calendar: calendar))")
        }

        return orderedWeekdays(calendar: calendar)
            .filter { valid.contains($0) }
            .map { shortSymbol(for: $0, calendar: calendar) }
            .joined(separator: ", ")
    }

    /// Resolve weekdays from stored field, migrating legacy `repeatOption` when needed.
    static func resolved(for alarm: Alarm, calendar: Calendar = .current) -> Set<Int> {
        if alarm.entity.attributesByName["repeatWeekdays"] != nil {
            // `nil` = never written (legacy) → migrate. `""` = explicit Never from new UI.
            if let raw = alarm.value(forKey: "repeatWeekdays") as? String {
                return decode(raw)
            }
        }
        return migrated(from: RepeatOption(rawValue: alarm.repeatOption ?? "") ?? .never, time: alarm.time, calendar: calendar)
    }

    static func migrated(from option: RepeatOption, time: Date?, calendar: Calendar = .current) -> Set<Int> {
        switch option {
        case .never, .monthly, .yearly:
            return []
        case .daily:
            return all
        case .weekly:
            guard let time else { return [] }
            return [calendar.component(.weekday, from: time)]
        }
    }

    /// Compat `repeatOption` string persisted alongside weekdays.
    static func legacyRepeatOption(for days: Set<Int>) -> String {
        if days.isEmpty { return RepeatOption.never.rawValue }
        if days == all { return RepeatOption.daily.rawValue }
        return RepeatOption.weekly.rawValue
    }

    static func setWeekdays(_ days: Set<Int>, on alarm: Alarm) {
        let encoded = encode(days) ?? ""
        if alarm.entity.attributesByName["repeatWeekdays"] != nil {
            alarm.willChangeValue(forKey: "repeatWeekdays")
            alarm.setValue(encoded, forKey: "repeatWeekdays")
            alarm.didChangeValue(forKey: "repeatWeekdays")
        }
        alarm.repeatOption = legacyRepeatOption(for: days)
    }
}

extension RepeatOption {
    var alarmListTitle: String {
        switch self {
        case .never: return String(localized: "Never")
        case .daily: return String(localized: "Every day")
        case .weekly: return String(localized: "Every week")
        case .monthly: return String(localized: "Every month")
        case .yearly: return String(localized: "Every year")
        }
    }
}

enum AlarmDaySchedule {
    /// Whether an enabled alarm would fire on the given calendar day.
    static func fires(on day: Date, alarm: Alarm, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        guard alarm.isEnabled, let time = alarm.time else { return false }
        let days = AlarmWeekdays.resolved(for: alarm, calendar: calendar)
        let dayStart = calendar.startOfDay(for: day)

        if days.isEmpty {
            return calendar.isDate(dayStart, inSameDayAs: nextNeverFireDay(time: time, calendar: calendar, now: now))
        }
        return days.contains(calendar.component(.weekday, from: day))
    }

    static func countFiring(on day: Date, in alarms: [Alarm], calendar: Calendar = .current, now: Date = Date()) -> Int {
        alarms.reduce(0) { partial, alarm in
            partial + (fires(on: day, alarm: alarm, calendar: calendar, now: now) ? 1 : 0)
        }
    }

    /// One-shot (Never) alarm whose scheduled calendar day is already in the past.
    static func isSpentOneShot(_ alarm: Alarm, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        let days = AlarmWeekdays.resolved(for: alarm, calendar: calendar)
        guard days.isEmpty, let time = alarm.time else { return false }
        return calendar.startOfDay(for: time) < calendar.startOfDay(for: now)
    }

    /// Next calendar day a one-shot (Never) alarm fires: today if that time is still ahead, otherwise tomorrow.
    static func nextNeverFireDay(time: Date, calendar: Calendar = .current, now: Date = Date()) -> Date {
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let todayFire = calendar.date(from: components), todayFire > now {
            return calendar.startOfDay(for: todayFire)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.startOfDay(for: tomorrow)
    }
}
