//
//  HabitDetailView.swift
//  One
//

import SwiftUI
import CoreData

struct HabitDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var habit: Habit
    var occurrenceDay: Date?

    @State private var folders: [Folder] = []
    @State private var title: String = ""
    @State private var hasTime: Bool = false
    @State private var time: Date = Date()
    @State private var repeatOption: RepeatOption = .daily
    @State private var alertOption: AlertOption = .none
    @State private var selectedFolderID: UUID?
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showRepeatDeleteConfirmation = false
    @State private var checklistDrafts: [ChecklistDraft] = []

    private var effectiveOccurrenceDay: Date {
        occurrenceDay ?? habit.date ?? Date()
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

                Section {
                    Button(role: .destructive) {
                        requestDelete()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete")
                            Spacer()
                        }
                    }
                    .tint(Color(uiColor: .systemRed))
                    .foregroundStyle(Color(uiColor: .systemRed))
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
                    deleteHabit(scope: .thisOccurrence)
                },
                onDeleteAll: {
                    deleteHabit(scope: .allOccurrences)
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
                loadHabitData()
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

    private func loadHabitData() {
        title = habit.title ?? ""
        hasTime = habit.time != nil
        time = habit.time ?? Date()
        repeatOption = RepeatOption(rawValue: habit.repeatOption ?? "Daily") ?? .daily
        alertOption = AlertOption(rawValue: habit.alert ?? "None") ?? .none
        selectedFolderID = habit.folder?.id
        checklistDrafts = ChecklistStore.drafts(of: .habit(habit))
    }

    private func saveChanges() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a title"
            showError = true
            return
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: habit.date ?? Date())
        habit.title = title
        habit.time = hasTime ? calendar.combining(day: dayStart, andTimeFrom: time) : nil
        habit.repeatOption = repeatOption.rawValue
        habit.alert = alertOption.rawValue
        if habit.entity.relationshipsByName.keys.contains("folder") {
            habit.folder = folders.first { $0.id == selectedFolderID }
        }
        ChecklistStore.apply(checklistDrafts, to: .habit(habit), context: viewContext)

        let habitId = habit.id?.uuidString ?? ""
        NotificationManager.shared.cancelAllNotifications(for: habitId, itemType: "habit")
        Task {
            await NotificationManager.shared.requestAuthorization()
            await MainActor.run {
                NotificationManager.shared.scheduleNotification(for: habit)
            }
        }

        PersistenceController.shared.save()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }

    private func requestDelete() {
        if ItemActions.isRepeating(repeatOption: habit.repeatOption) {
            showRepeatDeleteConfirmation = true
        } else {
            deleteHabit(scope: .allOccurrences)
        }
    }

    private func deleteHabit(scope: RepeatDeleteScope) {
        ItemActions.deleteHabit(
            habit,
            scope: scope,
            occurrenceDay: Calendar.current.startOfDay(for: effectiveOccurrenceDay),
            context: viewContext
        )
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let habit = Habit(context: context)
    habit.id = UUID()
    habit.title = "Run"
    habit.date = Date()
    habit.repeatOption = RepeatOption.daily.rawValue
    return HabitDetailView(habit: habit)
        .environment(\.managedObjectContext, context)
}
