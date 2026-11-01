//
//  CalendarSheetItemRow.swift
//  One
//

import SwiftUI
import CoreData

enum CalendarSheetFilter: Hashable {
    case all
    case events
    case reminders
    case habits
    case folder(UUID)

    func menuTitle(folders: [Folder] = []) -> String {
        switch self {
        case .all: return "All"
        case .events: return "Events"
        case .reminders: return "Reminders"
        case .habits: return "Habits"
        case .folder(let id):
            if let folder = folders.first(where: { $0.id == id }) {
                return FolderStore.displayName(for: folder)
            }
            return String(localized: "Folder")
        }
    }

    var showsEvents: Bool {
        switch self {
        case .all, .events, .folder: return true
        case .reminders, .habits: return false
        }
    }

    var showsReminders: Bool {
        switch self {
        case .all, .reminders, .folder: return true
        case .events, .habits: return false
        }
    }

    var showsHabits: Bool {
        switch self {
        case .all, .habits, .folder: return true
        case .events, .reminders: return false
        }
    }

    func matchesFolder(_ itemFolderID: UUID?) -> Bool {
        switch self {
        case .folder(let id): return itemFolderID == id
        default: return true
        }
    }

    /// Noun phrase for empty-state copy, e.g. "events", "flagged reminders".
    func emptyListSubject(flaggedOnly: Bool) -> String {
        switch self {
        case .events:
            return flaggedOnly ? String(localized: "flagged events") : String(localized: "events")
        case .reminders:
            return flaggedOnly ? String(localized: "flagged reminders") : String(localized: "reminders")
        case .habits:
            return flaggedOnly ? String(localized: "flagged habits") : String(localized: "habits")
        case .all:
            return flaggedOnly ? String(localized: "flagged items") : String(localized: "events/reminders/habits")
        case .folder:
            return flaggedOnly ? String(localized: "flagged items") : String(localized: "items")
        }
    }
}

struct CalendarSheetItemRow: View {
    private let content: AnyView

    init(
        item: Event,
        showsItemDate: Bool = false,
        occurrenceDay: Date? = nil,
        leadingIconColor: Color? = nil,
        onTap: @escaping () -> Void
    ) {
        let day = occurrenceDay ?? item.date ?? Date()
        content = AnyView(
            CalendarEventSheetRow(
                event: item,
                showsItemDate: showsItemDate,
                occurrenceDay: day,
                leadingIconColor: leadingIconColor,
                onTap: onTap
            )
        )
    }

    init(
        item: Reminder,
        showsItemDate: Bool = false,
        occurrenceDay: Date? = nil,
        leadingIconColor: Color? = nil,
        onTap: @escaping () -> Void
    ) {
        let day = occurrenceDay ?? item.date ?? Date()
        content = AnyView(
            CalendarReminderSheetRow(
                reminder: item,
                showsItemDate: showsItemDate,
                occurrenceDay: day,
                leadingIconColor: leadingIconColor,
                onTap: onTap
            )
        )
    }

    init(
        item: Habit,
        showsItemDate: Bool = false,
        occurrenceDay: Date? = nil,
        leadingIconColor: Color? = nil,
        onTap: @escaping () -> Void
    ) {
        let day = occurrenceDay ?? item.date ?? Date()
        content = AnyView(
            CalendarHabitSheetRow(
                habit: item,
                showsItemDate: showsItemDate,
                occurrenceDay: day,
                leadingIconColor: leadingIconColor,
                onTap: onTap
            )
        )
    }

    var body: some View {
        content
    }
}

private struct CalendarEventSheetRow: View {
    @ObservedObject var event: Event
    var showsItemDate: Bool
    var occurrenceDay: Date
    var leadingIconColor: Color?
    let onTap: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showRepeatDeleteConfirmation = false

    var body: some View {
        CalendarSheetItemRowLayout(
            showsItemDate: showsItemDate,
            itemDate: event.date,
            isOverdue: false,
            titleUsesOverdueColor: false,
            isCompleted: false,
            title: event.title ?? "Untitled Event",
            isFlagged: event.isFlagged,
            isRepeating: itemHasRepeat(event.repeatOption),
            folderName: event.folder?.name,
            notes: event.notes,
            timeText: eventTimeText,
            timeUsesOverdueColor: false,
            onTap: onTap,
            onDelete: { requestDelete() }
        ) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(leadingIconColor ?? Color.eventBlue)
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
    }

    private func requestDelete() {
        if ItemActions.isRepeating(repeatOption: event.repeatOption) {
            showRepeatDeleteConfirmation = true
        } else {
            ItemActions.delete(event, context: viewContext)
        }
    }

    private var eventTimeText: String? {
        guard !event.isAllDay, let startTime = event.startTime else { return nil }
        return calendarSheetTimeRangeText(start: startTime, end: event.endTime)
    }
}

private struct CalendarReminderSheetRow: View {
    @ObservedObject var reminder: Reminder
    var showsItemDate: Bool
    var occurrenceDay: Date
    var leadingIconColor: Color?
    let onTap: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showRepeatDeleteConfirmation = false

    var body: some View {
        CalendarSheetItemRowLayout(
            showsItemDate: showsItemDate,
            itemDate: reminder.date,
            isOverdue: false,
            titleUsesOverdueColor: false,
            isCompleted: reminder.isCompleted,
            title: reminder.title ?? "Untitled Reminder",
            isFlagged: reminder.isFlagged,
            isRepeating: itemHasRepeat(reminder.repeatOption),
            folderName: reminder.folder?.name,
            notes: reminder.notes,
            timeText: reminder.time.map(calendarSheetFormatTime),
            timeUsesOverdueColor: false,
            onTap: onTap,
            onDelete: { requestDelete() }
        ) {
            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(leadingIconColor ?? Color.reminderOrange)
                .scaleEffect(reminder.isCompleted ? 1.1 : 1.0)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        Haptics.light()
                        let wasCompleted = reminder.isCompleted
                        if !wasCompleted {
                            _ = reminder.completeOrRollForward()
                        } else {
                            reminder.isCompleted = false
                            reminder.completionDate = nil
                            if let reminderId = reminder.id?.uuidString {
                                NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
                                NotificationManager.shared.scheduleNotification(for: reminder)
                            }
                        }
                        do {
                            try viewContext.save()
                            PersistenceController.shared.save()
                            NotificationCenter.default.post(name: .dataDidChange, object: nil)
                        } catch {
                            #if DEBUG
                            print("Error saving context: \(error.localizedDescription)")
                            #endif
                        }
                    }
                )
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
    }

    private func requestDelete() {
        if ItemActions.isRepeating(repeatOption: reminder.repeatOption) {
            showRepeatDeleteConfirmation = true
        } else {
            ItemActions.delete(reminder, context: viewContext)
        }
    }
}

private struct CalendarHabitSheetRow: View {
    @ObservedObject var habit: Habit
    var showsItemDate: Bool
    var occurrenceDay: Date
    var leadingIconColor: Color?
    let onTap: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showRepeatDeleteConfirmation = false

    var body: some View {
        let dayCompleted = habit.isCompleted(on: occurrenceDay)
        return CalendarSheetItemRowLayout(
            showsItemDate: showsItemDate,
            itemDate: habit.date,
            isOverdue: false,
            titleUsesOverdueColor: false,
            isCompleted: dayCompleted,
            title: habit.title ?? "Untitled Habit",
            isFlagged: false,
            isRepeating: ItemActions.isRepeating(repeatOption: habit.repeatOption),
            showsRepeatIndicator: false,
            folderName: habit.folder?.name,
            notes: nil,
            timeText: nil,
            timeUsesOverdueColor: false,
            onTap: onTap,
            onDelete: { requestDelete() },
            leadingIcon: {
                Image(systemName: dayCompleted ? "checkmark.circle.dotted" : "circle.dotted")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(leadingIconColor ?? Color.flagRed)
                    .scaleEffect(dayCompleted ? 1.1 : 1.0)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            Haptics.light()
                            habit.setCompleted(!dayCompleted, on: occurrenceDay)
                            do {
                                try viewContext.save()
                                PersistenceController.shared.save()
                                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                            } catch {
                                #if DEBUG
                                print("Error saving context: \(error.localizedDescription)")
                                #endif
                            }
                        }
                    )
            },
            trailingAccessory: {
                HabitFlamePill(streak: habit.currentStreak())
            }
        )
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
    }

    private func requestDelete() {
        if ItemActions.isRepeating(repeatOption: habit.repeatOption) {
            showRepeatDeleteConfirmation = true
        } else {
            ItemActions.delete(habit, context: viewContext)
        }
    }
}

private struct CalendarSheetItemRowLayout<Leading: View, Trailing: View>: View {
    var showsItemDate: Bool
    var itemDate: Date?
    var isOverdue: Bool
    var titleUsesOverdueColor: Bool
    var isCompleted: Bool = false
    var title: String
    var isFlagged: Bool
    var isRepeating: Bool
    /// When false, the title omits RepeatIndicator (habits) while swipe still uses `isRepeating`.
    var showsRepeatIndicator: Bool = true
    var folderName: String?
    var notes: String?
    var timeText: String?
    var timeUsesOverdueColor: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let leadingIcon: () -> Leading
    @ViewBuilder let trailingAccessory: () -> Trailing

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: showsItemDate ? 6 : 12) {
                leadingIcon()

                if showsItemDate, let itemDate {
                    Text(calendarSheetFormatItemDate(itemDate))
                        .font(.caption)
                        .foregroundColor(isOverdue ? Color.flagRed : Color.primaryText.opacity(0.9))
                        .frame(minWidth: 36, alignment: .leading)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(
                                isCompleted
                                    ? Color.primaryText.opacity(0.45)
                                    : (titleUsesOverdueColor ? Color.flagRed : Color.primaryText)
                            )
                            .lineLimit(1)

                        if isFlagged {
                            FlagIndicator()
                        }

                        if showsRepeatIndicator && isRepeating {
                            RepeatIndicator()
                        }
                    }

                    if !showsItemDate {
                        FolderNotesMetaRow(folderName: folderName, notes: notes)
                    }
                }

                Spacer(minLength: showsItemDate ? 4 : 8)

                trailingAccessory()

                if let timeText {
                    Text(timeText)
                        .font(.caption)
                        .foregroundColor(
                            isCompleted
                                ? Color.primaryText.opacity(0.4)
                                : (timeUsesOverdueColor ? Color.flagRed : Color.primaryText.opacity(0.9))
                        )
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: !isRepeating) {
            // Destructive role eagerly removes the row; repeating deletes need a confirmation first.
            if isRepeating {
                Button {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color(uiColor: .systemRed))
            } else {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color(uiColor: .systemRed))
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

extension CalendarSheetItemRowLayout where Trailing == EmptyView {
    init(
        showsItemDate: Bool,
        itemDate: Date?,
        isOverdue: Bool,
        titleUsesOverdueColor: Bool,
        isCompleted: Bool = false,
        title: String,
        isFlagged: Bool,
        isRepeating: Bool,
        folderName: String?,
        notes: String?,
        timeText: String?,
        timeUsesOverdueColor: Bool,
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder leadingIcon: @escaping () -> Leading
    ) {
        self.showsItemDate = showsItemDate
        self.itemDate = itemDate
        self.isOverdue = isOverdue
        self.titleUsesOverdueColor = titleUsesOverdueColor
        self.isCompleted = isCompleted
        self.title = title
        self.isFlagged = isFlagged
        self.isRepeating = isRepeating
        self.showsRepeatIndicator = true
        self.folderName = folderName
        self.notes = notes
        self.timeText = timeText
        self.timeUsesOverdueColor = timeUsesOverdueColor
        self.onTap = onTap
        self.onDelete = onDelete
        self.leadingIcon = leadingIcon
        self.trailingAccessory = { EmptyView() }
    }
}

private func calendarSheetFormatItemDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let itemYear = calendar.component(.year, from: date)
    let currentYear = calendar.component(.year, from: Date())

    let formatter = DateFormatter()
    if itemYear == currentYear {
        formatter.dateFormat = "d MMM"
    } else {
        formatter.dateFormat = "yyyy"
    }
    return formatter.string(from: date)
}

private func calendarSheetFormatTime(_ time: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter.string(from: time).lowercased()
}

private func calendarSheetTimeRangeText(start: Date, end: Date?) -> String {
    let startStr = calendarSheetFormatTime(start)
    if let end {
        return "\(startStr) - \(calendarSheetFormatTime(end))"
    }
    return startStr
}

struct FolderNotesMetaRow: View {
    var folderName: String?
    var notes: String?

    var body: some View {
        let hasFolder = folderName.map { !$0.isEmpty } ?? false
        let hasNotes = notes.map { !$0.isEmpty } ?? false

        if hasFolder || hasNotes {
            HStack(spacing: 6) {
                if hasFolder, let folderName {
                    FolderNamePill(name: FolderStore.displayName(forName: folderName))
                }
                if hasNotes, let notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct FolderNamePill: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color.primaryText.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.pillBackground)
            .clipShape(Capsule())
    }
}

struct FlagIndicator: View {
    var body: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: 11))
            .foregroundColor(Color.flagRed)
    }
}

struct RepeatIndicator: View {
    var body: some View {
        Image(systemName: "repeat")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.gray)
    }
}

func itemHasRepeat(_ raw: String?) -> Bool {
    let option = RepeatOption(rawValue: raw ?? RepeatOption.never.rawValue) ?? .never
    return option != .never
}

struct SheetClosePill: View {
    var size: CGFloat = 32
    var action: () -> Void

    private var iconSize: CGFloat {
        size * (11.0 / 32.0)
    }

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(Color.primaryText)
                .frame(width: size, height: size)
                .glassCircleClose()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Nav-toolbar cancel — icon only (no glass disc; glass looks gray in nav bars).
struct ToolbarGlassCancelButton: View {
    var action: () -> Void
    var accessibilityLabelText: String = "Cancel"

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.primaryText)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
    }
}

/// Nav-toolbar save/done — system glassProminent + red tint, light red checkmark.
struct ToolbarGlassConfirmButton: View {
    var accessibilityLabelText: String = "Save"
    var isEnabled: Bool = true
    var action: () -> Void

    private var checkmarkLightRed: Color {
        Color(red: 1.0, green: 0.72, blue: 0.72)
    }

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "checkmark")
                .foregroundStyle(checkmarkLightRed)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.flagRed)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabelText)
    }
}

struct CalendarSheetFilterBar: View {
    @Binding var sheetFilter: CalendarSheetFilter
    @Binding var showFlaggedOnly: Bool
    var folders: [Folder] = []
    var alarmCount: Int = 0
    var onAlarmTap: (() -> Void)? = nil

    private var pillTitle: String {
        sheetFilter.menuTitle(folders: folders)
    }

    private var isFilterActive: Bool {
        if case .all = sheetFilter { return false }
        return true
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All") {
                    Haptics.selection()
                    sheetFilter = .all
                }
                Button("Events") {
                    Haptics.selection()
                    sheetFilter = .events
                }
                Button("Reminders") {
                    Haptics.selection()
                    sheetFilter = .reminders
                }
                Button("Habits") {
                    Haptics.selection()
                    sheetFilter = .habits
                }

                if !folders.isEmpty {
                    Divider()
                    ForEach(folders, id: \.objectID) { folder in
                        Button(FolderStore.displayName(for: folder)) {
                            Haptics.selection()
                            if let id = folder.id {
                                sheetFilter = .folder(id)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(pillTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(Color.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .sheetFilterPill(active: isFilterActive)
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Button {
                Haptics.selection()
                showFlaggedOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.flagRed)
                    Text("Flagged")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(Color.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .sheetFilterPill(active: showFlaggedOnly)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            if onAlarmTap != nil, alarmCount > 0 {
                Button {
                    Haptics.selection()
                    onAlarmTap?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "alarm")
                            .font(.system(size: 11))
                            .foregroundColor(Color.alarmOrange)
                        Text("\(alarmCount)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(Color.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .sheetFilterPill()
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

private extension View {
    /// Liquid glass on the flat white light-mode sheet reads as a dark drop shadow,
    /// so light mode uses a flat white pill with a hairline border instead.
    func sheetFilterPill(active: Bool = false) -> some View {
        modifier(SheetFilterPillModifier(active: active))
    }
}

private struct SheetFilterPillModifier: ViewModifier {
    let active: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.glassCapsulePill(active: active)
        } else {
            content.background {
                Capsule()
                    .fill(Color.white)
                    .overlay {
                        Capsule().strokeBorder(
                            Color.primaryText.opacity(active ? 0.35 : 0.1),
                            lineWidth: active ? 1.2 : 1
                        )
                    }
            }
        }
    }
}
