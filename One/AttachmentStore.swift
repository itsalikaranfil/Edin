//
//  AttachmentStore.swift
//  One
//

import CoreData
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Which item a child record (attachment, checklist item) hangs off.
/// Habits support checklists only.
enum ItemOwner {
    case event(Event)
    case reminder(Reminder)
    case habit(Habit)

    var object: NSManagedObject {
        switch self {
        case .event(let event): return event
        case .reminder(let reminder): return reminder
        case .habit(let habit): return habit
        }
    }
}

/// Staged attachment for the create/edit forms, so Cancel discards changes the same
/// way the rest of those forms do (edits only ever live in `@State`).
struct AttachmentDraft: Identifiable, Equatable {
    let id: UUID
    var filename: String
    var typeIdentifier: String?
    var byteCount: Int
    /// Set for attachments that are already persisted, nil for newly picked files.
    var existingObjectID: NSManagedObjectID?
    /// Bytes for newly picked files, nil for already-persisted attachments.
    var data: Data?

    var isNew: Bool { existingObjectID == nil }
}

/// Metadata-only handle used by the read-only detail sheet. Deliberately carries no
/// bytes, so building it never faults in the external blob.
struct AttachmentRef: Identifiable, Equatable {
    let id: UUID
    let objectID: NSManagedObjectID
    let filename: String
    let typeIdentifier: String?
    let byteCount: Int
}

enum AttachmentImportError: LocalizedError {
    case tooLarge(filename: String)
    case unreadable(filename: String)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let filename):
            return String(localized: "\(filename) is larger than 25 MB and can't be attached.")
        case .unreadable(let filename):
            return String(localized: "\(filename) couldn't be read.")
        }
    }
}

enum AttachmentStore {
    /// Single-file ceiling. Count is unlimited, but one oversized blob would stall CloudKit sync.
    static let maxByteCount = 25 * 1024 * 1024

    // MARK: - Reading

    static func attachments(of owner: ItemOwner) -> [Attachment] {
        let object = owner.object
        guard object.entity.relationshipsByName.keys.contains("attachments") else { return [] }
        let stored = object.value(forKey: "attachments") as? Set<Attachment> ?? []
        return stored.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            let lhsDate = lhs.createdAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return (lhs.filename ?? "") < (rhs.filename ?? "")
        }
    }

    static func drafts(of owner: ItemOwner) -> [AttachmentDraft] {
        attachments(of: owner).map { attachment in
            AttachmentDraft(
                id: attachment.id ?? UUID(),
                filename: attachment.displayFilename,
                typeIdentifier: attachment.typeIdentifier,
                byteCount: attachment.storedByteCount,
                existingObjectID: attachment.objectID,
                data: nil
            )
        }
    }

    static func refs(of owner: ItemOwner) -> [AttachmentRef] {
        attachments(of: owner).map { attachment in
            AttachmentRef(
                id: attachment.id ?? UUID(),
                objectID: attachment.objectID,
                filename: attachment.displayFilename,
                typeIdentifier: attachment.typeIdentifier,
                byteCount: attachment.storedByteCount
            )
        }
    }

    // MARK: - Writing

    /// Commits a staged list: removes attachments dropped from the drafts, inserts the new ones,
    /// and renumbers `sortOrder` to match the on-screen order.
    static func apply(_ drafts: [AttachmentDraft], to owner: ItemOwner, context: NSManagedObjectContext) {
        guard owner.object.entity.relationshipsByName.keys.contains("attachments") else { return }

        let keptObjectIDs = Set(drafts.compactMap(\.existingObjectID))
        for attachment in attachments(of: owner) where !keptObjectIDs.contains(attachment.objectID) {
            context.delete(attachment)
        }

        for (index, draft) in drafts.enumerated() {
            if let objectID = draft.existingObjectID {
                if let attachment = try? context.existingObject(with: objectID) as? Attachment {
                    attachment.sortOrder = Int16(clamping: index)
                }
                continue
            }
            guard let data = draft.data else { continue }

            let attachment = Attachment(context: context)
            attachment.id = draft.id
            attachment.createdAt = Date()
            attachment.filename = draft.filename
            attachment.typeIdentifier = draft.typeIdentifier
            attachment.data = data
            attachment.byteCount = Int64(data.count)
            attachment.sortOrder = Int16(clamping: index)
            switch owner {
            case .event(let event): attachment.event = event
            case .reminder(let reminder): attachment.reminder = reminder
            case .habit:
                break
            }
        }
    }

    // MARK: - Bytes

    static func data(for ref: AttachmentRef, context: NSManagedObjectContext) -> Data? {
        guard let attachment = try? context.existingObject(with: ref.objectID) as? Attachment else {
            return nil
        }
        return attachment.data
    }

    /// QuickLook needs a real file on disk, so bytes get written to a per-attachment temp folder.
    static func previewURL(for ref: AttachmentRef, context: NSManagedObjectContext) -> URL? {
        guard let data = data(for: ref, context: context) else { return nil }
        return writeTemporaryFile(data: data, id: ref.id, filename: ref.filename)
    }

    static func previewURL(for draft: AttachmentDraft, context: NSManagedObjectContext) -> URL? {
        if let data = draft.data {
            return writeTemporaryFile(data: data, id: draft.id, filename: draft.filename)
        }
        guard let objectID = draft.existingObjectID,
              let attachment = try? context.existingObject(with: objectID) as? Attachment,
              let data = attachment.data else {
            return nil
        }
        return writeTemporaryFile(data: data, id: draft.id, filename: draft.filename)
    }

    private static func writeTemporaryFile(data: Data, id: UUID, filename: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent(sanitized(filename))

        if let existing = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           existing == data.count {
            return fileURL
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            #if DEBUG
            print("Attachment temp write failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private static func sanitized(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Attachment" : cleaned
    }

    // MARK: - Presentation helpers

    static func isImage(_ typeIdentifier: String?) -> Bool {
        guard let typeIdentifier, let type = UTType(typeIdentifier) else { return false }
        return type.conforms(to: .image)
    }

    static func symbolName(for typeIdentifier: String?) -> String {
        guard let typeIdentifier, let type = UTType(typeIdentifier) else { return "doc.fill" }
        if type.conforms(to: .image) { return "photo.fill" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film.fill" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext.fill" }
        if type.conforms(to: .zip) || type.conforms(to: .archive) { return "archivebox.fill" }
        if type.conforms(to: .spreadsheet) { return "tablecells.fill" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle.fill" }
        if type.conforms(to: .calendarEvent) { return "calendar" }
        if type.conforms(to: .vCard) { return "person.crop.circle.fill" }
        if type.conforms(to: .text) { return "doc.text.fill" }
        return "doc.fill"
    }

    static func sizeText(_ byteCount: Int) -> String {
        Int64(byteCount).formatted(.byteCount(style: .file))
    }

    /// Suggested filename for a picked photo, which arrives without one.
    static func generatedFilename(for typeIdentifier: String?, index: Int) -> String {
        let stamp = Date().formatted(.dateTime.year().month().day().hour().minute().second())
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ",", with: "")
        let ext = typeIdentifier.flatMap { UTType($0)?.preferredFilenameExtension } ?? "dat"
        return "IMG-\(stamp)-\(index).\(ext)"
    }

    // MARK: - Thumbnails

    static func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// In-memory thumbnail cache so scrolling a list of attachments does not re-decode images.
final class AttachmentThumbnailCache {
    static let shared = AttachmentThumbnailCache()

    private let cache = NSCache<NSUUID, UIImage>()

    private init() {
        cache.countLimit = 120
    }

    func image(for id: UUID) -> UIImage? {
        cache.object(forKey: id as NSUUID)
    }

    func store(_ image: UIImage, for id: UUID) {
        cache.setObject(image, forKey: id as NSUUID)
    }
}

extension Attachment {
    var displayFilename: String {
        let trimmed = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return String(localized: "Attachment")
    }

    /// Recorded at import time so listing attachments never faults in the external blob.
    var storedByteCount: Int {
        Int(byteCount)
    }
}
