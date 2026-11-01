import AppIntents
import Foundation

/// Completes a reminder or habit from a home-screen widget check control.
struct CompleteWidgetItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Item"
    static var description = IntentDescription("Marks a reminder or habit complete from the widget.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Kind")
    var kind: String

    /// Core Data entity UUID string
    @Parameter(title: "Item ID")
    var itemID: String

    /// Widget row id (occurrence-scoped for habits)
    @Parameter(title: "Row ID")
    var rowID: String

    @Parameter(title: "Occurrence Day Key")
    var occurrenceDayKey: String?

    init() {
        kind = ""
        itemID = ""
        rowID = ""
        occurrenceDayKey = nil
    }

    init(kind: String, itemID: String, rowID: String, occurrenceDayKey: String? = nil) {
        self.kind = kind
        self.itemID = itemID
        self.rowID = rowID
        self.occurrenceDayKey = occurrenceDayKey
    }

    func perform() async throws -> some IntentResult {
        guard kind == WidgetRowKind.reminder.rawValue || kind == WidgetRowKind.habit.rawValue else {
            return .result()
        }
        WidgetPendingCompletions.enqueue(
            WidgetPendingCompletion(
                kind: kind,
                itemID: itemID,
                occurrenceDayKey: occurrenceDayKey
            )
        )
        // Return immediately after marking so the widget can reload and show the checkmark.
        // The timeline provider drops the row after `completingCheckmarkDuration`.
        WidgetPendingCompletions.markCompleting(rowID: rowID)
        return .result()
    }
}
