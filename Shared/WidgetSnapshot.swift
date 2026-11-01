import Foundation

// MARK: - Shared data model between the main app and the widget extension

/// One titled block after Today on medium/large widgets (e.g. "Tomorrow" or "Wed, 22 Jan").
struct WidgetDatedSection: Codable {
    var title: String
    var rows: [WidgetRow]
}

struct WidgetSnapshot: Codable {
    var generatedAt: Date
    var todayRows: [WidgetRow]
    /// Legacy: rows for calendar tomorrow only. Kept for decoding old snapshots; prefer `afterTodaySections`.
    var tomorrowRows: [WidgetRow]
    /// Sections after Today: single "Tomorrow" or multiple future days with date titles when tomorrow is empty.
    var afterTodaySections: [WidgetDatedSection]?
    /// True when at least one reminder/habit for today was already completed (empty Today ≠ never planned).
    var todayHadCompletedItems: Bool? = nil

    static let appGroupID = "group.com.ali.OneApp"
    static let fileName = "widgetSnapshot.json"

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// How long a completing checkmark stays visible before the row is dropped.
    static let completingCheckmarkDuration: TimeInterval = 1.0

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else { return nil }
        return snapshot.filteredForCurrentDate()
    }

    /// Rebucket stale snapshots to current day boundaries so Today doesn't go empty after midnight.
    private func filteredForCurrentDate(now: Date = Date()) -> WidgetSnapshot {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        guard
            let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart),
            let dayAfterStart = cal.date(byAdding: .day, value: 2, to: todayStart)
        else { return self }

        // Flatten all persisted rows, then dedupe by id so stale snapshots can be rebuilt safely.
        let flattened = todayRows + tomorrowRows + (afterTodaySections?.flatMap(\.rows) ?? [])
        var dedupedByID: [String: WidgetRow] = [:]
        for row in flattened {
            if let existing = dedupedByID[row.id] {
                if row.sortDate < existing.sortDate {
                    dedupedByID[row.id] = row
                }
            } else {
                dedupedByID[row.id] = row
            }
        }
        let rows = Array(dedupedByID.values).sorted { $0.sortDate < $1.sortDate }

        let rebucketedToday = rows.filter { row in
            row.sortDate >= todayStart && row.sortDate < tomorrowStart
        }
        let rebucketedTomorrow = rows.filter { row in
            row.sortDate >= tomorrowStart && row.sortDate < dayAfterStart
        }
        let futureRows = rows.filter { $0.sortDate >= dayAfterStart }
        let rebucketedSections = groupedFutureSections(from: futureRows, calendar: cal)

        // Keep the completed-today flag only while the snapshot is still for the current day.
        let keepCompletedFlag = Calendar.current.isDate(generatedAt, inSameDayAs: now)
            ? todayHadCompletedItems
            : nil

        return WidgetSnapshot(
            generatedAt: generatedAt,
            todayRows: rebucketedToday,
            tomorrowRows: rebucketedTomorrow,
            afterTodaySections: rebucketedSections,
            todayHadCompletedItems: keepCompletedFlag
        )
    }

    private func groupedFutureSections(from rows: [WidgetRow], calendar cal: Calendar) -> [WidgetDatedSection]? {
        guard !rows.isEmpty else { return nil }

        let grouped = Dictionary(grouping: rows) { row in
            cal.startOfDay(for: row.sortDate)
        }

        let sections = grouped.keys.sorted().compactMap { dayStart -> WidgetDatedSection? in
            guard let dayRows = grouped[dayStart], !dayRows.isEmpty else { return nil }
            return WidgetDatedSection(
                title: formatSectionDate(dayStart),
                rows: dayRows.sorted { $0.sortDate < $1.sortDate }
            )
        }
        return sections.isEmpty ? nil : sections
    }

    private func formatSectionDate(_ dayStart: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM"
        return f.string(from: dayStart)
    }
}

struct WidgetRow: Codable, Identifiable {
    var id: String
    var kind: WidgetRowKind
    var title: String
    var subtitle: String?
    var sortDate: Date
    /// Habit occurrence day key (`yyyy-MM-dd`); nil for events/reminders.
    var occurrenceDayKey: String? = nil
    /// True while the widget shows a checkmark before removing the row.
    var isCompleting: Bool? = nil
    /// When the checkmark started; used to drop the row on the next timeline tick.
    var completingStartedAt: Date? = nil
}

enum WidgetRowKind: String, Codable {
    case event
    case reminder
    case habit
}
