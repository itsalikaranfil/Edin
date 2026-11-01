//
//  ChecklistStore.swift
//  One
//

import CoreData

/// Staged checklist row for the create/edit forms. Cancel discards because edits
/// only ever live in `@State`, matching how attachments work.
struct ChecklistDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    /// Set for rows that are already persisted, nil for newly typed ones.
    var existingObjectID: NSManagedObjectID?

    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func empty() -> ChecklistDraft {
        ChecklistDraft(id: UUID(), title: "", isCompleted: false, existingObjectID: nil)
    }
}

/// Lightweight handle used by the read-only detail sheet.
struct ChecklistRef: Identifiable, Equatable {
    let id: UUID
    let objectID: NSManagedObjectID
    let title: String
    let isCompleted: Bool
}

enum ChecklistStore {
    // MARK: - Reading

    static func items(of owner: ItemOwner) -> [ChecklistItem] {
        let object = owner.object
        guard object.entity.relationshipsByName.keys.contains("checklistItems") else { return [] }
        let stored = object.value(forKey: "checklistItems") as? Set<ChecklistItem> ?? []
        return stored.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            let lhsDate = lhs.createdAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return (lhs.title ?? "") < (rhs.title ?? "")
        }
    }

    static func drafts(of owner: ItemOwner) -> [ChecklistDraft] {
        items(of: owner).map { item in
            ChecklistDraft(
                id: item.id ?? UUID(),
                title: item.title ?? "",
                isCompleted: item.isCompleted,
                existingObjectID: item.objectID
            )
        }
    }

    static func refs(of owner: ItemOwner) -> [ChecklistRef] {
        items(of: owner).map { item in
            ChecklistRef(
                id: item.id ?? UUID(),
                objectID: item.objectID,
                title: (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                isCompleted: item.isCompleted
            )
        }
        .filter { !$0.title.isEmpty }
    }

    static func progress(of owner: ItemOwner) -> (completed: Int, total: Int) {
        let refs = refs(of: owner)
        return (refs.filter(\.isCompleted).count, refs.count)
    }

    // MARK: - Writing

    /// Commits a staged list: drops blank titles, deletes items removed from the drafts,
    /// inserts new ones, updates titles and completion, and renumbers `sortOrder`.
    static func apply(_ drafts: [ChecklistDraft], to owner: ItemOwner, context: NSManagedObjectContext) {
        guard owner.object.entity.relationshipsByName.keys.contains("checklistItems") else { return }

        let kept = drafts.filter { !$0.isBlank }
        let keptObjectIDs = Set(kept.compactMap(\.existingObjectID))
        for item in items(of: owner) where !keptObjectIDs.contains(item.objectID) {
            context.delete(item)
        }

        for (index, draft) in kept.enumerated() {
            let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let objectID = draft.existingObjectID,
               let item = try? context.existingObject(with: objectID) as? ChecklistItem {
                item.title = trimmed
                item.isCompleted = draft.isCompleted
                item.sortOrder = Int16(clamping: index)
                continue
            }

            let item = ChecklistItem(context: context)
            item.id = draft.id
            item.createdAt = Date()
            item.title = trimmed
            item.isCompleted = draft.isCompleted
            item.sortOrder = Int16(clamping: index)
            switch owner {
            case .event(let event): item.event = event
            case .reminder(let reminder): item.reminder = reminder
            case .habit(let habit): item.habit = habit
            }
        }
    }

    /// Immediate-save path used by the read-only detail sheet.
    static func setCompleted(_ completed: Bool, for ref: ChecklistRef, context: NSManagedObjectContext) {
        guard let item = try? context.existingObject(with: ref.objectID) as? ChecklistItem else { return }
        item.isCompleted = completed
    }
}
