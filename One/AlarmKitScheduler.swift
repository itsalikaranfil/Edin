//
//  AlarmKitScheduler.swift
//  One
//

import AlarmKit
import ActivityKit
import Foundation
import SwiftUI

@MainActor
enum AlarmKitScheduler {
    private static var manager: AlarmManager { .shared }

    static func requestAuthorizationIfNeeded() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await manager.requestAuthorization() == .authorized
            } catch {
                #if DEBUG
                print("❌ AlarmKit authorization failed: \(error)")
                #endif
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Schedules a system alarm for a Core Data `Alarm` entity.
    static func schedule(alarm storedAlarm: Alarm) async {
        guard let id = storedAlarm.id else { return }
        cancel(id: id)

        guard storedAlarm.isEnabled, let time = storedAlarm.time else { return }
        guard await requestAuthorizationIfNeeded() else {
            #if DEBUG
            print("⚠️ AlarmKit not authorized — alarm not scheduled")
            #endif
            return
        }

        let label = storedAlarm.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Alarm"
        let weekdays = AlarmWeekdays.resolved(for: storedAlarm)
        let snoozeEnabled = storedAlarm.snoozeEnabled
        let snoozeSeconds = TimeInterval(max(1, Int(storedAlarm.snoozeDurationMinutes)) * 60)

        let stopButton = AlarmButton(
            text: LocalizedStringResource("Stop"),
            textColor: .white,
            systemImageName: "stop.circle.fill"
        )
        let snoozeButton = AlarmButton(
            text: LocalizedStringResource("Snooze"),
            textColor: .white,
            systemImageName: "moon.zzz.fill"
        )

        let alert: AlarmPresentation.Alert
        if snoozeEnabled {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: label),
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .countdown
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: label),
                stopButton: stopButton
            )
        }

        let countdown = snoozeEnabled
            ? AlarmPresentation.Countdown(
                title: LocalizedStringResource("Snoozed"),
                pauseButton: nil
            )
            : nil

        let presentation = AlarmPresentation(alert: alert, countdown: countdown)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: EdinAlarmMetadata(label: label),
            tintColor: Color.alarmOrange
        )

        let countdownDuration: AlarmKit.Alarm.CountdownDuration? = snoozeEnabled
            ? AlarmKit.Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeSeconds)
            : nil

        let schedule = makeSchedule(time: time, weekdays: weekdays)
        let sound = alertSound(for: AlarmSound(rawValue: storedAlarm.sound ?? "") ?? .default)

        let configuration = AlarmManager.AlarmConfiguration<EdinAlarmMetadata>(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            sound: sound
        )

        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            #if DEBUG
            print("✅ Scheduled AlarmKit alarm \(id) — \(label)")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to schedule AlarmKit alarm \(id): \(error)")
            #endif
        }
    }

    static func cancel(id: UUID) {
        do {
            try manager.cancel(id: id)
        } catch {
            #if DEBUG
            print("⚠️ AlarmKit cancel \(id): \(error)")
            #endif
        }
    }

    static func rescheduleAll(alarms: [Alarm]) async {
        _ = await requestAuthorizationIfNeeded()
        for storedAlarm in alarms {
            await schedule(alarm: storedAlarm)
        }
    }

    private static func makeSchedule(time: Date, weekdays: Set<Int>) -> AlarmKit.Alarm.Schedule {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        let relativeTime = AlarmKit.Alarm.Schedule.Relative.Time(hour: hour, minute: minute)

        if weekdays.isEmpty {
            return .relative(
                AlarmKit.Alarm.Schedule.Relative(time: relativeTime, repeats: .never)
            )
        }

        let localeDays = weekdays.compactMap(localeWeekday(fromCalendarWeekday:)).sorted { lhs, rhs in
            weekdaySortIndex(lhs) < weekdaySortIndex(rhs)
        }
        return .relative(
            AlarmKit.Alarm.Schedule.Relative(
                time: relativeTime,
                repeats: .weekly(localeDays)
            )
        )
    }

    private static func localeWeekday(fromCalendarWeekday weekday: Int) -> Locale.Weekday? {
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    private static func weekdaySortIndex(_ day: Locale.Weekday) -> Int {
        switch day {
        case .sunday: return 0
        case .monday: return 1
        case .tuesday: return 2
        case .wednesday: return 3
        case .thursday: return 4
        case .friday: return 5
        case .saturday: return 6
        @unknown default: return 7
        }
    }

    private static func alertSound(for sound: AlarmSound) -> AlertConfiguration.AlertSound {
        switch sound {
        case .none:
            return .default
        case .default, .radar, .apex, .chord, .waves:
            return .default
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
