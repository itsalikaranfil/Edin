//
//  FolderStore.swift
//  One
//

import CoreData

enum FolderStore {
    static let inboxFolderName = "Inbox"

    static func ensureInboxExists(context: NSManagedObjectContext) {
        deduplicateInboxFolders(context: context)
    }

    static func isInbox(_ folder: Folder) -> Bool {
        isReservedInboxName(folder.name ?? "")
    }

    static func isReservedInboxName(_ name: String) -> Bool {
        normalizedFolderName(name) == normalizedFolderName(inboxFolderName)
    }

    /// Localized display name. Inbox stays stored as English `"Inbox"` in Core Data.
    static func displayName(for folder: Folder) -> String {
        if isInbox(folder) { return String(localized: "Inbox") }
        return folder.name ?? String(localized: "Untitled")
    }

    static func displayName(forName name: String?) -> String {
        guard let name, !name.isEmpty else {
            return String(localized: "Untitled")
        }
        if isReservedInboxName(name) { return String(localized: "Inbox") }
        return name
    }

    static func rename(_ folder: Folder, to name: String, context: NSManagedObjectContext) {
        guard !isInbox(folder) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isReservedInboxName(trimmed) else { return }
        folder.name = trimmed
        PersistenceController.shared.save()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
    }

    static func fetchAll(context: NSManagedObjectContext) -> [Folder] {
        guard NSEntityDescription.entity(forEntityName: "Folder", in: context) != nil else {
            return []
        }
        deduplicateInboxFolders(context: context)
        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
        return (try? context.fetch(request)) ?? []
    }

    private static func normalizedFolderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func deduplicateInboxFolders(context: NSManagedObjectContext) {
        guard NSEntityDescription.entity(forEntityName: "Folder", in: context) != nil else { return }

        let request = NSFetchRequest<Folder>(entityName: "Folder")
        guard let allFolders = try? context.fetch(request) else { return }

        let inboxFolders = allFolders.filter { isInbox($0) }

        if inboxFolders.isEmpty {
            let inbox = Folder(context: context)
            inbox.id = UUID()
            inbox.name = inboxFolderName
            inbox.sortOrder = 0
            PersistenceController.shared.save()
            return
        }

        if inboxFolders.count == 1 {
            let inbox = inboxFolders[0]
            var didChange = false
            if inbox.name != inboxFolderName {
                inbox.name = inboxFolderName
                didChange = true
            }
            if inbox.sortOrder != 0 {
                inbox.sortOrder = 0
                didChange = true
            }
            if didChange || context.hasChanges {
                PersistenceController.shared.save()
            }
            return
        }

        guard let canonical = inboxFolders.max(by: { lhs, rhs in
            let lhsCount = itemCount(for: lhs)
            let rhsCount = itemCount(for: rhs)
            if lhsCount != rhsCount {
                return lhsCount < rhsCount
            }
            return lhs.sortOrder > rhs.sortOrder
        }) else { return }

        for duplicate in inboxFolders where duplicate.objectID != canonical.objectID {
            if let events = duplicate.events as? Set<Event> {
                for event in events {
                    event.folder = canonical
                }
            }
            if let reminders = duplicate.reminders as? Set<Reminder> {
                for reminder in reminders {
                    reminder.folder = canonical
                }
            }
            context.delete(duplicate)
        }

        canonical.name = inboxFolderName
        canonical.sortOrder = 0
        PersistenceController.shared.save()
    }

    private static func itemCount(for folder: Folder) -> Int {
        let eventCount = (folder.events as? Set<Event>)?.count ?? 0
        let reminderCount = (folder.reminders as? Set<Reminder>)?.count ?? 0
        return eventCount + reminderCount
    }
}
