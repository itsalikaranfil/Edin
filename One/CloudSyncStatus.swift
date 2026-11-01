//
//  CloudSyncStatus.swift
//  One
//

import CloudKit
import Combine
import CoreData
import Foundation

/// Shared CloudKit container identifier — must match entitlements and Persistence.swift.
enum CloudKitConfig {
    static let containerIdentifier = "iCloud.com.ali.OneApp"
}

/// Surfaces iCloud account availability and last Core Data + CloudKit sync for Settings.
@MainActor
final class CloudSyncStatus: ObservableObject {
    static let shared = CloudSyncStatus()

    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isUsingCloudKit: Bool = true
    @Published private(set) var isExportInProgress: Bool = false

    private var eventObserver: NSObjectProtocol?

    private init() {
        startObservingSyncEvents()
    }

    deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    var statusDescription: String {
        switch accountStatus {
        case .available:
            return String(localized: "Available")
        case .noAccount:
            return String(localized: "No Account")
        case .restricted:
            return String(localized: "Restricted")
        case .temporarilyUnavailable:
            return String(localized: "Temporarily Unavailable")
        case .couldNotDetermine:
            return String(localized: "Checking…")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    var lastSyncDescription: String? {
        guard let lastSyncDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return String(localized: "Last synced \(formatter.localizedString(for: lastSyncDate, relativeTo: Date()))")
    }

    func recordError(_ message: String) {
        lastError = message
    }

    func refresh() async {
        isUsingCloudKit = PersistenceController.shared.isUsingCloudKit

        let container = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            accountStatus = .couldNotDetermine
            #if DEBUG
            print("⚠️ CloudKit account status check failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func startObservingSyncEvents() {
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }
            Task { @MainActor in
                self?.handleSyncEvent(event)
            }
        }
    }

    private func handleSyncEvent(_ event: NSPersistentCloudKitContainer.Event) {
        // In-progress events have no endDate.
        if event.endDate == nil {
            if event.type == .export {
                isExportInProgress = true
            }
            return
        }

        if event.type == .export {
            isExportInProgress = false
        }

        if event.succeeded {
            lastError = nil
            switch event.type {
            case .import, .export:
                lastSyncDate = event.endDate
            case .setup:
                break
            @unknown default:
                break
            }
            return
        }

        guard let error = event.error else { return }

        #if DEBUG
        Self.logCloudKitError(error, eventType: event.type)
        #endif

        // Export failures with unknownItem / batchRequestFailed usually mean the Production
        // schema is missing a record type (e.g. CD_Alarm). Surface those; keep other retries silent.
        if event.type == .export, Self.isLikelySchemaMismatch(error) {
            let typeLabel = Self.label(for: event.type)
            lastError = "\(typeLabel): \(Self.userFacingMessage(for: error))"
            return
        }

        // Transient / retryable failures: Core Data + CloudKit will retry; keep lastSyncDate.
        if Self.isRetryable(error) {
            return
        }

        let typeLabel = Self.label(for: event.type)
        lastError = "\(typeLabel): \(Self.userFacingMessage(for: error))"
    }

    private static func label(for type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:
            return String(localized: "Setup")
        case .import:
            return String(localized: "Import")
        case .export:
            return String(localized: "Export")
        @unknown default:
            return String(localized: "Sync")
        }
    }

    // MARK: - CloudKit error helpers

    /// CloudKit codes that NSPersistentCloudKitContainer typically retries automatically.
    private static let retryableCodes: Set<CKError.Code> = [
        .networkUnavailable,
        .networkFailure,
        .serviceUnavailable,
        .requestRateLimited,
        .zoneBusy,
        .serverRecordChanged,
        .changeTokenExpired,
        .batchRequestFailed,
        .unknownItem,
        .serverResponseLost,
    ]

    /// Codes that often mean Production is missing a Core Data record type / field.
    private static let schemaMismatchCodes: Set<CKError.Code> = [
        .unknownItem,
        .batchRequestFailed,
        .incompatibleVersion,
        .serverRejectedRequest,
    ]

    private static func isRetryable(_ error: Error) -> Bool {
        let leafErrors = leafCloudKitErrors(from: error)
        if leafErrors.isEmpty {
            // Outer partialFailure with no nested items still often retries; treat as transient.
            return cloudKitCode(from: error) == .partialFailure
        }
        return leafErrors.allSatisfy { retryableCodes.contains($0) }
    }

    private static func isLikelySchemaMismatch(_ error: Error) -> Bool {
        let leaves = leafCloudKitErrors(from: error)
        if !leaves.isEmpty {
            return leaves.contains { schemaMismatchCodes.contains($0) }
        }
        if let code = cloudKitCode(from: error) {
            return schemaMismatchCodes.contains(code)
        }
        return false
    }

    private static func userFacingMessage(for error: Error) -> String {
        let leaves = leafCloudKitErrors(from: error)
        if let first = leaves.first {
            return message(for: first) ?? (error as NSError).localizedDescription
        }
        if let code = cloudKitCode(from: error) {
            return message(for: code) ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    private static func message(for code: CKError.Code) -> String? {
        switch code {
        case .notAuthenticated:
            return String(localized: "Sign in to iCloud in Settings to sync.")
        case .quotaExceeded:
            return String(localized: "iCloud storage is full.")
        case .permissionFailure:
            return String(localized: "iCloud permission denied for this app.")
        case .incompatibleVersion, .serverRejectedRequest, .unknownItem, .batchRequestFailed:
            return String(localized: "iCloud schema may need updating. Try again later.")
        case .managedAccountRestricted:
            return String(localized: "This iCloud account is restricted.")
        case .accountTemporarilyUnavailable:
            return String(localized: "iCloud is temporarily unavailable.")
        default:
            return nil
        }
    }

    private static func cloudKitCode(from error: Error) -> CKError.Code? {
        if let ck = error as? CKError {
            return ck.code
        }
        let ns = error as NSError
        guard ns.domain == CKErrorDomain else { return nil }
        return CKError.Code(rawValue: ns.code)
    }

    /// Unwraps `CKPartialErrorsByItemIDKey` and `NSUnderlyingErrorKey` to leaf CloudKit codes.
    private static func leafCloudKitErrors(from error: Error) -> [CKError.Code] {
        var result: [CKError.Code] = []
        var queue: [Error] = [error]
        var depth = 0

        while let current = queue.popLast(), depth < 32 {
            depth += 1
            let ns = current as NSError

            if let partial = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], !partial.isEmpty {
                queue.append(contentsOf: partial.values)
                continue
            }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying)
                continue
            }

            if ns.domain == CKErrorDomain, let code = CKError.Code(rawValue: ns.code) {
                // Skip container-only partialFailure; prefer nested leaves when present.
                if code != .partialFailure {
                    result.append(code)
                }
            }
        }

        return result
    }

    #if DEBUG
    private static func logCloudKitError(_ error: Error, eventType: NSPersistentCloudKitContainer.EventType) {
        let typeLabel = label(for: eventType)
        let leaves = leafCloudKitErrors(from: error)
        let ns = error as NSError
        if leaves.isEmpty {
            print("⚠️ CloudKit \(typeLabel) failed: \(ns.domain) code \(ns.code) — \(error.localizedDescription)")
            return
        }
        let detail = leaves.map { "\($0.rawValue)/\($0)" }.joined(separator: "; ")
        print("⚠️ CloudKit \(typeLabel) failed (nested): \(detail) — outer: \(ns.domain) \(ns.code)")
    }
    #endif
}
