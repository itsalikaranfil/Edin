//
//  HabitStatsSheet.swift
//  One
//

import SwiftUI
import CoreData

/// Trailing liquid-glass flame pill: flag-red glyph, soft paywall-red glass tint.
struct HabitFlamePill: View {
    var streak: Int

    private var pillTintRed: Color {
        Color(red: 1.0, green: 0.12, blue: 0.14).opacity(0.12)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("\(streak)")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(Color.flagRed)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(pillTintRed), in: .capsule)
        .allowsHitTesting(false)
    }
}

/// Compact completion squares for habit details (and the stats sheet card).
struct HabitActivityGrid: View {
    @ObservedObject var habit: Habit
    var showsCardChrome: Bool = false

    private let calendar = Calendar.current
    private let gridColumns = 20
    private let gridRows = 7

    private var gridDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        let cellCount = gridColumns * gridRows
        guard let start = calendar.date(byAdding: .day, value: -(cellCount - 1), to: today) else {
            return []
        }
        return (0..<cellCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    var body: some View {
        let days = gridDays
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: gridColumns)

        let grid = LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        habit.isCompleted(on: day, calendar: calendar)
                            ? Color.flagRed.opacity(0.85)
                            : Color.primaryText.opacity(0.12)
                    )
                    .aspectRatio(1, contentMode: .fit)
            }
        }

        if showsCardChrome {
            grid
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(Color.pillBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            grid
        }
    }
}

/// Read-only habit overview: meta, streak, total days, activity grid.
struct HabitStatsSheet: View {
    @ObservedObject var habit: Habit
    var onClose: () -> Void

    private let calendar = Calendar.current

    private var totalDays: Int {
        habit.completedOccurrenceDays(calendar: calendar).count
    }

    private var currentStreak: Int {
        habit.currentStreak(calendar: calendar)
    }

    private var frequencyLabel: String {
        Recurrence.option(from: habit.repeatOption).alarmListTitle
    }

    private var startDateLabel: String {
        guard let date = habit.date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private var timeLabel: String {
        guard let time = habit.time else { return "—" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    metaCard(title: "Start date", value: startDateLabel)
                    metaCard(title: "Frequency", value: frequencyLabel)
                    metaCard(title: "Time", value: timeLabel)
                }

                HStack(spacing: 10) {
                    statCard(
                        icon: "flame.fill",
                        value: "\(currentStreak)",
                        label: "Current streak"
                    )
                    statCard(
                        icon: "calendar",
                        value: "\(totalDays)",
                        label: "Total Days"
                    )
                }

                HabitActivityGrid(habit: habit, showsCardChrome: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Habit")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text(habit.title ?? "Untitled Habit")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.primaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            SheetClosePill(action: onClose)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func metaCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.flagRed)
                Spacer()
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.primaryText)
            }
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let habit = Habit(context: context)
    habit.id = UUID()
    habit.title = "Run"
    habit.date = Date()
    habit.time = Date()
    habit.repeatOption = RepeatOption.daily.rawValue
    habit.setCompleted(true, on: Date())
    return HabitStatsSheet(habit: habit, onClose: {})
        .environment(\.managedObjectContext, context)
}
