//
//  NewHabitView.swift
//  One
//

import SwiftUI
import CoreData

struct NewHabitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let initialFolderID: UUID?

    @State private var folders: [Folder] = []
    @State private var title: String = ""
    @State private var hasTime: Bool = false
    @State private var time: Date = Date()
    @State private var repeatOption: RepeatOption = .daily
    @State private var alertOption: AlertOption = .none
    @State private var selectedFolderID: UUID?
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var checklistDrafts: [ChecklistDraft] = []

    init(initialDate: Date = Date(), initialFolderID: UUID? = nil) {
        self.initialDate = initialDate
        self.initialFolderID = initialFolderID
        _selectedFolderID = State(initialValue: initialFolderID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .foregroundColor(Color.primaryText)
                }

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

                    Toggle(isOn: Binding(
                        get: { hasTime },
                        set: { newValue in
                            hasTime = newValue
                            if newValue {
                                time = Self.nextMinute(from: Date())
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
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .foregroundColor(Color.primaryText)
                            .tint(.blue)
                    }

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

                ChecklistEditorSection(drafts: $checklistDrafts)
            }
            .tint(.secondary)
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton {
                        saveHabit()
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

    private static func nextMinute(from date: Date) -> Date {
        let calendar = Calendar.current
        let truncated = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        ) ?? date
        return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? date.addingTimeInterval(60)
    }

    private func saveHabit() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a title"
            showError = true
            return
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: initialDate)
        let habit = Habit(context: viewContext)
        habit.id = UUID()
        habit.createdAt = Date()
        habit.title = title
        habit.date = dayStart
        habit.time = hasTime ? calendar.combining(day: dayStart, andTimeFrom: time) : nil
        habit.repeatOption = repeatOption.rawValue
        habit.alert = alertOption.rawValue
        habit.isCompleted = false
        if habit.entity.relationshipsByName.keys.contains("folder") {
            habit.folder = folders.first { $0.id == selectedFolderID }
        }
        ChecklistStore.apply(checklistDrafts, to: .habit(habit), context: viewContext)

        PersistenceController.shared.save()

        let habitObjectID = habit.objectID
        Task {
            await NotificationManager.shared.requestAuthorization()
            await MainActor.run {
                guard let scheduled = try? viewContext.existingObject(with: habitObjectID) as? Habit else {
                    return
                }
                NotificationManager.shared.scheduleNotification(for: scheduled)
            }
        }

        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        dismiss()
    }
}

#Preview {
    NewHabitView(initialDate: Date())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
