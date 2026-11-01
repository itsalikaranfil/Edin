//
//  ItemLimitManager.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import Foundation
import CoreData

/// Manages item count limits for free vs paid users
class ItemLimitManager {
    static let shared = ItemLimitManager()
    
    private let freeLimit = 6
    
    /// Check if user can add more items
    func canAddItem(context: NSManagedObjectContext) -> Bool {
        if PurchaseManager.shared.hasUnlimitedAccess {
            return true
        }
        
        let eventCount = countEvents(context: context)
        let reminderCount = countReminders(context: context)
        let habitCount = countHabits(context: context)
        
        return (eventCount + reminderCount + habitCount) < freeLimit
    }
    
    /// Get current item count
    func getItemCount(context: NSManagedObjectContext) -> Int {
        let eventCount = countEvents(context: context)
        let reminderCount = countReminders(context: context)
        let habitCount = countHabits(context: context)
        return eventCount + reminderCount + habitCount
    }
    
    /// Get remaining free items
    func getRemainingFreeItems(context: NSManagedObjectContext) -> Int {
        let currentCount = getItemCount(context: context)
        return max(0, freeLimit - currentCount)
    }
    
    private func countEvents(context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.resultType = .countResultType
        do {
            return try context.count(for: request)
        } catch {
            #if DEBUG
            print("Error counting events: \(error)")
            #endif
            return 0
        }
    }
    
    private func countReminders(context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<Reminder>(entityName: "Reminder")
        request.resultType = .countResultType
        do {
            return try context.count(for: request)
        } catch {
            #if DEBUG
            print("Error counting reminders: \(error)")
            #endif
            return 0
        }
    }

    private func countHabits(context: NSManagedObjectContext) -> Int {
        guard NSEntityDescription.entity(forEntityName: "Habit", in: context) != nil else {
            return 0
        }
        let request = NSFetchRequest<Habit>(entityName: "Habit")
        request.resultType = .countResultType
        do {
            return try context.count(for: request)
        } catch {
            #if DEBUG
            print("Error counting habits: \(error)")
            #endif
            return 0
        }
    }
}

