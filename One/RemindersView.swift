//
//  RemindersView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import CoreData

struct RemindersView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    private static let activeRemindersRequest: NSFetchRequest<Reminder> = {
        let r = NSFetchRequest<Reminder>(entityName: "Reminder")
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \Reminder.date, ascending: true),
            NSSortDescriptor(keyPath: \Reminder.time, ascending: true)
        ]
        r.predicate = NSPredicate(format: "isCompleted == NO")
        return r
    }()
    private static let completedRemindersRequest: NSFetchRequest<Reminder> = {
        let r = NSFetchRequest<Reminder>(entityName: "Reminder")
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \Reminder.date, ascending: true),
            NSSortDescriptor(keyPath: \Reminder.time, ascending: true)
        ]
        r.predicate = NSPredicate(format: "isCompleted == YES")
        return r
    }()
    private static let allEventsRequest: NSFetchRequest<Event> = {
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \Event.date, ascending: true),
            NSSortDescriptor(keyPath: \Event.startTime, ascending: true)
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let past = calendar.date(byAdding: .year, value: -20, to: today)!
        let future = calendar.date(byAdding: .year, value: 50, to: today)!
        r.predicate = NSPredicate(format: "date >= %@ AND date < %@", past as NSDate, future as NSDate)
        return r
    }()
    private static let allHabitsRequest: NSFetchRequest<Habit> = {
        let r = NSFetchRequest<Habit>(entityName: "Habit")
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \Habit.date, ascending: true),
            NSSortDescriptor(keyPath: \Habit.time, ascending: true)
        ]
        return r
    }()
    
    @FetchRequest(fetchRequest: activeRemindersRequest)
    private var activeReminders: FetchedResults<Reminder>
    
    @FetchRequest(fetchRequest: completedRemindersRequest)
    private var completedReminders: FetchedResults<Reminder>
    
    @FetchRequest(fetchRequest: allEventsRequest)
    private var allEvents: FetchedResults<Event>

    @FetchRequest(fetchRequest: allHabitsRequest)
    private var allHabits: FetchedResults<Habit>
    
    @State private var showNewItem = false
    @State private var showSubscription = false
    @State private var completingReminderIds: Set<UUID> = []
    @State private var completingHabitOccurrenceIds: Set<String> = []
    @State private var selectedReminder: Reminder? = nil
    @State private var selectedEvent: Event? = nil
    @State private var selectedHabit: Habit? = nil
    @State private var selectedHabitOccurrenceDay: Date? = nil
    @State private var showCompletedSheet = false
    
    private var completedEvents: [Event] {
        let today = Calendar.current.startOfDay(for: Date())
        
        // Non-repeating events whose date/time is before today. Repeating events stay active.
        return allEvents.filter { event in
            let option = Recurrence.option(from: event.repeatOption)
            guard option == .never else { return false }
            guard let date = event.date else { return false }
            let eventDateTime = event.startTime ?? date
            return eventDateTime < today
        }
    }
    
    /// Combine a date (start of day) with time components from another date
    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        
        var combinedComponents = DateComponents()
        combinedComponents.year = dateComponents.year
        combinedComponents.month = dateComponents.month
        combinedComponents.day = dateComponents.day
        combinedComponents.hour = timeComponents.hour
        combinedComponents.minute = timeComponents.minute
        combinedComponents.second = timeComponents.second ?? 0
        
        return calendar.date(from: combinedComponents) ?? date
    }
    
    private typealias UpcomingItem = (id: String, occurrenceDay: Date, isEvent: Bool, event: Event?, reminder: Reminder?, habit: Habit?)
    
    /// Today through today+2 — horizon used for repeating events/reminders in Upcoming.
    private var upcomingRepeatHorizonEnd: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 2, to: today)!
    }
    
    private func occurrenceListID(baseID: String, day: Date) -> String {
        "\(baseID)-\(Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970))"
    }
    
    private var expandedUpcomingItems: [UpcomingItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let horizonEnd = upcomingRepeatHorizonEnd
        var items: [UpcomingItem] = []
        
        for reminder in activeReminders {
            guard let baseDate = reminder.date else { continue }
            let option = Recurrence.option(from: reminder.repeatOption)
            let baseID = reminder.id?.uuidString ?? reminder.objectID.uriRepresentation().absoluteString
            
            if option == .never {
                let day = calendar.startOfDay(for: baseDate)
                items.append((id: baseID, occurrenceDay: day, isEvent: false, event: nil, reminder: reminder, habit: nil))
            } else {
                for day in Recurrence.occurrenceDates(
                    from: today,
                    through: horizonEnd,
                    baseDate: baseDate,
                    option: option,
                    excludedDates: reminder.excludedDatesStorage,
                    calendar: calendar
                ) {
                    items.append((
                        id: occurrenceListID(baseID: baseID, day: day),
                        occurrenceDay: day,
                        isEvent: false,
                        event: nil,
                        reminder: reminder,
                        habit: nil
                    ))
                }
            }
        }
        
        for event in allEvents {
            guard let baseDate = event.date else { continue }
            let option = Recurrence.option(from: event.repeatOption)
            // Skip non-repeating past events (they belong in Completed)
            if option == .never {
                let eventDateTime = event.startTime ?? baseDate
                if eventDateTime < today { continue }
            }
            let baseID = event.id?.uuidString ?? event.objectID.uriRepresentation().absoluteString
            
            if option == .never {
                let day = calendar.startOfDay(for: baseDate)
                items.append((id: baseID, occurrenceDay: day, isEvent: true, event: event, reminder: nil, habit: nil))
            } else {
                for day in Recurrence.occurrenceDates(
                    from: today,
                    through: horizonEnd,
                    baseDate: baseDate,
                    option: option,
                    excludedDates: event.excludedDatesStorage,
                    calendar: calendar
                ) {
                    items.append((
                        id: occurrenceListID(baseID: baseID, day: day),
                        occurrenceDay: day,
                        isEvent: true,
                        event: event,
                        reminder: nil,
                        habit: nil
                    ))
                }
            }
        }

        items.append(contentsOf: expandedHabitItems(today: today, calendar: calendar))
        
        return items
    }

    /// Per habit: today (if it occurs) and the next occurrence only (e.g. weekly → today + next week).
    private func expandedHabitItems(today: Date, calendar: Calendar) -> [UpcomingItem] {
        var items: [UpcomingItem] = []

        for habit in allHabits {
            guard let baseDate = habit.date else { continue }
            let option = Recurrence.option(from: habit.repeatOption)
            let baseID = habit.id?.uuidString ?? habit.objectID.uriRepresentation().absoluteString

            if option == .never {
                if habit.isCompleted { continue }
                let day = calendar.startOfDay(for: baseDate)
                if habit.isCompleted(on: day) { continue }
                items.append((
                    id: baseID,
                    occurrenceDay: day,
                    isEvent: false,
                    event: nil,
                    reminder: nil,
                    habit: habit
                ))
            } else {
                if Recurrence.occurs(
                    on: today,
                    baseDate: baseDate,
                    option: option,
                    excludedDates: habit.excludedDatesStorage,
                    calendar: calendar
                ), !habit.isCompleted(on: today) {
                    items.append((
                        id: occurrenceListID(baseID: baseID, day: today),
                        occurrenceDay: today,
                        isEvent: false,
                        event: nil,
                        reminder: nil,
                        habit: habit
                    ))
                }
                if let next = Recurrence.nextDate(
                    after: today,
                    baseDate: baseDate,
                    option: option,
                    excludedDates: habit.excludedDatesStorage,
                    calendar: calendar
                ), !habit.isCompleted(on: next) {
                    items.append((
                        id: occurrenceListID(baseID: baseID, day: next),
                        occurrenceDay: next,
                        isEvent: false,
                        event: nil,
                        reminder: nil,
                        habit: habit
                    ))
                }
            }
        }

        return items
    }
    
    private func sortTime(for item: UpcomingItem) -> Date {
        if item.isEvent, let event = item.event {
            if let start = event.startTime {
                return Calendar.current.combining(day: item.occurrenceDay, andTimeFrom: start)
            }
            return item.occurrenceDay
        }
        if let reminder = item.reminder, let time = reminder.time {
            return Calendar.current.combining(day: item.occurrenceDay, andTimeFrom: time)
        }
        if let habit = item.habit, let time = habit.time {
            return Calendar.current.combining(day: item.occurrenceDay, andTimeFrom: time)
        }
        return item.occurrenceDay
    }
    
    private var todayItems: [UpcomingItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return expandedUpcomingItems
            .filter { $0.occurrenceDay <= today }
            .sorted { sortTime(for: $0) < sortTime(for: $1) }
    }
    
    private var scheduledItems: [UpcomingItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return expandedUpcomingItems
            .filter { $0.occurrenceDay > today }
            .sorted { sortTime(for: $0) < sortTime(for: $1) }
    }
    
    private var hasVisibleUpcomingItems: Bool {
        !visibleTodayItems.isEmpty || !visibleScheduledItemsByDate.isEmpty
    }

    /// Identity for List remount when section layout changes (avoids UICollectionView crash).
    private var upcomingListStructureID: String {
        let hasToday = visibleTodayItems.isEmpty ? "0" : "1"
        let empty = hasVisibleUpcomingItems ? "1" : "0"
        let scheduledKeys = visibleScheduledItemsByDate
            .map { String(Int($0.date.timeIntervalSince1970)) }
            .joined(separator: ",")
        return "\(empty)-\(hasToday)-\(scheduledKeys)"
    }

    private var visibleTodayItems: [UpcomingItem] {
        todayItems.filter { item in
            if let reminderID = item.reminder?.id, completingReminderIds.contains(reminderID) {
                return false
            }
            if item.habit != nil, completingHabitOccurrenceIds.contains(item.id) {
                return false
            }
            return true
        }
    }

    private var visibleScheduledItemsByDate: [(date: Date, items: [UpcomingItem])] {
        scheduledItemsByDate.compactMap { dateGroup in
            let visible = dateGroup.items.filter { item in
                if let reminderID = item.reminder?.id, completingReminderIds.contains(reminderID) {
                    return false
                }
                if item.habit != nil, completingHabitOccurrenceIds.contains(item.id) {
                    return false
                }
                return true
            }
            return visible.isEmpty ? nil : (date: dateGroup.date, items: visible)
        }
    }

    private var scheduledItemsByDate: [(date: Date, items: [UpcomingItem])] {
        var grouped: [Date: [UpcomingItem]] = [:]
        
        for item in scheduledItems {
            let startOfDay = item.occurrenceDay
            grouped[startOfDay, default: []].append(item)
        }
        
        for (date, _) in grouped {
            grouped[date] = grouped[date]?.sorted { sortTime(for: $0) < sortTime(for: $1) }
        }
        
        return grouped.map { (date: $0.key, items: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    /// Completed section items with stable unique id per managed object so delete only removes the correct row.
    private var completedItems: [(id: String, isEvent: Bool, event: Event?, reminder: Reminder?)] {
        var items: [(id: String, isEvent: Bool, event: Event?, reminder: Reminder?)] = []
        
        for event in completedEvents {
            items.append((id: event.objectID.uriRepresentation().absoluteString, isEvent: true, event: event, reminder: nil))
        }
        
        for reminder in completedReminders {
            items.append((id: reminder.objectID.uriRepresentation().absoluteString, isEvent: false, event: nil, reminder: reminder))
        }
        
        return items.sorted { item1, item2 in
            let date1 = item1.isEvent ? (item1.event?.startTime ?? item1.event?.date ?? Date.distantPast) : (item1.reminder?.completionDate ?? Date.distantPast)
            let date2 = item2.isEvent ? (item2.event?.startTime ?? item2.event?.date ?? Date.distantPast) : (item2.reminder?.completionDate ?? Date.distantPast)
            return date1 > date2
        }
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    private var remindersHeader: some View {
        HStack {
            Text("Upcoming")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.primaryText)
            Spacer()
            Button {
                Haptics.light()
                showCompletedSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.204, green: 0.780, blue: 0.349))
                    Text("Completed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(Color.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassCapsulePill()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func upcomingSectionBackground(isFirst: Bool, isLast: Bool) -> some View {
        if isFirst && isLast {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.appBackground)
        } else if isFirst {
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            )
            .fill(Color.appBackground)
        } else if isLast {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 0
            )
            .fill(Color.appBackground)
        } else {
            Color.appBackground
        }
    }

    @ViewBuilder
    private func upcomingItemRow(
        _ item: UpcomingItem,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        Group {
            if item.isEvent, let event = item.event {
                EventRow(
                    event: event,
                    onTap: { selectedEvent = event },
                    groupedStyle: true,
                    occurrenceDay: item.occurrenceDay
                )
            } else if let reminder = item.reminder {
                ReminderRow(
                    reminder: reminder,
                    onTap: { selectedReminder = reminder },
                    onDidComplete: { id in
                        // Let the checkmark paint, then use the system List removal animation.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.default) {
                                _ = completingReminderIds.insert(id)
                            }
                        }
                    },
                    groupedStyle: true,
                    occurrenceDay: item.occurrenceDay
                )
                .id(item.id)
            } else if let habit = item.habit {
                HabitRow(
                    habit: habit,
                    onTap: {
                        selectedHabitOccurrenceDay = item.occurrenceDay
                        selectedHabit = habit
                    },
                    onDidComplete: { occurrenceID in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.default) {
                                _ = completingHabitOccurrenceIds.insert(occurrenceID)
                            }
                        }
                    },
                    groupedStyle: true,
                    occurrenceDay: item.occurrenceDay,
                    occurrenceListID: item.id
                )
                .id(item.id)
            }
        }
        .transition(.opacity)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
        .listRowSeparatorTint(Color.gray.opacity(0.25))
        .listRowBackground(upcomingSectionBackground(isFirst: isFirst, isLast: isLast))
    }

    @ViewBuilder
    private var upcomingEmptyContent: some View {
        EmptyListSkeletonView(
            accessibilityLabel: String(localized: "No events/reminders"),
            surface: Color.appBackground,
            icons: ["calendar", "circle", "calendar", "circle"]
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    var body: some View {
        List {
            Section {
                remindersHeader
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.screenBackground)
            }

            if !hasVisibleUpcomingItems {
                Section {
                    upcomingEmptyContent
                } header: {
                    Text("Today")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.primaryText)
                        .textCase(nil)
                }

                Section {
                    EmptyListSkeletonView(
                        surface: Color.appBackground,
                        icons: ["calendar", "circle"]
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Tomorrow")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.primaryText)
                        .textCase(nil)
                }
            } else {
                if !visibleTodayItems.isEmpty {
                    Section {
                        ForEach(Array(visibleTodayItems.enumerated()), id: \.element.id) { index, item in
                            upcomingItemRow(
                                item,
                                isFirst: index == 0,
                                isLast: index == visibleTodayItems.count - 1
                            )
                        }
                    } header: {
                        Text("Today")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.primaryText)
                            .textCase(nil)
                    }
                }

                if !visibleScheduledItemsByDate.isEmpty {
                    Section {
                        Text("Scheduled")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.primaryText)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.screenBackground)
                    }

                    ForEach(visibleScheduledItemsByDate, id: \.date) { dateGroup in
                        Section {
                            ForEach(Array(dateGroup.items.enumerated()), id: \.element.id) { index, item in
                                upcomingItemRow(
                                    item,
                                    isFirst: index == 0,
                                    isLast: index == dateGroup.items.count - 1
                                )
                            }
                        } header: {
                            Text(formatDateHeader(dateGroup.date))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Color.primaryText)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        // Remount list when section structure changes to avoid UICollectionView invalid updates.
        .id(upcomingListStructureID)
        .listStyle(.plain)
        .listSectionSpacing(12)
        .listSectionMargins(.horizontal, 16)
        .scrollContentBackground(.hidden)
        .background(Color.screenBackground)
        // Allow default item removal animation; keep section-date changes non-animated
        // to avoid UICollectionView "invalid number of items" crashes.
        .animation(nil, value: visibleScheduledItemsByDate.map(\.date))
        .sheet(isPresented: $showCompletedSheet) {
            CompletedListPage(onClose: { showCompletedSheet = false })
                .environment(\.managedObjectContext, viewContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.sheetSurface)
        }
        .sheet(isPresented: $showNewItem) { NewItemView() }
        .sheet(isPresented: $showSubscription) { SubscriptionView() }
        .sheet(item: $selectedReminder) { reminder in ItemInfoView(item: .reminder(reminder)) }
        .sheet(item: $selectedEvent) { event in ItemInfoView(item: .event(event)) }
        .sheet(item: $selectedHabit) { habit in
            ItemInfoView(item: .habit(habit, occurrenceDay: selectedHabitOccurrenceDay))
                .environment(\.managedObjectContext, viewContext)
        }
        .onChange(of: todayItems.map(\.id)) { _, _ in
            pruneCompletingReminderIds()
            pruneCompletingHabitOccurrenceIds()
        }
        .onChange(of: scheduledItems.map(\.id)) { _, _ in
            pruneCompletingReminderIds()
            pruneCompletingHabitOccurrenceIds()
        }
        .onChange(of: showCompletedSheet) { _, isOpen in
            if !isOpen {
                completingReminderIds.removeAll()
                completingHabitOccurrenceIds.removeAll()
            }
        }
        .onAppear { updateEventPredicate() }
    }
    
    /// Drops completing IDs once the reminder is no longer active (fully completed).
    private func pruneCompletingReminderIds() {
        let activeIds = Set(activeReminders.compactMap(\.id))
        completingReminderIds = completingReminderIds.intersection(activeIds)
    }

    private func pruneCompletingHabitOccurrenceIds() {
        let activeIds = Set(expandedUpcomingItems.compactMap { item in
            item.habit != nil ? item.id : nil
        })
        completingHabitOccurrenceIds = completingHabitOccurrenceIds.intersection(activeIds)
    }
    
    /// Applies date range so events load for Reminders. Uses a wide range so events visible in Calendar also appear here.
    private func updateEventPredicate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let pastDate = calendar.date(byAdding: .year, value: -20, to: today)!
        let futureDate = calendar.date(byAdding: .year, value: 50, to: today)!
        let eventPredicate = NSPredicate(format: "date >= %@ AND date < %@", pastDate as NSDate, futureDate as NSDate)
        allEvents.nsPredicate = eventPredicate
    }
    
    private func checkLimitAndShowSheet() {
        if ItemLimitManager.shared.canAddItem(context: viewContext) {
            showNewItem = true
        } else {
            showSubscription = true
        }
    }
}

// MARK: - Completed List Page

struct CompletedListPage: View {
    @Environment(\.managedObjectContext) private var viewContext
    var onClose: () -> Void
    
    private static let completedRemindersRequest: NSFetchRequest<Reminder> = {
        let r = NSFetchRequest<Reminder>(entityName: "Reminder")
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \Reminder.date, ascending: true),
            NSSortDescriptor(keyPath: \Reminder.time, ascending: true)
        ]
        r.predicate = NSPredicate(format: "isCompleted == YES")
        return r
    }()
    private static let allEventsRequest: NSFetchRequest<Event> = {
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \Event.date, ascending: true),
            NSSortDescriptor(keyPath: \Event.startTime, ascending: true)
        ]
        return r
    }()
    private static let allHabitsRequest: NSFetchRequest<Habit> = {
        let r = NSFetchRequest<Habit>(entityName: "Habit")
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \Habit.completionDate, ascending: false)
        ]
        return r
    }()
    
    @FetchRequest(fetchRequest: completedRemindersRequest)
    private var completedReminders: FetchedResults<Reminder>
    
    @FetchRequest(fetchRequest: allEventsRequest)
    private var allEvents: FetchedResults<Event>

    @FetchRequest(fetchRequest: allHabitsRequest)
    private var allHabits: FetchedResults<Habit>
    
    @State private var selectedReminder: Reminder? = nil
    @State private var selectedEvent: Event? = nil
    
    private var completedEvents: [Event] {
        let today = Calendar.current.startOfDay(for: Date())
        return allEvents.filter { event in
            guard let date = event.date else { return false }
            let eventDateTime = event.startTime ?? date
            return eventDateTime < today
        }
    }

    private typealias CompletedItem = (
        id: String,
        isEvent: Bool,
        event: Event?,
        reminder: Reminder?,
        habit: Habit?,
        habitOccurrenceDay: Date?
    )
    
    private var completedItems: [CompletedItem] {
        var items: [CompletedItem] = []
        for event in completedEvents {
            items.append((
                id: event.objectID.uriRepresentation().absoluteString,
                isEvent: true,
                event: event,
                reminder: nil,
                habit: nil,
                habitOccurrenceDay: nil
            ))
        }
        for reminder in completedReminders {
            items.append((
                id: reminder.objectID.uriRepresentation().absoluteString,
                isEvent: false,
                event: nil,
                reminder: reminder,
                habit: nil,
                habitOccurrenceDay: nil
            ))
        }
        for habit in allHabits {
            let days = habit.completedOccurrenceDays()
            if days.isEmpty, habit.isCompleted, let date = habit.date {
                items.append((
                    id: habit.objectID.uriRepresentation().absoluteString,
                    isEvent: false,
                    event: nil,
                    reminder: nil,
                    habit: habit,
                    habitOccurrenceDay: Calendar.current.startOfDay(for: date)
                ))
            } else {
                for day in days {
                    let baseID = habit.id?.uuidString ?? habit.objectID.uriRepresentation().absoluteString
                    items.append((
                        id: "\(baseID)-\(Recurrence.dayKey(for: day))",
                        isEvent: false,
                        event: nil,
                        reminder: nil,
                        habit: habit,
                        habitOccurrenceDay: day
                    ))
                }
            }
        }
        return items.sorted { item1, item2 in
            let date1 = completedSortDate(for: item1)
            let date2 = completedSortDate(for: item2)
            return date1 > date2
        }
    }

    private func completedSortDate(for item: CompletedItem) -> Date {
        if item.isEvent {
            return item.event?.startTime ?? item.event?.date ?? Date.distantPast
        }
        if let reminder = item.reminder {
            return reminder.completionDate ?? Date.distantPast
        }
        if let habit = item.habit {
            return habit.completionDate ?? item.habitOccurrenceDay ?? Date.distantPast
        }
        return Date.distantPast
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header

            if completedItems.isEmpty {
                Text("No completed items")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(completedItems.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if item.isEvent, let event = item.event {
                                EventRow(event: event, onTap: { selectedEvent = event }, showDate: true, groupedStyle: true)
                            } else if let reminder = item.reminder {
                                ReminderRow(reminder: reminder, onTap: { selectedReminder = reminder }, showCompletionDate: true, groupedStyle: true)
                            } else if let habit = item.habit, let day = item.habitOccurrenceDay {
                                HabitRow(
                                    habit: habit,
                                    showCompletionDate: true,
                                    groupedStyle: true,
                                    occurrenceDay: day
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(index < completedItems.count - 1 ? .visible : .hidden, edges: .bottom)
                        .listRowSeparatorTint(Color.gray.opacity(0.25))
                        .listRowBackground(Color.appBackground)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity.combined(with: .scale(scale: 0.92))
                        ))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.easeInOut(duration: 0.3), value: completedItems.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.sheetSurface)
        .onAppear { updateEventPredicate() }
        .sheet(item: $selectedReminder) { reminder in
            ItemInfoView(item: .reminder(reminder))
        }
        .sheet(item: $selectedEvent) { event in
            ItemInfoView(item: .event(event))
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Completed")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.primaryText)

            Spacer()

            SheetClosePill(action: onClose)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    private func updateEventPredicate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let pastDate = calendar.date(byAdding: .day, value: -30, to: today)!
        let futureDate = calendar.date(byAdding: .year, value: 2, to: today)!
        let eventPredicate = NSPredicate(format: "date >= %@ AND date < %@", pastDate as NSDate, futureDate as NSDate)
        allEvents.nsPredicate = eventPredicate
    }
}

struct HabitRow: View {
    @ObservedObject var habit: Habit
    var onTap: (() -> Void)? = nil
    var showCompletionDate: Bool = false
    var onDidComplete: ((String) -> Void)? = nil
    var groupedStyle: Bool = false
    var occurrenceDay: Date = Calendar.current.startOfDay(for: Date())
    var occurrenceListID: String? = nil

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showRepeatDeleteConfirmation = false
    @State private var isCompleting = false
    @State private var completionToken = UUID()

    private var dayCompleted: Bool {
        habit.isCompleted(on: occurrenceDay) || isCompleting
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                Image(systemName: dayCompleted ? "checkmark.circle.dotted" : "circle.dotted")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color.flagRed)
                    .scaleEffect(dayCompleted ? 1.1 : 1.0)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            handleCompletionToggle()
                        }
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(habit.title ?? "Untitled Habit")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(dayCompleted ? .gray : Color.primaryText)
                            .lineLimit(1)
                    }

                    if showCompletionDate {
                        if let completionDate = habit.completionDate {
                            Text("Completed at \(habitRowFormatCompletionDateTime(completionDate))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            Text("Completed")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        FolderNotesMetaRow(folderName: habit.folder?.name, notes: nil)
                    }
                }

                Spacer()

                if !showCompletionDate {
                    HabitFlamePill(streak: habit.currentStreak())
                }
            }
            .padding(.horizontal, groupedStyle ? 0 : 16)
            .padding(.vertical, groupedStyle ? 12 : 16)
            .background(groupedStyle ? Color.clear : Color.appBackground)
            .cornerRadius(groupedStyle ? 0 : 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: !ItemActions.isRepeating(repeatOption: habit.repeatOption)) {
            if ItemActions.isRepeating(repeatOption: habit.repeatOption) {
                Button {
                    showRepeatDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color(uiColor: .systemRed))
            } else {
                Button(role: .destructive) {
                    ItemActions.delete(habit, context: viewContext)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color(uiColor: .systemRed))
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                if ItemActions.isRepeating(repeatOption: habit.repeatOption) {
                    showRepeatDeleteConfirmation = true
                } else {
                    ItemActions.delete(habit, context: viewContext)
                }
            }
        }
        .repeatDeleteConfirmation(
            isPresented: $showRepeatDeleteConfirmation,
            onDeleteThis: {
                DispatchQueue.main.async {
                    ItemActions.deleteHabit(
                        habit,
                        scope: .thisOccurrence,
                        occurrenceDay: occurrenceDay,
                        context: viewContext
                    )
                }
            },
            onDeleteAll: {
                DispatchQueue.main.async {
                    ItemActions.deleteHabit(
                        habit,
                        scope: .allOccurrences,
                        occurrenceDay: occurrenceDay,
                        context: viewContext
                    )
                }
            }
        )
        .onAppear {
            if !habit.isCompleted(on: occurrenceDay) {
                isCompleting = false
            }
        }
    }

    private func handleCompletionToggle() {
        guard !isCompleting else { return }
        Haptics.selection()

        let wasCompleted = habit.isCompleted(on: occurrenceDay)

        // Completing with parent-driven list hide (Upcoming), then persist → Completed.
        if !wasCompleted, let occurrenceListID, onDidComplete != nil {
            let token = UUID()
            completionToken = token
            withAnimation(.easeInOut(duration: 0.15)) {
                isCompleting = true
            }
            onDidComplete?(occurrenceListID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard completionToken == token else { return }
                habit.setCompleted(true, on: occurrenceDay)
                persistCompletionChange()
            }
            return
        }

        habit.setCompleted(!wasCompleted, on: occurrenceDay)
        if wasCompleted {
            isCompleting = false
            completionToken = UUID()
        }
        persistCompletionChange()
    }

    private func persistCompletionChange() {
        do {
            try viewContext.save()
            PersistenceController.shared.save()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        } catch {
            #if DEBUG
            print("❌ Error saving habit completion: \(error.localizedDescription)")
            #endif
        }
    }
}

private func habitRowFormatCompletionDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

struct ReminderRow: View {
    @ObservedObject var reminder: Reminder
    let onTap: () -> Void
    var showCompletionDate: Bool = false
    var onDidComplete: ((UUID) -> Void)? = nil
    /// When true, row has no card chrome; parent provides grouped list background (matches Calendar).
    var groupedStyle: Bool = false
    /// Day this row represents (for repeating items in Upcoming).
    var occurrenceDay: Date = Calendar.current.startOfDay(for: Date())
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showChangeDateSheet = false
    @State private var tempNewDate = Date()
    @State private var isCompleting = false
    @State private var completionToken = UUID()
    @State private var showRepeatDeleteConfirmation = false
    
    private var showsCompletedAppearance: Bool {
        reminder.isCompleted || isCompleting
    }
    
    private var isOverdue: Bool {
        guard !showsCompletedAppearance else { return false }
        guard let reminderDate = reminder.date else { return false }
        return Calendar.current.isDayBeforeToday(reminderDate)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Completion Toggle
                Image(systemName: showsCompletedAppearance ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color.reminderOrange)
                    .scaleEffect(showsCompletedAppearance ? 1.1 : 1.0)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            handleCompletionToggle()
                        }
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(reminder.title ?? "Untitled Reminder")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(
                                showsCompletedAppearance ? .gray : Color.primaryText
                            )
                            .lineLimit(1)

                        if reminder.isFlagged {
                            FlagIndicator()
                        }

                        if itemHasRepeat(reminder.repeatOption) {
                            RepeatIndicator()
                        }
                    }

                    if showCompletionDate && reminder.isCompleted {
                        // Show "Completed at" only when we have real completion date; otherwise just "Completed"
                        if let completionDate = reminder.completionDate {
                            Text("Completed at \(formatCompletionDateTime(completionDate))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            Text("Completed")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else if !showCompletionDate {
                        // Show passed date text for overdue reminders
                        if isOverdue && !showsCompletedAppearance, let date = reminder.date {
                            Text(formatPassedDate(date))
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            FolderNotesMetaRow(folderName: reminder.folder?.name, notes: reminder.notes)
                        }
                    }
                }
                
                Spacer()
                
                let badgeTime: Date? = showsCompletedAppearance ? nil : reminder.time
                if let time = badgeTime {
                    Text(formatTime(time))
                        .font(.caption)
                        .foregroundColor(Color.primaryText.opacity(0.9))
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, groupedStyle ? 0 : 16)
            .padding(.vertical, groupedStyle ? 12 : 16)
            .background(groupedStyle ? Color.clear : Color.appBackground)
            .cornerRadius(groupedStyle ? 0 : 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: !ItemActions.isRepeating(repeatOption: reminder.repeatOption)) {
            if ItemActions.isRepeating(repeatOption: reminder.repeatOption) {
                Button {
                    performSwipeDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color(uiColor: .systemRed))
            } else {
                Button(role: .destructive) {
                    performSwipeDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                performSwipeDelete()
            }
        }
        .repeatDeleteConfirmation(
            isPresented: $showRepeatDeleteConfirmation,
            onDeleteThis: {
                DispatchQueue.main.async {
                    ItemActions.deleteReminder(
                        reminder,
                        scope: .thisOccurrence,
                        occurrenceDay: occurrenceDay,
                        context: viewContext
                    )
                }
            },
            onDeleteAll: {
                DispatchQueue.main.async {
                    ItemActions.deleteReminder(
                        reminder,
                        scope: .allOccurrences,
                        occurrenceDay: occurrenceDay,
                        context: viewContext
                    )
                }
            }
        )
        .sheet(isPresented: $showChangeDateSheet) {
            QuickChangeDateView(selectedDate: $tempNewDate, onDone: {
                applyNewDateToReminder()
                showChangeDateSheet = false
            }, onCancel: {
                showChangeDateSheet = false
            })
        }
        .onAppear {
            if !reminder.isCompleted {
                isCompleting = false
            }
        }
        .onChange(of: reminder.isCompleted) { _, isCompleted in
            if !isCompleted {
                isCompleting = false
                completionToken = UUID()
            }
        }
    }
    
    private func handleCompletionToggle() {
        guard !isCompleting else { return }
        
        Haptics.selection()
        let wasCompleted = reminder.isCompleted
        
        // Repeating: roll date forward instead of permanently completing.
        if !wasCompleted, Recurrence.option(from: reminder.repeatOption) != .never {
            _ = reminder.completeOrRollForward()
            persistCompletionChange()
            return
        }
        
        // Completing with parent-driven list animation: show checkmark now, save after removal animates.
        if !wasCompleted, let id = reminder.id, onDidComplete != nil {
            let token = UUID()
            completionToken = token
            withAnimation(.easeInOut(duration: 0.15)) {
                isCompleting = true
            }
            onDidComplete?(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard completionToken == token else { return }
                reminder.isCompleted = true
                reminder.completionDate = Date()
                persistCompletionChange()
            }
            return
        }
        
        reminder.isCompleted.toggle()
        if reminder.isCompleted && !wasCompleted {
            reminder.completionDate = Date()
        } else if !reminder.isCompleted && wasCompleted {
            reminder.completionDate = nil
            isCompleting = false
            completionToken = UUID()
        }
        persistCompletionChange()
    }
    
    private func persistCompletionChange() {
        let reminderId = reminder.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
        if !reminder.isCompleted {
            NotificationManager.shared.scheduleNotification(for: reminder)
        }
        do {
            try viewContext.save()
            PersistenceController.shared.save()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        } catch {
            #if DEBUG
            print("❌ Error saving context: \(error.localizedDescription)")
            #endif
        }
    }
    
    private func performSwipeDelete() {
        if ItemActions.isRepeating(repeatOption: reminder.repeatOption) {
            showRepeatDeleteConfirmation = true
            return
        }
        ItemActions.delete(reminder, context: viewContext)
    }
    
    private func applyNewDateToReminder() {
        let calendar = Calendar.current
        let newDate = calendar.startOfDay(for: tempNewDate)
        reminder.date = newDate
        if let time = reminder.time {
            reminder.time = calendar.combining(day: newDate, andTimeFrom: time)
        }
        let reminderId = reminder.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
        NotificationManager.shared.scheduleNotification(for: reminder)
        do { try viewContext.save() } catch { }
        PersistenceController.shared.save()
    }
    
    private func formatTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time).lowercased()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return String(localized: "Today")
        } else if Calendar.current.isDateInTomorrow(date) {
            return String(localized: "Tomorrow")
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    private func formatDateTime(date: Date, time: Date) -> String {
        let dateStr = formatDate(date)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(dateStr) at \(formatter.string(from: time))"
    }
    
    private func formatCompletionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
    
    private func formatCompletionDateTime(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return "\(dateFormatter.string(from: date)) at \(timeFormatter.string(from: date))"
    }
    
    private func formatCompletionDateTime(_ date: Date, time: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return "\(dateFormatter.string(from: date)) at \(timeFormatter.string(from: time))"
    }
    
    private func formatPassedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

struct EventRow: View {
    @ObservedObject var event: Event
    let onTap: () -> Void
    var showDate: Bool = false
    /// When true, row has no card chrome; parent provides grouped list background (matches Calendar).
    var groupedStyle: Bool = false
    var occurrenceDay: Date = Calendar.current.startOfDay(for: Date())
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showChangeDateSheet = false
    @State private var tempNewDate = Date()
    @State private var showRepeatDeleteConfirmation = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Blue calendar icon for events
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color.eventBlue)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.title ?? "Untitled Event")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(showDate ? .gray : Color.primaryText)
                            .lineLimit(1)

                        if event.isFlagged {
                            FlagIndicator()
                        }

                        if itemHasRepeat(event.repeatOption) {
                            RepeatIndicator()
                        }
                    }

                    if showDate {
                        // Show event date
                        if let date = event.startTime ?? event.date {
                            Text(formatEventDate(date))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        FolderNotesMetaRow(folderName: event.folder?.name, notes: event.notes)
                    }
                }
                
                Spacer()
                
                if !event.isAllDay, let startTime = event.startTime {
                    Text(timeRangeText(start: startTime, end: event.endTime))
                        .font(.caption)
                        .foregroundColor(showDate ? .gray : Color.primaryText.opacity(0.9))
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, groupedStyle ? 0 : 16)
            .padding(.vertical, groupedStyle ? 12 : 16)
            .background(groupedStyle ? Color.clear : Color.appBackground)
            .cornerRadius(groupedStyle ? 0 : 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: !ItemActions.isRepeating(repeatOption: event.repeatOption)) {
            if ItemActions.isRepeating(repeatOption: event.repeatOption) {
                Button {
                    performSwipeDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color(uiColor: .systemRed))
            } else {
                Button(role: .destructive) {
                    performSwipeDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                performSwipeDelete()
            }
        }
        .repeatDeleteConfirmation(
            isPresented: $showRepeatDeleteConfirmation,
            onDeleteThis: {
                DispatchQueue.main.async {
                    ItemActions.deleteEvent(
                        event,
                        scope: .thisOccurrence,
                        occurrenceDay: occurrenceDay,
                        context: viewContext
                    )
                }
            },
            onDeleteAll: {
                DispatchQueue.main.async {
                    ItemActions.deleteEvent(
                        event,
                        scope: .allOccurrences,
                        occurrenceDay: occurrenceDay,
                        context: viewContext
                    )
                }
            }
        )
        .sheet(isPresented: $showChangeDateSheet) {
            QuickChangeDateView(selectedDate: $tempNewDate, onDone: {
                applyNewDateToEvent()
                showChangeDateSheet = false
            }, onCancel: {
                showChangeDateSheet = false
            })
        }
    }
    
    private func performSwipeDelete() {
        if ItemActions.isRepeating(repeatOption: event.repeatOption) {
            showRepeatDeleteConfirmation = true
            return
        }
        ItemActions.delete(event, context: viewContext)
    }
    
    private func applyNewDateToEvent() {
        let calendar = Calendar.current
        let newDate = calendar.startOfDay(for: tempNewDate)
        event.date = newDate
        if !event.isAllDay {
            if let startTime = event.startTime {
                event.startTime = calendar.combining(day: newDate, andTimeFrom: startTime)
            }
            if let endTime = event.endTime {
                event.endTime = calendar.combining(day: newDate, andTimeFrom: endTime)
            }
        }
        let eventId = event.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: eventId, itemType: "event")
        NotificationManager.shared.scheduleNotification(for: event)
        do { try viewContext.save() } catch { }
        PersistenceController.shared.save()
    }
    
    private func formatTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time).lowercased()
    }

    private func timeRangeText(start: Date, end: Date?) -> String {
        let startStr = formatTime(start)
        if let end {
            return "\(startStr) - \(formatTime(end))"
        }
        return startStr
    }
    
    private func formatEventDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    RemindersView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

