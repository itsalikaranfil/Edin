import Foundation
import CoreData

/// Applies widget-initiated completions to Core Data when the main app is active.
enum WidgetPendingCompletionDrainer {
    @MainActor
    static func drain() {
        let pending = WidgetPendingCompletions.loadAndClear()
        guard !pending.isEmpty else { return }

        let context = PersistenceController.shared.container.viewContext
        var didChange = false

        for item in pending {
            guard let uuid = UUID(uuidString: item.itemID) else { continue }

            switch item.kind {
            case WidgetRowKind.reminder.rawValue:
                let request = NSFetchRequest<Reminder>(entityName: "Reminder")
                request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                request.fetchLimit = 1
                if let reminder = try? context.fetch(request).first {
                    _ = reminder.completeOrRollForward()
                    didChange = true
                }
            case WidgetRowKind.habit.rawValue:
                let request = NSFetchRequest<Habit>(entityName: "Habit")
                request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                request.fetchLimit = 1
                if let habit = try? context.fetch(request).first {
                    let day: Date
                    if let key = item.occurrenceDayKey,
                       let parsed = Recurrence.date(fromDayKey: key) {
                        day = parsed
                    } else {
                        day = Calendar.current.startOfDay(for: Date())
                    }
                    habit.setCompleted(true, on: day)
                    didChange = true
                }
            default:
                continue
            }
        }

        guard didChange else {
            // Re-export so optimistic removals stay aligned if nothing applied.
            WidgetSnapshotExporter.shared.scheduleExport()
            return
        }

        PersistenceController.shared.save()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
    }
}
