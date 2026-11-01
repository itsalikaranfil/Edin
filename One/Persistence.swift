//
//  Persistence.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import CoreData
import CloudKit
import Combine

/// Observable store load state so the UI can wait before showing main content
final class StoreLoadState: ObservableObject {
    @Published var isLoaded = false
    static let shared = StoreLoadState()
    private init() {}
}

/// Core Data persistence controller with CloudKit integration.
/// When CloudKit fails with model incompatibility (134060), falls back to local-only storage so the app can run.
final class PersistenceController {
    static let shared = PersistenceController()
    
    /// When CloudKit fails with 134060, we load a local-only container and set this so the app can run.
    private static var _fallbackContainer: NSPersistentContainer?
    
    private let initialContainer: NSPersistentContainer
    /// The container to use; uses fallback (local-only) if CloudKit failed with 134060.
    var container: NSPersistentContainer { Self._fallbackContainer ?? initialContainer }

    /// Debounces AlarmKit / notification reschedule after CloudKit import bursts.
    private var remoteChangeRescheduleWorkItem: DispatchWorkItem?

    /// True when the active store is CloudKit-backed (not the local-only fallback).
    var isUsingCloudKit: Bool { container is NSPersistentCloudKitContainer }
    
    /// Preview instance for SwiftUI previews (in-memory store)
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        
        // Add sample data for previews
        let sampleEvent = Event(context: context)
        sampleEvent.id = UUID()
        sampleEvent.createdAt = Date()
        sampleEvent.title = "Meeting"
        sampleEvent.date = Date()
        sampleEvent.startTime = Date()
        sampleEvent.endTime = Date().addingTimeInterval(1800)
        sampleEvent.isAllDay = false
        sampleEvent.isFlagged = true

        let inboxFolder = Folder(context: context)
        inboxFolder.id = UUID()
        inboxFolder.name = FolderStore.inboxFolderName
        inboxFolder.sortOrder = 0

        let workFolder = Folder(context: context)
        workFolder.id = UUID()
        workFolder.name = "Work"
        workFolder.sortOrder = 1
        sampleEvent.folder = workFolder
        
        let sampleReminder = Reminder(context: context)
        sampleReminder.id = UUID()
        sampleReminder.createdAt = Date()
        sampleReminder.title = "Shop"
        sampleReminder.date = Date()
        sampleReminder.time = Date().addingTimeInterval(3600)
        sampleReminder.notes = "Don't forget milk again"
        sampleReminder.isCompleted = false
        sampleReminder.folder = inboxFolder
        
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return controller
    }()
    
    // Set to true to enable CloudKit sync (requires CloudKit setup in Xcode)
    private static let useCloudKit = true
    
    init(inMemory: Bool = false) {
        let containerToUse: NSPersistentContainer
        // Use CloudKit container if enabled, otherwise use regular container
        if Self.useCloudKit {
            let cloudContainer = NSPersistentCloudKitContainer(name: "One")
            containerToUse = cloudContainer
            
            if inMemory {
                cloudContainer.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            } else {
                guard let description = cloudContainer.persistentStoreDescriptions.first else {
                    fatalError("Could not retrieve persistent store description")
                }
                // Explicit store URL so path is deterministic (helps avoid 134060 / schema mismatch)
                if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    description.url = appSupport.appendingPathComponent("One.sqlite")
                }
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
                description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: CloudKitConfig.containerIdentifier
                )
                #if DEBUG
                print("CloudKit sync enabled (container: \(CloudKitConfig.containerIdentifier))")
                #endif
            }
        } else {
            // Use regular container (local storage only)
            containerToUse = NSPersistentContainer(name: "One")
        
        if inMemory {
            containerToUse.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
                guard let description = containerToUse.persistentStoreDescriptions.first else {
                    fatalError("Could not retrieve persistent store description")
                }
                
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
                description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            
                #if DEBUG
                print("📱 Running in local-only mode (CloudKit disabled)")
                #endif
            }
        }
        
        self.initialContainer = containerToUse
        let storeContainer = containerToUse
        storeContainer.loadPersistentStores { description, error in
            if let error = error {
                let nsError = error as NSError
                
                // Log detailed error information
                #if DEBUG
                print("❌ Core Data store failed to load")
                print("Error: \(nsError.localizedDescription)")
                print("Domain: \(nsError.domain)")
                print("Code: \(nsError.code)")
                print("User Info: \(nsError.userInfo)")
                if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                    print("Failure reason: \(reason)")
                }
                #endif
                
                // Check if it's a model incompatibility error (134060)
                if nsError.domain == "NSCocoaErrorDomain" && nsError.code == 134060 {
                    #if DEBUG
                    print("⚠️ CloudKit/Core Data 134060 — See CLOUDKIT_SETUP.md: reset development schema in CloudKit Console, then delete app and reinstall.")
                    #endif
                    // Store was created with a different model (e.g. after enabling CloudKit). Remove all possible store paths and retry.
                    let fileManager = FileManager.default
                    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    var urlsToRemove: [URL] = []
                    if let url = description.url { urlsToRemove.append(url) }
                    if let base = appSupport {
                        urlsToRemove.append(base.appendingPathComponent("One.sqlite"))
                        urlsToRemove.append(base.appendingPathComponent("One").appendingPathComponent("One.sqlite"))
                    }
                    func removeStoreFiles(at storeURL: URL) {
                        if fileManager.fileExists(atPath: storeURL.path) {
                            try? fileManager.removeItem(at: storeURL)
                            #if DEBUG
                            print("✅ Removed \(storeURL.lastPathComponent)")
                            #endif
                        }
                        let walURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
                        if fileManager.fileExists(atPath: walURL.path) {
                            try? fileManager.removeItem(at: walURL)
                            #if DEBUG
                            print("✅ Removed \(walURL.lastPathComponent)")
                            #endif
                        }
                        let shmURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
                        if fileManager.fileExists(atPath: shmURL.path) {
                            try? fileManager.removeItem(at: shmURL)
                            #if DEBUG
                            print("✅ Removed \(shmURL.lastPathComponent)")
                            #endif
                        }
                    }
                    #if DEBUG
                    print("⚠️ Removing incompatible store(s)...")
                    #endif
                    for url in urlsToRemove { removeStoreFiles(at: url) }
                    if let base = appSupport {
                        let oneDir = base.appendingPathComponent("One")
                        if fileManager.fileExists(atPath: oneDir.path) {
                            try? fileManager.removeItem(at: oneDir)
                            #if DEBUG
                            print("✅ Removed One directory")
                            #endif
                        }
                    }
                    
                    // Retry with a fresh store description so the container isn’t in a bad state
                    let storeURL = appSupport?.appendingPathComponent("One.sqlite") ?? URL(fileURLWithPath: "/tmp/One.sqlite")
                    let freshDescription = NSPersistentStoreDescription(url: storeURL)
                    freshDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                    freshDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                    freshDescription.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
                    freshDescription.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
                    if Self.useCloudKit {
                        freshDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitConfig.containerIdentifier)
                    }
                    storeContainer.persistentStoreDescriptions = [freshDescription]
                    
                    #if DEBUG
                    print("✅ Retrying store load...")
                    #endif
                    storeContainer.loadPersistentStores { _, retryError in
                        if let retryError = retryError {
                            let retryNsError = retryError as NSError
                            #if DEBUG
                            print("❌ Retry failed (code=\(retryNsError.code)). Falling back to local-only store.")
                            print("Retry userInfo: \(retryNsError.userInfo)")
                            if let reason = retryNsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                                print("Retry failure reason: \(reason)")
                            }
                            #endif
                            Self.loadLocalOnlyFallback(
                                appSupport: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                                reason: "CloudKit store retry failed (code \(retryNsError.code))"
                            )
                            return
                        }
                        #if DEBUG
                        print("✅ Core Data store loaded successfully after recovery")
                        #endif
                        DispatchQueue.main.async {
                            StoreLoadState.shared.isLoaded = true
                        }
                    }
                    return
                } else if nsError.domain == "NSCocoaErrorDomain" {
                    // Other Core Data errors
                    switch nsError.code {
                    case 134130:
                        fatalError("""
                            Core Data Migration Error
                            
                            The data model has changed. Please:
                            1. Delete the app from your device/simulator
                            2. Clean build folder (Cmd+Shift+K)
                            3. Rebuild and run
                            """)
                    case 134140:
                        fatalError("""
                            Core Data Store Corruption
                            
                            The database file may be corrupted. Please:
                            1. Delete the app completely
                            2. Reinstall the app
                            """)
                    default:
                        fatalError("""
                            Core Data Error (Code: \(nsError.code))
                            
                            Error: \(nsError.localizedDescription)
                            
                            Troubleshooting:
                            1. Delete the app and reinstall
                            2. Clean build folder (Product → Clean Build Folder)
                            3. Check that 'One.xcdatamodeld' exists in the project
                            4. For CloudKit: Enable CloudKit in Xcode Capabilities
                            5. For CloudKit: Ensure container 'iCloud.com.ali.OneApp' is created
                            """)
                    }
                } else {
                    fatalError("""
                        Core Data store failed to load: \(nsError.localizedDescription)
                        
                        Full error details:
                        - Domain: \(nsError.domain)
                        - Code: \(nsError.code)
                        - User Info: \(nsError.userInfo)
                        
                        Quick fixes:
                        1. Delete app and reinstall
                        2. Clean build folder
                        3. Check CloudKit configuration in Xcode
                        """)
                }
            } else {
                #if DEBUG
                print("✅ Core Data store loaded successfully")
                #endif
                DispatchQueue.main.async {
                    StoreLoadState.shared.isLoaded = true
                }
                // Push Core Data model to CloudKit (development only). Deploy schema to Production in CloudKit Console before App Store release.
                #if DEBUG
                if let cloudContainer = storeContainer as? NSPersistentCloudKitContainer {
                    Task {
                        do {
                            try cloudContainer.initializeCloudKitSchema(options: [])
                            print("✅ CloudKit schema initialized")
                        } catch {
                            let message = error.localizedDescription
                            print("⚠️ CloudKit schema init: \(message) — check CLOUDKIT_SETUP.md and reset development schema if you see 134060.")
                            Task { @MainActor in
                                CloudSyncStatus.shared.recordError("Schema setup: \(message)")
                            }
                        }
                    }
                }
                #endif
            }
        }
        
        // Configure view context for automatic merging
        containerToUse.viewContext.automaticallyMergesChangesFromParent = true
        containerToUse.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Refresh UI and widgets whenever CloudKit pushes remote changes
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: containerToUse.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            let context = PersistenceController.shared.container.viewContext
            context.processPendingChanges()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            WidgetSnapshotExporter.shared.scheduleExport()
            self?.scheduleRescheduleAfterRemoteChange()
        }
    }

    /// After CloudKit import, re-register local notifications and AlarmKit (device-local schedules).
    private func scheduleRescheduleAfterRemoteChange() {
        remoteChangeRescheduleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            let context = PersistenceController.shared.container.viewContext
            NotificationManager.shared.rescheduleAllNotifications(context: context)
        }
        remoteChangeRescheduleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    
    /// Call from UI after a timeout if the loading screen never dismisses (e.g. CloudKit hangs).
    /// Uses the main store file (One.sqlite) in local-only mode so existing data is preserved.
    static func ensureLoadedWithFallbackIfNeeded() {
        if StoreLoadState.shared.isLoaded { return }
        if _fallbackContainer != nil {
            DispatchQueue.main.async { StoreLoadState.shared.isLoaded = true }
            return
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        loadLocalOnlyFallback(appSupport: appSupport, useMainStoreFile: true, reason: "CloudKit store load timed out")
    }
    
    /// When CloudKit fails with 134060, load a local-only store so the app can run (no sync).
    /// - Parameter useMainStoreFile: If true (e.g. timeout), use One.sqlite so existing data is preserved. If false (134060), use One_local.sqlite.
    private static func loadLocalOnlyFallback(appSupport: URL?, useMainStoreFile: Bool = false, reason: String) {
        guard let base = appSupport else {
            fatalError("Core Data model incompatibility (134060). Please delete the app and reinstall.")
        }
        if _fallbackContainer != nil {
            DispatchQueue.main.async { StoreLoadState.shared.isLoaded = true }
            return
        }
        let storeURL = useMainStoreFile
            ? base.appendingPathComponent("One.sqlite")
            : base.appendingPathComponent("One_local.sqlite")
        let fallbackContainer = NSPersistentContainer(name: "One")
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        fallbackContainer.persistentStoreDescriptions = [desc]
        fallbackContainer.loadPersistentStores { _, err in
            if let err = err {
                let ns = err as NSError
                #if DEBUG
                print("❌ Fallback store failed: \(ns.localizedDescription)")
                #endif
                fatalError("Core Data model incompatibility (134060). Please delete the app and reinstall.")
            }
            fallbackContainer.viewContext.automaticallyMergesChangesFromParent = true
            fallbackContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            Self._fallbackContainer = fallbackContainer
            #if DEBUG
            print("✅ Using local-only store (CloudKit unavailable) — \(useMainStoreFile ? "same file (One.sqlite), data preserved" : "fallback file (One_local.sqlite)")")
            #endif
            DispatchQueue.main.async {
                CloudSyncStatus.shared.recordError("Local fallback: \(reason)")
                StoreLoadState.shared.isLoaded = true
            }
        }
    }
    
    /// Save context if there are changes
    func save() {
        let context = container.viewContext
        var didSaveSuccessfully = false

        if context.hasChanges {
            do {
                try context.save()
                context.processPendingChanges()
                didSaveSuccessfully = true
            } catch {
                let nsError = error as NSError
                #if DEBUG
                print("Error saving context: \(nsError.localizedDescription)")
                #endif
                return
            }
        }

        // Export even when there were no pending changes, so pre-saved flows refresh widgets.
        if didSaveSuccessfully || !context.hasChanges {
            WidgetSnapshotExporter.shared.scheduleExport()
        }
    }
}

