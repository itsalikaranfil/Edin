//
//  FolderItemsView.swift
//  One
//

import SwiftUI
import CoreData

struct FolderItemsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @ObservedObject var folder: Folder
    var bottomContentInset: CGFloat = 0
    var onBack: () -> Void
    var onClose: () -> Void
    var onSelectEvent: (Event) -> Void
    var onSelectReminder: (Reminder) -> Void
    var onSelectHabit: (Habit) -> Void = { _ in }

    @State private var sheetFilter: CalendarSheetFilter = .all
    @State private var showFlaggedOnly = false
    @State private var items: [(id: String, event: Event?, reminder: Reminder?, habit: Habit?)] = []

    var body: some View {
        VStack(spacing: 0) {
            header

            CalendarSheetFilterBar(
                sheetFilter: $sheetFilter,
                showFlaggedOnly: $showFlaggedOnly,
                folders: []
            )

            List {
                if filteredItems.isEmpty {
                    EmptyListSkeletonView(accessibilityLabel: emptyMessage, surface: .clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if let event = item.event {
                                CalendarSheetItemRow(item: event, showsItemDate: true) {
                                    onSelectEvent(event)
                                }
                            } else if let reminder = item.reminder {
                                CalendarSheetItemRow(item: reminder, showsItemDate: true) {
                                    onSelectReminder(reminder)
                                }
                            } else if let habit = item.habit {
                                CalendarSheetItemRow(item: habit, showsItemDate: true) {
                                    onSelectHabit(habit)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(index < filteredItems.count - 1 ? .visible : .hidden, edges: .bottom)
                        .listRowSeparatorTint(Color.gray.opacity(0.25))
                        .listRowBackground(Color.calendarSheetSurface)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, bottomContentInset)
            .animation(nil, value: filteredItems.map(\.id))
        }
        .compositingGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            reloadItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
            reloadItems()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                Haptics.light()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.primaryText)
                    .frame(width: 32, height: 32)
                    .glassCircleClose()
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to folders")

            Text(FolderStore.displayName(for: folder))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            SheetClosePill(action: onClose)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var emptyMessage: String {
        let folderName = FolderStore.displayName(for: folder)
        let subject = sheetFilter.emptyListSubject(flaggedOnly: showFlaggedOnly)
        return String(localized: "No \(subject) in \(folderName)")
    }

    private var filteredItems: [(id: String, event: Event?, reminder: Reminder?, habit: Habit?)] {
        items.filter { item in
            if let event = item.event {
                if !sheetFilter.showsEvents { return false }
                if showFlaggedOnly && !event.isFlagged { return false }
                return true
            }
            if let reminder = item.reminder {
                if !sheetFilter.showsReminders { return false }
                if showFlaggedOnly && !reminder.isFlagged { return false }
                return true
            }
            if item.habit != nil {
                if !sheetFilter.showsHabits { return false }
                if showFlaggedOnly { return false }
                return true
            }
            return false
        }
    }

    private func reloadItems() {
        let eventRequest = NSFetchRequest<Event>(entityName: "Event")
        eventRequest.predicate = NSPredicate(format: "folder == %@", folder)
        eventRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Event.date, ascending: true)]

        let reminderRequest = NSFetchRequest<Reminder>(entityName: "Reminder")
        reminderRequest.predicate = NSPredicate(format: "folder == %@", folder)
        reminderRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Reminder.date, ascending: true)]

        let folderEvents = (try? viewContext.fetch(eventRequest)) ?? []
        let folderReminders = (try? viewContext.fetch(reminderRequest)) ?? []

        var folderHabits: [Habit] = []
        if NSEntityDescription.entity(forEntityName: "Habit", in: viewContext) != nil {
            let habitRequest = NSFetchRequest<Habit>(entityName: "Habit")
            habitRequest.predicate = NSPredicate(format: "folder == %@", folder)
            habitRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Habit.date, ascending: true)]
            folderHabits = (try? viewContext.fetch(habitRequest)) ?? []
        }

        var allItems: [(date: Date, event: Event?, reminder: Reminder?, habit: Habit?)] = []

        for event in folderEvents {
            let date = event.startTime ?? event.date ?? Date.distantFuture
            allItems.append((date: date, event: event, reminder: nil, habit: nil))
        }

        for reminder in folderReminders {
            let date = reminder.time ?? reminder.date ?? Date.distantFuture
            allItems.append((date: date, event: nil, reminder: reminder, habit: nil))
        }

        for habit in folderHabits {
            let date = habit.time ?? habit.date ?? Date.distantFuture
            allItems.append((date: date, event: nil, reminder: nil, habit: habit))
        }

        allItems.sort { $0.date < $1.date }

        items = allItems.compactMap { item in
            if let event = item.event {
                return (id: event.objectID.uriRepresentation().absoluteString, event: event, reminder: nil, habit: nil)
            }
            if let reminder = item.reminder {
                return (id: reminder.objectID.uriRepresentation().absoluteString, event: nil, reminder: reminder, habit: nil)
            }
            if let habit = item.habit {
                return (id: habit.objectID.uriRepresentation().absoluteString, event: nil, reminder: nil, habit: habit)
            }
            return nil
        }
    }
}
