//
//  NewItemView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import CoreData

enum ItemType: String, CaseIterable {
    case event = "Event"
    case reminder = "Reminder"

    var localizedTitle: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

enum PlusMenuChoice: String {
    case event
    case habit
    case reminder
    case alarm
}

struct NewItemView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var folders: [Folder] = []
    
    let initialDate: Date
    let initialItemType: ItemType
    
    @State private var itemType: ItemType
    @State private var title: String = ""
    @State private var date: Date
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
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var attachmentDrafts: [AttachmentDraft] = []
    @State private var checklistDrafts: [ChecklistDraft] = []
    
    init(initialDate: Date = Date(), initialFolderID: UUID? = nil, initialItemType: ItemType = .event) {
        self.initialDate = initialDate
        self.initialItemType = initialItemType
        _itemType = State(initialValue: initialItemType)
        _date = State(initialValue: initialDate)
        _selectedFolderID = State(initialValue: initialFolderID)
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
                if itemType == .event {
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
                if itemType == .reminder {
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
            }
            .tint(.secondary)
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .navigationTitle(String(localized: "New \(itemType.localizedTitle)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton {
                        saveItem()
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
    
    private func saveItem() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a title"
            showError = true
            return
        }
        
        if itemType == .event {
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let event = Event(context: viewContext)
            event.id = UUID()
            event.createdAt = Date()
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
            
            // Save so event is persisted and shows in Reminders tab
            PersistenceController.shared.save()
            
            // Schedule notification
            Task {
                await NotificationManager.shared.requestAuthorization()
                await MainActor.run {
                    NotificationManager.shared.scheduleNotification(for: event)
                }
            }
        } else {
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let reminder = Reminder(context: viewContext)
            reminder.id = UUID()
            reminder.createdAt = Date()
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
            reminder.isCompleted = false
            if reminder.entity.attributesByName.keys.contains("isFlagged") {
                reminder.isFlagged = isFlagged
            }
            if reminder.entity.relationshipsByName.keys.contains("folder") {
                reminder.folder = folders.first { $0.id == selectedFolderID }
            }
            ChecklistStore.apply(checklistDrafts, to: .reminder(reminder), context: viewContext)
            AttachmentStore.apply(attachmentDrafts, to: .reminder(reminder), context: viewContext)
            
            // Save first to ensure reminder is persisted
            PersistenceController.shared.save()
            
            let reminderObjectID = reminder.objectID
            // Schedule notification after save
            Task {
                await NotificationManager.shared.requestAuthorization()
                await MainActor.run {
                    guard let scheduled = try? viewContext.existingObject(with: reminderObjectID) as? Reminder else {
                        return
                    }
                    NotificationManager.shared.scheduleNotification(for: scheduled)
                }
            }
        }
        
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        dismiss()
    }
}

#Preview {
    NewItemView(initialDate: Date())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

