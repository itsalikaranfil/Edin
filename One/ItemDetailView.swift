 //
//  ItemDetailView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import CoreData

/// Shared delete logic for use from ItemDetailView and row context menus.
enum RepeatDeleteScope {
    case thisOccurrence
    case allOccurrences
}

enum ItemActions {
    static func delete(_ event: Event, context: NSManagedObjectContext, postDataDidChange: Bool = true) {
        let eventId = event.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: eventId, itemType: "event")
        context.delete(event)
        PersistenceController.shared.save()
        if postDataDidChange {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }
    
    static func delete(_ reminder: Reminder, context: NSManagedObjectContext, postDataDidChange: Bool = true) {
        let reminderId = reminder.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
        context.delete(reminder)
        PersistenceController.shared.save()
        if postDataDidChange {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }

    static func delete(_ habit: Habit, context: NSManagedObjectContext, postDataDidChange: Bool = true) {
        let habitId = habit.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: habitId, itemType: "habit")
        context.delete(habit)
        PersistenceController.shared.save()
        if postDataDidChange {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }
    
    /// Deletes one occurrence or the whole series for a repeating reminder.
    static func deleteReminder(
        _ reminder: Reminder,
        scope: RepeatDeleteScope,
        occurrenceDay: Date,
        context: NSManagedObjectContext,
        postDataDidChange: Bool = true
    ) {
        let option = Recurrence.option(from: reminder.repeatOption)
        if option == .never || scope == .allOccurrences {
            delete(reminder, context: context, postDataDidChange: postDataDidChange)
            return
        }
        
        Recurrence.exclude(day: occurrenceDay, on: reminder)
        let reminderId = reminder.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
        if !reminder.isCompleted {
            NotificationManager.shared.scheduleNotification(for: reminder)
        }
        PersistenceController.shared.save()
        if postDataDidChange {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }

    /// Deletes one occurrence or the whole series for a repeating habit.
    static func deleteHabit(
        _ habit: Habit,
        scope: RepeatDeleteScope,
        occurrenceDay: Date,
        context: NSManagedObjectContext,
        postDataDidChange: Bool = true
    ) {
        let option = Recurrence.option(from: habit.repeatOption)
        if option == .never || scope == .allOccurrences {
            delete(habit, context: context, postDataDidChange: postDataDidChange)
            return
        }

        Recurrence.exclude(day: occurrenceDay, on: habit)
        let habitId = habit.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: habitId, itemType: "habit")
        NotificationManager.shared.scheduleNotification(for: habit)
        PersistenceController.shared.save()
        if postDataDidChange {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }
    
    /// Deletes one occurrence or the whole series for a repeating event.
    static func deleteEvent(
        _ event: Event,
        scope: RepeatDeleteScope,
        occurrenceDay: Date,
        context: NSManagedObjectContext,
        postDataDidChange: Bool = true
    ) {
        let option = Recurrence.option(from: event.repeatOption)
        if option == .never || scope == .allOccurrences {
            delete(event, context: context, postDataDidChange: postDataDidChange)
            return
        }
        
        Recurrence.exclude(day: occurrenceDay, on: event)
        let eventId = event.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: eventId, itemType: "event")
        NotificationManager.shared.scheduleNotification(for: event)
        PersistenceController.shared.save()
        if postDataDidChange {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }
    
    static func isRepeating(repeatOption raw: String?) -> Bool {
        Recurrence.option(from: raw) != .never
    }
}

/// Confirmation dialog for repeating-item delete (this occurrence vs all).
struct RepeatDeleteConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDeleteThis: () -> Void
    let onDeleteAll: () -> Void
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete Repeating Item?",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete This Occurrence", role: .destructive, action: onDeleteThis)
                Button("Delete All Occurrences", role: .destructive, action: onDeleteAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This item repeats. Delete only this day, or every occurrence?")
            }
    }
}

extension View {
    func repeatDeleteConfirmation(
        isPresented: Binding<Bool>,
        onDeleteThis: @escaping () -> Void,
        onDeleteAll: @escaping () -> Void
    ) -> some View {
        modifier(RepeatDeleteConfirmationModifier(
            isPresented: isPresented,
            onDeleteThis: onDeleteThis,
            onDeleteAll: onDeleteAll
        ))
    }
}

enum ItemDetailType {
    case event(Event)
    case reminder(Reminder)
}

struct ItemDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var folders: [Folder] = []
    
    let item: ItemDetailType
    
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var hasTime: Bool = false
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(3600)
    @State private var isAllDay: Bool = true
    @State private var repeatOption: RepeatOption = .never
    @State private var alertOption: AlertOption = .none
    @State private var secondAlertOption: AlertOption = .none
    @State private var notes: String = ""
    @State private var isFlagged: Bool = false
    @State private var selectedFolderID: UUID?
    @State private var isCompleted: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showRepeatDeleteConfirmation = false
    @State private var attachmentDrafts: [AttachmentDraft] = []
    @State private var checklistDrafts: [ChecklistDraft] = []
    
    private var isOverdue: Bool {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        switch item {
        case .event(let event):
            guard !event.isAllDay else { return false }
            guard let eventDate = event.date else { return false }
            return calendar.startOfDay(for: eventDate) < todayStart
        case .reminder(let reminder):
            guard !reminder.isCompleted else { return false }
            guard let reminderDate = reminder.date else { return false }
            return calendar.startOfDay(for: reminderDate) < todayStart
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Title
                Section {
                    TextField("Title", text: $title)
                        .foregroundColor(Color.primaryText)
                }
                
                // Date
                Section {
                    DatePicker(selection: $date, displayedComponents: .date) {
                        Label {
                            Text("Date")
                        } icon: {
                            Image(systemName: "calendar")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(Color.primaryText)
                    .tint(.blue)
                }
                
                // Time (for Events)
                if case .event = item {
                    Section {
                        Toggle("All Day", isOn: $isAllDay)
                            .foregroundColor(Color.primaryText)
                            .tint(.green)
                            .sensoryFeedback(.selection, trigger: isAllDay)
                        
                        if !isAllDay {
                            DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                                .foregroundColor(Color.primaryText)
                                .tint(.blue)
                            
                            DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                                .foregroundColor(Color.primaryText)
                                .tint(.blue)
                        }
                    }
                }
                
                // Time (for Reminders)
                if case .reminder = item {
                    Section {
                        Toggle(isOn: Binding(
                            get: { hasTime },
                            set: { newValue in
                                hasTime = newValue
                                if newValue {
                                    startTime = Self.nextMinute(from: Date())
                                }
                            }
                        )) {
                            Label {
                                Text("Has Time")
                            } icon: {
                                Image(systemName: "clock")
                                    .font(.system(size: 16))
                            }
                        }
                        .foregroundColor(Color.primaryText)
                        .tint(.green)
                        .sensoryFeedback(.selection, trigger: hasTime)
                        
                        if hasTime {
                            DatePicker("Time", selection: $startTime, displayedComponents: .hourAndMinute)
                                .foregroundColor(Color.primaryText)
                                .tint(.blue)
                        }
                    }
                    
                    // Completion Toggle
                    Section {
                        Toggle("Completed", isOn: $isCompleted)
                            .foregroundColor(Color.primaryText)
                            .tint(.green)
                            .sensoryFeedback(.selection, trigger: isCompleted)
                    }
                }

                Section {
                    Toggle(isOn: $isFlagged) {
                        Label {
                            Text("Flagged")
                        } icon: {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(Color.primaryText)
                    .tint(.green)
                    .sensoryFeedback(.selection, trigger: isFlagged)

                    Picker(selection: $selectedFolderID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(folders, id: \.objectID) { folder in
                            if let folderID = folder.id {
                                Text(FolderStore.displayName(for: folder)).tag(Optional(folderID))
                            }
                        }
                    } label: {
                        Label {
                            Text("Folder")
                        } icon: {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(Color.primaryText)
                }
                
                // Repeat
                Section {
                    Picker(selection: $repeatOption) {
                        ForEach(RepeatOption.allCases, id: \.self) { option in
                            Text(option.localizedTitle).tag(option)
                        }
                    } label: {
                        Label {
                            Text("Repeat")
                        } icon: {
                            Image(systemName: "repeat")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(Color.primaryText)
                }
                
                // Alert
                Section {
                    Picker(selection: $alertOption) {
                        ForEach(AlertOption.allCases, id: \.self) { option in
                            Text(option.localizedTitle).tag(option)
                        }
                    } label: {
                        Label {
                            Text("Alert")
                        } icon: {
                            Image(systemName: "alarm")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(Color.primaryText)
                    
                    if alertOption != .none {
                        Picker(selection: $secondAlertOption) {
                            ForEach(AlertOption.allCases, id: \.self) { option in
                                Text(option.localizedTitle).tag(option)
                            }
                        } label: {
                            Label {
                                Text("Second Alert")
                            } icon: {
                                Image(systemName: "alarm")
                                    .font(.system(size: 16))
                            }
                        }
                        .foregroundColor(Color.primaryText)
                    }
                }
                
                // Notes
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .foregroundColor(Color.primaryText)
                        .lineLimit(3...6)
                }

                ChecklistEditorSection(drafts: $checklistDrafts)

                AttachmentsEditorSection(drafts: $attachmentDrafts) { message in
                    errorMessage = message
                    showError = true
                }
                
                // Delete Button
                Section {
                    Button(role: .destructive) {
                        requestDelete()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete")
                            Spacer()
                        }
                        .foregroundStyle(.red)
                    }
                    .tint(.red)
                }
            }
            .tint(.secondary)
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .repeatDeleteConfirmation(
                isPresented: $showRepeatDeleteConfirmation,
                onDeleteThis: {
                    deleteItem(scope: .thisOccurrence)
                },
                onDeleteAll: {
                    deleteItem(scope: .allOccurrences)
                }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton {
                        saveChanges()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                reloadFolders()
                loadItemData()
            }
        }
    }

    private func reloadFolders() {
        guard NSEntityDescription.entity(forEntityName: "Folder", in: viewContext) != nil else {
            folders = []
            return
        }
        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
        folders = (try? viewContext.fetch(request)) ?? []
    }
    
    /// Next full minute from `date` (seconds zeroed) so calendar notification triggers stay valid.
    private static func nextMinute(from date: Date) -> Date {
        let calendar = Calendar.current
        let truncated = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        ) ?? date
        return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? date.addingTimeInterval(60)
    }
    
    private func loadItemData() {
        switch item {
        case .event(let event):
            title = event.title ?? ""
            date = event.date ?? Date()
            isAllDay = event.isAllDay
            startTime = event.startTime ?? Date()
            endTime = event.endTime ?? Date().addingTimeInterval(3600)
            repeatOption = RepeatOption(rawValue: event.repeatOption ?? "Never") ?? .never
            alertOption = AlertOption(rawValue: event.alert ?? "None") ?? .none
            // Load second alert if attribute exists
            if event.entity.attributesByName.keys.contains("secondAlert") {
                let secondAlertValue = event.value(forKey: "secondAlert") as? String ?? "None"
                secondAlertOption = AlertOption(rawValue: secondAlertValue) ?? .none
            }
            notes = event.notes ?? ""
            if event.entity.attributesByName.keys.contains("isFlagged") {
                isFlagged = event.isFlagged
            }
            if event.entity.relationshipsByName.keys.contains("folder") {
                selectedFolderID = event.folder?.id
            }
            attachmentDrafts = AttachmentStore.drafts(of: .event(event))
            checklistDrafts = ChecklistStore.drafts(of: .event(event))
            
        case .reminder(let reminder):
            title = reminder.title ?? ""
            date = reminder.date ?? Date()
            hasTime = reminder.time != nil
            startTime = reminder.time ?? Date()
            repeatOption = RepeatOption(rawValue: reminder.repeatOption ?? "Never") ?? .never
            alertOption = AlertOption(rawValue: reminder.alert ?? "None") ?? .none
            // Load second alert if attribute exists
            if reminder.entity.attributesByName.keys.contains("secondAlert") {
                let secondAlertValue = reminder.value(forKey: "secondAlert") as? String ?? "None"
                secondAlertOption = AlertOption(rawValue: secondAlertValue) ?? .none
            }
            notes = reminder.notes ?? ""
            if reminder.entity.attributesByName.keys.contains("isFlagged") {
                isFlagged = reminder.isFlagged
            }
            if reminder.entity.relationshipsByName.keys.contains("folder") {
                selectedFolderID = reminder.folder?.id
            }
            isCompleted = reminder.isCompleted
            attachmentDrafts = AttachmentStore.drafts(of: .reminder(reminder))
            checklistDrafts = ChecklistStore.drafts(of: .reminder(reminder))
        }
    }
    
    private func saveChanges() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a title"
            showError = true
            return
        }
        
        switch item {
        case .event(let event):
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            event.title = title
            event.date = dayStart
            event.isAllDay = isAllDay
            event.startTime = isAllDay ? nil : calendar.combining(day: dayStart, andTimeFrom: startTime)
            event.endTime = isAllDay ? nil : calendar.combining(day: dayStart, andTimeFrom: endTime)
            event.repeatOption = repeatOption.rawValue
            event.alert = alertOption.rawValue
            // Save second alert if attribute exists
            if event.entity.attributesByName.keys.contains("secondAlert") {
                event.setValue(secondAlertOption.rawValue, forKey: "secondAlert")
            }
            event.notes = notes.isEmpty ? nil : notes
            if event.entity.attributesByName.keys.contains("isFlagged") {
                event.isFlagged = isFlagged
            }
            if event.entity.relationshipsByName.keys.contains("folder") {
                event.folder = folders.first { $0.id == selectedFolderID }
            }
            ChecklistStore.apply(checklistDrafts, to: .event(event), context: viewContext)
            AttachmentStore.apply(attachmentDrafts, to: .event(event), context: viewContext)
            
            // Reschedule notification (cancels both primary and second)
            let eventId = event.id?.uuidString ?? ""
            NotificationManager.shared.cancelAllNotifications(for: eventId, itemType: "event")
            Task {
                await NotificationManager.shared.requestAuthorization()
                await MainActor.run {
                    NotificationManager.shared.scheduleNotification(for: event)
                }
            }
            
        case .reminder(let reminder):
            let wasCompletedBefore = reminder.isCompleted
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            
            reminder.title = title
            reminder.date = dayStart
            reminder.time = hasTime ? calendar.combining(day: dayStart, andTimeFrom: startTime) : nil
            reminder.repeatOption = repeatOption.rawValue
            reminder.alert = alertOption.rawValue
            // Save second alert if attribute exists
            if reminder.entity.attributesByName.keys.contains("secondAlert") {
                reminder.setValue(secondAlertOption.rawValue, forKey: "secondAlert")
            }
            reminder.notes = notes.isEmpty ? nil : notes
            if reminder.entity.attributesByName.keys.contains("isFlagged") {
                reminder.isFlagged = isFlagged
            }
            if reminder.entity.relationshipsByName.keys.contains("folder") {
                reminder.folder = folders.first { $0.id == selectedFolderID }
            }
            ChecklistStore.apply(checklistDrafts, to: .reminder(reminder), context: viewContext)
            AttachmentStore.apply(attachmentDrafts, to: .reminder(reminder), context: viewContext)
            
            // Completing a repeating reminder rolls the date forward instead of staying done.
            if isCompleted && !wasCompletedBefore, Recurrence.option(from: reminder.repeatOption) != .never {
                _ = reminder.completeOrRollForward()
            } else {
                reminder.isCompleted = isCompleted
                if isCompleted && !wasCompletedBefore {
                    let completionDate = Date()
                    reminder.setValue(completionDate, forKey: "completionDate")
                    #if DEBUG
                    print("✅ Set completionDate to: \(completionDate)")
                    #endif
                } else if !isCompleted && wasCompletedBefore {
                    reminder.setValue(nil, forKey: "completionDate")
                    #if DEBUG
                    print("🗑️ Cleared completionDate")
                    #endif
                }
            }
            
            // Reschedule notification if not completed (cancels both primary and second)
            let reminderId = reminder.id?.uuidString ?? ""
            NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
            if !reminder.isCompleted {
                Task {
                    await NotificationManager.shared.requestAuthorization()
                    await MainActor.run {
                        NotificationManager.shared.scheduleNotification(for: reminder)
                    }
                }
            }
        }
        
        PersistenceController.shared.save()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }
    
    private func requestDelete() {
        let repeating: Bool
        switch item {
        case .event(let event):
            repeating = ItemActions.isRepeating(repeatOption: event.repeatOption)
        case .reminder(let reminder):
            repeating = ItemActions.isRepeating(repeatOption: reminder.repeatOption)
        }
        if repeating {
            showRepeatDeleteConfirmation = true
        } else {
            deleteItem(scope: .allOccurrences)
        }
    }
    
    private func deleteItem(scope: RepeatDeleteScope) {
        switch item {
        case .event(let event):
            ItemActions.deleteEvent(
                event,
                scope: scope,
                occurrenceDay: Calendar.current.startOfDay(for: date),
                context: viewContext
            )
        case .reminder(let reminder):
            ItemActions.deleteReminder(
                reminder,
                scope: scope,
                occurrenceDay: Calendar.current.startOfDay(for: date),
                context: viewContext
            )
        }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }
}

#Preview {
    ItemDetailView(item: .event(Event(context: PersistenceController.preview.container.viewContext)))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

