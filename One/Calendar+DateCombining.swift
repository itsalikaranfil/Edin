//
//  Calendar+DateCombining.swift
//  One
//

import Foundation

extension Calendar {
    /// Combines the calendar day from `day` with the time-of-day from `time`.
    func combining(day: Date, andTimeFrom time: Date) -> Date {
        let dayComponents = dateComponents([.year, .month, .day], from: day)
        let timeComponents = dateComponents([.hour, .minute, .second], from: time)

        var combined = DateComponents()
        combined.year = dayComponents.year
        combined.month = dayComponents.month
        combined.day = dayComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        // Notifications are minute-granular; keep seconds at 0 so the fire minute isn't already "past".
        combined.second = 0

        return self.date(from: combined) ?? day
    }

    /// True when `date`'s calendar day is strictly before today (day-based overdue).
    func isDayBeforeToday(_ date: Date) -> Bool {
        startOfDay(for: date) < startOfDay(for: Date())
    }
}
