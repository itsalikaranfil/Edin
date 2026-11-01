import WidgetKit
import Foundation

struct OneWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct OneWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> OneWidgetEntry {
        OneWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (OneWidgetEntry) -> Void) {
        completion(OneWidgetEntry(date: Date(), snapshot: Self.loadDisplaySnapshot().snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OneWidgetEntry>) -> Void) {
        let cal = Calendar.current
        let now = Date()
        let nextMidnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now)!)
        let postMidnightRefresh = cal.date(byAdding: .minute, value: 5, to: nextMidnight) ?? nextMidnight

        // Commit expirations only for the current moment — never while simulating the future entry
        // (that was clearing checkmarks before the widget could show them).
        let current = Self.loadDisplaySnapshot(now: now, commitExpirations: true)
        var entries: [OneWidgetEntry] = [
            OneWidgetEntry(date: now, snapshot: current.snapshot)
        ]

        if let completionRefresh = current.nextCompletionRefresh {
            let later = Self.loadDisplaySnapshot(now: completionRefresh, commitExpirations: false)
            entries.append(OneWidgetEntry(date: completionRefresh, snapshot: later.snapshot))
            let policyDate = min(completionRefresh, postMidnightRefresh)
            completion(Timeline(entries: entries, policy: .after(policyDate)))
            return
        }

        entries.append(OneWidgetEntry(date: postMidnightRefresh, snapshot: current.snapshot))
        completion(Timeline(entries: entries, policy: .after(postMidnightRefresh)))
    }

    private static func loadDisplaySnapshot(
        now: Date = Date(),
        commitExpirations: Bool = false
    ) -> (snapshot: WidgetSnapshot?, nextCompletionRefresh: Date?) {
        guard let loaded = WidgetSnapshot.load() else {
            return (nil, nil)
        }
        return WidgetPendingCompletions.applyCompletingState(
            to: loaded,
            now: now,
            commitExpirations: commitExpirations
        )
    }
}
