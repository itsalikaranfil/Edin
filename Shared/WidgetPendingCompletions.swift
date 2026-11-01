import Foundation
import WidgetKit

/// One completion requested from a widget check tap, applied by the main app later.
struct WidgetPendingCompletion: Codable, Equatable {
    /// `reminder` or `habit`
    var kind: String
    /// Core Data entity UUID string
    var itemID: String
    /// Habit occurrence day (`yyyy-MM-dd`); nil for reminders
    var occurrenceDayKey: String?
}

enum WidgetPendingCompletions {
    static let fileName = "widgetPendingCompletions.json"
    static let completingFileName = "widgetCompletingRows.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)?
            .appendingPathComponent(fileName)
    }

    static var completingURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)?
            .appendingPathComponent(completingFileName)
    }

    static func enqueue(_ item: WidgetPendingCompletion) {
        var items = load()
        if !items.contains(item) {
            items.append(item)
        }
        write(items)
    }

    /// Returns pending items and clears the queue file.
    static func loadAndClear() -> [WidgetPendingCompletion] {
        let items = load()
        write([])
        return items
    }

    static func load() -> [WidgetPendingCompletion] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetPendingCompletion].self, from: data)) ?? []
    }

    // MARK: - Checkmark overlay (rowID -> startedAt)

    /// Marks a row as showing its checkmark and reloads timelines immediately.
    static func markCompleting(rowID: String, at date: Date = Date()) {
        var map = loadCompletingMap()
        map[rowID] = date.timeIntervalSince1970
        writeCompletingMap(map)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadCompletingMap() -> [String: TimeInterval] {
        guard let url = completingURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }

    static func writeCompletingMap(_ map: [String: TimeInterval]) {
        guard let url = completingURL else { return }
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func isCompleting(rowID: String, now: Date = Date()) -> Bool {
        guard let started = loadCompletingMap()[rowID] else { return false }
        return now.timeIntervalSince1970 - started < WidgetSnapshot.completingCheckmarkDuration
    }

    /// Applies checkmarks / drops expired completing rows.
    /// Only mutates the completing store / snapshot on disk when `commitExpirations` is true
    /// (so building a future timeline entry does not wipe the checkmark state early).
    static func applyCompletingState(
        to snapshot: WidgetSnapshot,
        now: Date = Date(),
        commitExpirations: Bool = false
    ) -> (snapshot: WidgetSnapshot, nextCompletionRefresh: Date?) {
        let duration = WidgetSnapshot.completingCheckmarkDuration
        var map = loadCompletingMap()
        var expiredIDs = Set<String>()
        var activeIDs = Set<String>()
        var nextRefresh: Date?
        let nowTs = now.timeIntervalSince1970

        for (rowID, started) in map {
            let expiresAt = started + duration
            if expiresAt <= nowTs {
                expiredIDs.insert(rowID)
            } else {
                activeIDs.insert(rowID)
                let expiresDate = Date(timeIntervalSince1970: expiresAt)
                if let current = nextRefresh {
                    nextRefresh = min(current, expiresDate)
                } else {
                    nextRefresh = expiresDate
                }
            }
        }

        if commitExpirations, !expiredIDs.isEmpty {
            for id in expiredIDs {
                map.removeValue(forKey: id)
            }
            writeCompletingMap(map)
            var cleaned = snapshot.markingRowsCompleting(ids: activeIDs, startedAt: now)
            for id in expiredIDs {
                cleaned = cleaned.removingRow(id: id)
            }
            writeSnapshot(cleaned)
        }

        var result = snapshot.markingRowsCompleting(ids: activeIDs, startedAt: now)
        for id in expiredIDs {
            result = result.removingRow(id: id)
        }

        return (result, nextRefresh)
    }

    private static func write(_ items: [WidgetPendingCompletion]) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func writeSnapshot(_ snapshot: WidgetSnapshot) {
        guard let url = WidgetSnapshot.snapshotURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension WidgetSnapshot {
    func markingRowsCompleting(ids: Set<String>, startedAt: Date) -> WidgetSnapshot {
        guard !ids.isEmpty else { return self }
        func mark(_ rows: [WidgetRow]) -> [WidgetRow] {
            rows.map { row in
                guard ids.contains(row.id) else { return row }
                var updated = row
                updated.isCompleting = true
                updated.completingStartedAt = startedAt
                return updated
            }
        }
        let sections = afterTodaySections?.map { section in
            WidgetDatedSection(title: section.title, rows: mark(section.rows))
        }
        return WidgetSnapshot(
            generatedAt: generatedAt,
            todayRows: mark(todayRows),
            tomorrowRows: mark(tomorrowRows),
            afterTodaySections: sections,
            todayHadCompletedItems: todayHadCompletedItems
        )
    }

    func removingRow(id: String) -> WidgetSnapshot {
        let filteredSections = afterTodaySections?.compactMap { section -> WidgetDatedSection? in
            let rows = section.rows.filter { $0.id != id }
            guard !rows.isEmpty else { return nil }
            return WidgetDatedSection(title: section.title, rows: rows)
        }
        // Optimistic removal of a Today row means that day had a completed item.
        let removedFromToday = todayRows.contains { $0.id == id }
        return WidgetSnapshot(
            generatedAt: generatedAt,
            todayRows: todayRows.filter { $0.id != id },
            tomorrowRows: tomorrowRows.filter { $0.id != id },
            afterTodaySections: filteredSections,
            todayHadCompletedItems: removedFromToday ? true : todayHadCompletedItems
        )
    }
}

extension WidgetRow {
    /// Core Data UUID for pending completion (strips habit day-key suffix when present).
    var entityIDForCompletion: String {
        if kind == .habit,
           let key = occurrenceDayKey,
           id.hasSuffix("-\(key)") {
            return String(id.dropLast(key.count + 1))
        }
        return id
    }
}
