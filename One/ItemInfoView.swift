//
//  ItemInfoView.swift
//  One
//

import SwiftUI
import CoreData

enum ItemInfoTarget {
    case event(Event)
    case reminder(Reminder)
    case habit(Habit, occurrenceDay: Date?)
}

struct ItemInfoView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let item: ItemInfoTarget

    @State private var snapshot = ItemInfoSnapshot()
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date()
    @State private var hasTime: Bool = false
    @State private var isAllDay: Bool = true
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(3600)
    @State private var repeatOption: RepeatOption = .never
    @State private var alertOption: AlertOption = .none
    @State private var secondAlertOption: AlertOption = .none
    @State private var checklistDrafts: [ChecklistDraft] = []

    @State private var showEdit = false
    @State private var showRepeatDeleteConfirmation = false
    @State private var previewRequest: AttachmentPreviewRequest?
    @State private var isLoadingFields = false
    @State private var folders: [Folder] = []
    @State private var selectedFolderID: UUID?

    private var isHabit: Bool {
        if case .habit = item { return true }
        return false
    }

    private var usesHasTimeEditor: Bool {
        switch item {
        case .reminder, .habit:
            return true
        case .event:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection

                if snapshot.showsFlagToggle {
                    flagEditorSection
                }

                scheduleEditorSection
                recurrenceEditorSection
                folderEditorSection

                if !isHabit {
                    notesEditorSection
                }

                ChecklistEditorSection(drafts: $checklistDrafts)

                if !snapshot.attachments.isEmpty {
                    AttachmentsInfoSection(attachments: snapshot.attachments) { index in
                        presentPreview(startingAt: index)
                    }
                }

                if snapshot.showsHabitStats {
                    habitStatsSection
                }

                if snapshot.completionDateText != nil || snapshot.createdAtText != nil {
                    timestampsSection
                }

                deleteSection
            }
            .tint(.secondary)
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .listSectionSpacing(12)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton {
                        flushAndDismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        Haptics.light()
                        flushEdits()
                        showEdit = true
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Color.primaryText)
                }
            }
            .repeatDeleteConfirmation(
                isPresented: $showRepeatDeleteConfirmation,
                onDeleteThis: {
                    deleteItem(scope: .thisOccurrence)
                },
                onDeleteAll: {
                    deleteItem(scope: .allOccurrences)
                }
            )
            .sheet(isPresented: $showEdit) {
                editSheet
            }
            .sheet(item: $previewRequest) { request in
                AttachmentPreviewSheet(urls: request.urls, startIndex: request.startIndex) {
                    previewRequest = nil
                }
                .ignoresSafeArea()
            }
            .onAppear {
                reloadFolders()
                loadFields()
            }
            .onDisappear {
                flushEdits()
            }
            .onChange(of: showEdit) { _, isShowing in
                if !isShowing {
                    loadFields()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
                if managedObject.isDeleted || managedObject.managedObjectContext == nil {
                    dismiss()
                } else if !isLoadingFields {
                    reloadSnapshot()
                }
            }
            .onChange(of: title) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: notes) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: date) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: hasTime) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: isAllDay) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: startTime) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: endTime) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: repeatOption) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: alertOption) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: secondAlertOption) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: selectedFolderID) { _, _ in persistFieldsIfNeeded() }
            .onChange(of: checklistDrafts) { _, _ in persistChecklistIfNeeded() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                headerIcon

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.primaryText)

                    if !statusChips.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(statusChips, id: \.text) { chip in
                                Text(chip.text)
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(chip.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(chip.color.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
        }
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch item {
        case .event:
            Image(systemName: "calendar")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(Color.eventBlue)
                .frame(width: 36, height: 36)
        case .reminder:
            Button {
                toggleCompleted()
            } label: {
                Image(systemName: (snapshot.isCompleted ?? false) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(Color.reminderOrange)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: snapshot.isCompleted ?? false)
        case .habit:
            Button {
                toggleCompleted()
            } label: {
                Image(systemName: (snapshot.isCompleted ?? false) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(Color.flagRed)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: snapshot.isCompleted ?? false)
        }
    }

    private var flagEditorSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { snapshot.isFlagged ?? false },
                set: { _ in toggleFlagged() }
            )) {
                Label {
                    Text("Flagged")
                } icon: {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 16))
                }
            }
            .foregroundColor(Color.primaryText)
            .tint(.green)
            .sensoryFeedback(.selection, trigger: snapshot.isFlagged ?? false)
        }
    }

    // MARK: - Event / reminder / habit editors

    private var scheduleEditorSection: some View {
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

            if case .event = item {
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

            if usesHasTimeEditor {
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
    }

    private var recurrenceEditorSection: some View {
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

            if !isHabit, alertOption != .none {
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
    }

    private var folderEditorSection: some View {
        Section {
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
    }

    private var notesEditorSection: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .foregroundColor(Color.primaryText)
                .lineLimit(3...6)
        }
    }

    private var habitStatsSection: some View {
        Section {
            if let streak = snapshot.streak {
                infoRow(icon: "flame.fill", label: "Streak", value: "\(streak)")
            }
            if let total = snapshot.totalCompletions {
                infoRow(icon: "checkmark.circle", label: "Total completions", value: "\(total)")
            }

            if case .habit(let habit, _) = item {
                HabitActivityGrid(habit: habit)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
    }

    private var timestampsSection: some View {
        Section {
            if let completionDateText = snapshot.completionDateText {
                infoRow(icon: "checkmark.circle", label: "Completed", value: completionDateText)
            }
            if let createdAtText = snapshot.createdAtText {
                infoRow(icon: "sparkle", label: "Created", value: createdAtText)
            }
        }
    }

    private var deleteSection: some View {
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

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 16))
            }
            .foregroundColor(Color.primaryText)

            Spacer(minLength: 12)

            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Nested sheets

    @ViewBuilder
    private var editSheet: some View {
        switch item {
        case .event(let event):
            ItemDetailView(item: .event(event))
        case .reminder(let reminder):
            ItemDetailView(item: .reminder(reminder))
        case .habit(let habit, let occurrenceDay):
            HabitDetailView(habit: habit, occurrenceDay: occurrenceDay)
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: - Snapshot / load

    private var managedObject: NSManagedObject {
        switch item {
        case .event(let event): return event
        case .reminder(let reminder): return reminder
        case .habit(let habit, _): return habit
        }
    }

    private var occurrenceDay: Date {
        switch item {
        case .event:
            return Calendar.current.startOfDay(for: date)
        case .reminder:
            return Calendar.current.startOfDay(for: date)
        case .habit(let habit, let day):
            return Calendar.current.startOfDay(for: day ?? habit.date ?? Date())
        }
    }

    private var statusChips: [(text: String, color: Color)] {
        var chips: [(text: String, color: Color)] = []
        if snapshot.isOverdue {
            chips.append((String(localized: "Overdue"), Color.flagRed))
        }
        return chips
    }

    private func reloadSnapshot() {
        snapshot = ItemInfoSnapshot(item: item)
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

    private func loadFields() {
        isLoadingFields = true
        switch item {
        case .event(let event):
            title = event.title ?? ""
            notes = event.notes ?? ""
            date = event.date ?? Date()
            isAllDay = event.isAllDay
            startTime = event.startTime ?? Date()
            endTime = event.endTime ?? Date().addingTimeInterval(3600)
            repeatOption = RepeatOption(rawValue: event.repeatOption ?? "Never") ?? .never
            alertOption = AlertOption(rawValue: event.alert ?? "None") ?? .none
            if event.entity.attributesByName.keys.contains("secondAlert") {
                let value = event.value(forKey: "secondAlert") as? String ?? "None"
                secondAlertOption = AlertOption(rawValue: value) ?? .none
            }
            checklistDrafts = ChecklistStore.drafts(of: .event(event))
            selectedFolderID = event.folder?.id
        case .reminder(let reminder):
            title = reminder.title ?? ""
            notes = reminder.notes ?? ""
            date = reminder.date ?? Date()
            hasTime = reminder.time != nil
            startTime = reminder.time ?? Date()
            repeatOption = RepeatOption(rawValue: reminder.repeatOption ?? "Never") ?? .never
            alertOption = AlertOption(rawValue: reminder.alert ?? "None") ?? .none
            if reminder.entity.attributesByName.keys.contains("secondAlert") {
                let value = reminder.value(forKey: "secondAlert") as? String ?? "None"
                secondAlertOption = AlertOption(rawValue: value) ?? .none
            }
            checklistDrafts = ChecklistStore.drafts(of: .reminder(reminder))
            selectedFolderID = reminder.folder?.id
        case .habit(let habit, _):
            title = habit.title ?? ""
            date = habit.date ?? Date()
            hasTime = habit.time != nil
            startTime = habit.time ?? Date()
            repeatOption = RepeatOption(rawValue: habit.repeatOption ?? "Daily") ?? .daily
            alertOption = AlertOption(rawValue: habit.alert ?? "None") ?? .none
            selectedFolderID = habit.folder?.id
            checklistDrafts = ChecklistStore.drafts(of: .habit(habit))
        }
        reloadSnapshot()
        DispatchQueue.main.async {
            isLoadingFields = false
        }
    }

    /// Next full minute from `date` (seconds zeroed) so calendar notification triggers stay valid.
    private static func nextMinute(from date: Date) -> Date {
        let calendar = Calendar.current
        let truncated = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        ) ?? date
        return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? date.addingTimeInterval(60)
    }

    /// QuickLook needs files on disk, so every attachment is materialized before presenting.
    /// Attachments that fail to write are skipped, and the start index shifts to match.
    private func presentPreview(startingAt index: Int) {
        var urls: [URL] = []
        var resolvedStart = 0
        for (offset, ref) in snapshot.attachments.enumerated() {
            guard let url = AttachmentStore.previewURL(for: ref, context: viewContext) else { continue }
            if offset == index { resolvedStart = urls.count }
            urls.append(url)
        }
        guard !urls.isEmpty else { return }
        previewRequest = AttachmentPreviewRequest(urls: urls, startIndex: resolvedStart)
    }

    // MARK: - Persist

    private func persistFieldsIfNeeded() {
        guard !isLoadingFields else { return }
        persistFields(applyChecklist: false)
    }

    private func persistChecklistIfNeeded() {
        guard !isLoadingFields else { return }
        persistFields(applyChecklist: true)
    }

    private func flushEdits() {
        persistFields(applyChecklist: true)
    }

    private func flushAndDismiss() {
        flushEdits()
        dismiss()
    }

    private func persistFields(applyChecklist: Bool) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        switch item {
        case .event(let event):
            if !trimmedTitle.isEmpty {
                event.title = trimmedTitle
            }
            event.date = dayStart
            event.isAllDay = isAllDay
            event.startTime = isAllDay ? nil : calendar.combining(day: dayStart, andTimeFrom: startTime)
            event.endTime = isAllDay ? nil : calendar.combining(day: dayStart, andTimeFrom: endTime)
            event.repeatOption = repeatOption.rawValue
            event.alert = alertOption.rawValue
            if event.entity.attributesByName.keys.contains("secondAlert") {
                event.setValue(secondAlertOption.rawValue, forKey: "secondAlert")
            }
            event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if event.entity.relationshipsByName.keys.contains("folder") {
                event.folder = folders.first { $0.id == selectedFolderID }
            }
            if applyChecklist {
                ChecklistStore.apply(checklistDrafts, to: .event(event), context: viewContext)
                adoptSavedChecklistIDs(ChecklistStore.drafts(of: .event(event)))
            }
            let eventId = event.id?.uuidString ?? ""
            NotificationManager.shared.cancelAllNotifications(for: eventId, itemType: "event")
            Task {
                await NotificationManager.shared.requestAuthorization()
                await MainActor.run {
                    NotificationManager.shared.scheduleNotification(for: event)
                }
            }

        case .reminder(let reminder):
            if !trimmedTitle.isEmpty {
                reminder.title = trimmedTitle
            }
            reminder.date = dayStart
            reminder.time = hasTime ? calendar.combining(day: dayStart, andTimeFrom: startTime) : nil
            reminder.repeatOption = repeatOption.rawValue
            reminder.alert = alertOption.rawValue
            if reminder.entity.attributesByName.keys.contains("secondAlert") {
                reminder.setValue(secondAlertOption.rawValue, forKey: "secondAlert")
            }
            reminder.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if reminder.entity.relationshipsByName.keys.contains("folder") {
                reminder.folder = folders.first { $0.id == selectedFolderID }
            }
            if applyChecklist {
                ChecklistStore.apply(checklistDrafts, to: .reminder(reminder), context: viewContext)
                adoptSavedChecklistIDs(ChecklistStore.drafts(of: .reminder(reminder)))
            }
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

        case .habit(let habit, _):
            if !trimmedTitle.isEmpty {
                habit.title = trimmedTitle
            }
            habit.date = dayStart
            habit.time = hasTime ? calendar.combining(day: dayStart, andTimeFrom: startTime) : nil
            habit.repeatOption = repeatOption.rawValue
            habit.alert = alertOption.rawValue
            if habit.entity.relationshipsByName.keys.contains("folder") {
                habit.folder = folders.first { $0.id == selectedFolderID }
            }
            if applyChecklist {
                ChecklistStore.apply(checklistDrafts, to: .habit(habit), context: viewContext)
                adoptSavedChecklistIDs(ChecklistStore.drafts(of: .habit(habit)))
            }
            let habitId = habit.id?.uuidString ?? ""
            NotificationManager.shared.cancelAllNotifications(for: habitId, itemType: "habit")
            Task {
                await NotificationManager.shared.requestAuthorization()
                await MainActor.run {
                    NotificationManager.shared.scheduleNotification(for: habit)
                }
            }
        }

        PersistenceController.shared.save()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        reloadSnapshot()
    }

    /// After apply, stamp `existingObjectID` onto matching drafts so the next keystroke
    /// updates the same row instead of inserting a duplicate.
    private func adoptSavedChecklistIDs(_ saved: [ChecklistDraft]) {
        let ids = Dictionary(uniqueKeysWithValues: saved.compactMap { draft -> (UUID, NSManagedObjectID)? in
            guard let objectID = draft.existingObjectID else { return nil }
            return (draft.id, objectID)
        })
        guard !ids.isEmpty else { return }
        isLoadingFields = true
        for index in checklistDrafts.indices {
            if checklistDrafts[index].existingObjectID == nil,
               let objectID = ids[checklistDrafts[index].id] {
                checklistDrafts[index].existingObjectID = objectID
            }
        }
        DispatchQueue.main.async {
            isLoadingFields = false
        }
    }

    private func persistChange() {
        PersistenceController.shared.save()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        reloadSnapshot()
    }

    private func toggleCompleted() {
        Haptics.selection()
        switch item {
        case .event:
            return
        case .reminder(let reminder):
            if reminder.isCompleted {
                reminder.isCompleted = false
                reminder.completionDate = nil
                if let reminderId = reminder.id?.uuidString {
                    NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
                    NotificationManager.shared.scheduleNotification(for: reminder)
                }
            } else {
                _ = reminder.completeOrRollForward()
            }
            persistChange()
            loadFields()
        case .habit(let habit, _):
            let day = occurrenceDay
            habit.setCompleted(!habit.isCompleted(on: day), on: day)
            persistChange()
        }
    }

    private func toggleFlagged() {
        Haptics.selection()
        switch item {
        case .event(let event):
            event.isFlagged.toggle()
        case .reminder(let reminder):
            reminder.isFlagged.toggle()
        case .habit:
            return
        }
        persistChange()
    }

    private func requestDelete() {
        let repeating: Bool
        switch item {
        case .event(let event):
            repeating = ItemActions.isRepeating(repeatOption: event.repeatOption)
        case .reminder(let reminder):
            repeating = ItemActions.isRepeating(repeatOption: reminder.repeatOption)
        case .habit(let habit, _):
            repeating = ItemActions.isRepeating(repeatOption: habit.repeatOption)
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
                occurrenceDay: occurrenceDay,
                context: viewContext
            )
        case .reminder(let reminder):
            ItemActions.deleteReminder(
                reminder,
                scope: scope,
                occurrenceDay: occurrenceDay,
                context: viewContext
            )
        case .habit(let habit, _):
            ItemActions.deleteHabit(
                habit,
                scope: scope,
                occurrenceDay: occurrenceDay,
                context: viewContext
            )
        }
        dismiss()
    }
}

// MARK: - Snapshot

private struct ItemInfoSnapshot {
    var title: String = ""
    var isCompleted: Bool?
    var isFlagged: Bool?
    var isOverdue: Bool = false
    var dateText: String = ""
    var timeText: String = ""
    var repeatText: String?
    var alertText: String?
    var folderText: String?
    var streak: Int?
    var totalCompletions: Int?
    var completionDateText: String?
    var createdAtText: String?
    var attachments: [AttachmentRef] = []
    var showsFlagToggle: Bool = false
    var showsHabitStats: Bool = false

    init() {}

    init(item: ItemInfoTarget) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        switch item {
        case .event(let event):
            title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? String(localized: "Untitled Event")
            isFlagged = event.isFlagged
            showsFlagToggle = true
            if !event.isAllDay, let eventDate = event.date {
                isOverdue = calendar.startOfDay(for: eventDate) < todayStart
            }
            applySharedMeta(
                repeatOption: event.repeatOption,
                defaultRepeat: .never,
                alert: event.alert,
                folder: event.folder,
                createdAt: event.oneCreatedAt
            )
            attachments = AttachmentStore.refs(of: .event(event))

        case .reminder(let reminder):
            title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? String(localized: "Untitled Reminder")
            isCompleted = reminder.isCompleted
            isFlagged = reminder.isFlagged
            showsFlagToggle = true
            if !reminder.isCompleted, let reminderDate = reminder.date {
                isOverdue = calendar.startOfDay(for: reminderDate) < todayStart
            }
            dateText = Self.fullDate(reminder.date)
            if let time = reminder.time {
                timeText = Self.time(time)
            } else {
                timeText = String(localized: "No time")
            }
            applySharedMeta(
                repeatOption: reminder.repeatOption,
                defaultRepeat: .never,
                alert: reminder.alert,
                folder: reminder.folder,
                createdAt: reminder.oneCreatedAt
            )
            if let completionDate = reminder.completionDate {
                completionDateText = Self.dateAndTime(completionDate)
            }
            attachments = AttachmentStore.refs(of: .reminder(reminder))

        case .habit(let habit, let occurrenceDay):
            let day = calendar.startOfDay(for: occurrenceDay ?? habit.date ?? Date())
            let dayCompleted = habit.isCompleted(on: day)
            title = habit.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? String(localized: "Untitled Habit")
            isCompleted = dayCompleted
            showsHabitStats = true
            // Habits use missed-day squares, not an overdue state.
            dateText = Self.fullDate(day)
            if let time = habit.time {
                timeText = Self.time(time)
            } else {
                timeText = String(localized: "No time")
            }
            applySharedMeta(
                repeatOption: habit.repeatOption,
                defaultRepeat: .daily,
                alert: habit.alert,
                folder: habit.folder,
                createdAt: habit.oneCreatedAt
            )
            streak = habit.currentStreak(calendar: calendar)
            totalCompletions = habit.completedOccurrenceDays(calendar: calendar).count
            if let completionDate = habit.completionDate {
                completionDateText = Self.dateAndTime(completionDate)
            }
        }
    }

    private mutating func applySharedMeta(
        repeatOption raw: String?,
        defaultRepeat: RepeatOption,
        alert rawAlert: String?,
        folder: Folder?,
        createdAt: Date?
    ) {
        let option = RepeatOption(rawValue: raw ?? defaultRepeat.rawValue) ?? defaultRepeat
        if option != .never {
            repeatText = option.localizedTitle
        }
        let alert = AlertOption(rawValue: rawAlert ?? "None") ?? .none
        if alert != .none {
            alertText = alert.localizedTitle
        }
        if let folder {
            folderText = FolderStore.displayName(for: folder)
        }
        if let createdAt {
            createdAtText = Self.dateAndTime(createdAt)
        }
    }

    private static func fullDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .complete, time: .omitted)
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func dateAndTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension NSManagedObject {
    var oneCreatedAt: Date? {
        guard entity.attributesByName.keys.contains("createdAt") else { return nil }
        return value(forKey: "createdAt") as? Date
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let reminder = Reminder(context: context)
    reminder.id = UUID()
    reminder.title = "Shop"
    reminder.date = Date()
    reminder.time = Date().addingTimeInterval(3600)
    reminder.notes = "Don't forget milk again"
    reminder.createdAt = Date()
    return ItemInfoView(item: .reminder(reminder))
        .environment(\.managedObjectContext, context)
}
