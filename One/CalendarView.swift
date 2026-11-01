//
//  CalendarView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import CoreData

struct CalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var selectedDayManager = SelectedDayManager.shared
    
    private static let eventsRequest: NSFetchRequest<Event> = {
        let r = NSFetchRequest<Event>(entityName: "Event")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.date, ascending: true)]
        return r
    }()
    private static let remindersRequest: NSFetchRequest<Reminder> = {
        let r = NSFetchRequest<Reminder>(entityName: "Reminder")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Reminder.date, ascending: true)]
        return r
    }()
    private static let habitsRequest: NSFetchRequest<Habit> = {
        let r = NSFetchRequest<Habit>(entityName: "Habit")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Habit.date, ascending: true)]
        return r
    }()
    
    @FetchRequest(fetchRequest: eventsRequest)
    private var events: FetchedResults<Event>
    
    @FetchRequest(fetchRequest: remindersRequest)
    private var reminders: FetchedResults<Reminder>

    @FetchRequest(fetchRequest: habitsRequest)
    private var habits: FetchedResults<Habit>
    
    @State private var currentMonth = Date()
    @State private var selectedDay: Date? = nil
    @State private var selectedEvent: Event? = nil
    @State private var selectedReminder: Reminder? = nil
    @State private var selectedHabit: Habit? = nil
    @State private var selectedHabitOccurrenceDay: Date? = nil
    @State private var showMonthYearPicker = false
    @State private var monthSlideDirection: Int = 0
    @State private var isMonthChanging = false
    @State private var sheetDetent: SheetDetent = .mid
    @State private var foldersSheetDetent: SheetDetent = .mid
    @State private var folderItemsSheetDetent: SheetDetent = .mid
    @State private var showFolders = false
    @State private var showAlarms = false
    @State private var showFoldersBar = false
    @State private var foldersBarFrame: CGRect = .zero
    @State private var calendarContainerHeight: CGFloat = 0
    @State private var viewingFolder: Folder?
    @State private var sheetFilter: CalendarSheetFilter = .all
    @State private var showFlaggedOnly = false
    @State private var folders: [Folder] = []
    @State private var alarms: [Alarm] = []
    @State private var alarmsSheetDetent: SheetDetent = .mid
    
    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    // Computed property to get current month range
    private var currentMonthRange: (start: Date, end: Date) {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        let endOfMonthStart = calendar.startOfDay(for: endOfMonth)
        let endOfMonthEnd = calendar.date(byAdding: .day, value: 1, to: endOfMonthStart)!
        return (startOfMonth, endOfMonthEnd)
    }

    /// Sheet height delta vs mid detent: positive covers FoldersBar; negative drops the sheet below it.
    private var foldersCoverExtraHeight: CGFloat {
        guard calendarContainerHeight > 0,
              foldersBarFrame != .zero else { return 0 }
        let midHeight = SheetDetent.mid.height(in: calendarContainerHeight)
        // Hidden: sheet top at folders bar top. Shown: sit clearly below the bar.
        let revealPadding: CGFloat = 16
        let targetTop = showFoldersBar
            ? foldersBarFrame.maxY + revealPadding
            : foldersBarFrame.minY
        let targetHeight = calendarContainerHeight - targetTop
        return targetHeight - midHeight
    }

    private var alarmCountForSelectedDay: Int {
        AlarmDaySchedule.countFiring(
            on: selectedDay ?? Date(),
            in: alarms,
            calendar: calendar
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    monthlyCalendarView

                    VStack(spacing: 0) {
                        FoldersBar(onTap: {
                            showAlarms = false
                            showFolders = true
                        })
                        AlarmBar(onTap: {
                            showFolders = false
                            viewingFolder = nil
                            showAlarms = true
                        })
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: FoldersBarFrameKey.self,
                                value: proxy.frame(in: .named("calendarContainer"))
                            )
                        }
                    )

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onPreferenceChange(FoldersBarFrameKey.self) { foldersBarFrame = $0 }
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear {
                            calendarContainerHeight = proxy.size.height
                        }
                        .onChange(of: proxy.size.height) { _, height in
                            calendarContainerHeight = height
                        }
                    }
                )

                if !showFolders && viewingFolder == nil && !showAlarms {
                    CalendarDaySheet(
                        detent: $sheetDetent,
                        coverExtraHeight: foldersCoverExtraHeight,
                        header: {
                            CalendarSheetFilterBar(
                                sheetFilter: $sheetFilter,
                                showFlaggedOnly: $showFlaggedOnly,
                                folders: folders,
                                alarmCount: alarmCountForSelectedDay,
                                onAlarmTap: {
                                    showFolders = false
                                    viewingFolder = nil
                                    showAlarms = true
                                }
                            )
                        },
                        content: {
                            sheetItemsList
                        }
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showFoldersBar)
                }

                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        if showFolders {
                            FoldersBottomSheet(
                                detent: $foldersSheetDetent,
                                isPresented: $showFolders,
                                containerHeight: geo.size.height
                            ) {
                                FoldersView(
                                    onFolderSelected: { folder in
                                        viewingFolder = folder
                                    },
                                    onFolderDeleted: { folder in
                                        if viewingFolder?.objectID == folder.objectID {
                                            viewingFolder = nil
                                        }
                                    },
                                    isPresented: $showFolders,
                                    bottomContentInset: BottomSheetMetrics.tabBarContentInset
                                )
                                .environment(\.managedObjectContext, viewContext)
                            }
                            .transition(.move(edge: .bottom))
                        }

                        if let folder = viewingFolder {
                            FoldersBottomSheet(
                                detent: $folderItemsSheetDetent,
                                isPresented: Binding(
                                    get: { viewingFolder != nil },
                                    set: { if !$0 { viewingFolder = nil } }
                                ),
                                containerHeight: geo.size.height
                            ) {
                                FolderItemsView(
                                    folder: folder,
                                    bottomContentInset: BottomSheetMetrics.tabBarContentInset,
                                    onBack: {
                                        viewingFolder = nil
                                        showFolders = true
                                    },
                                    onClose: { viewingFolder = nil },
                                    onSelectEvent: { selectedEvent = $0 },
                                    onSelectReminder: { selectedReminder = $0 },
                                    onSelectHabit: { selectedHabit = $0 }
                                )
                                .environment(\.managedObjectContext, viewContext)
                            }
                            .transition(.move(edge: .bottom))
                        }

                        if showAlarms {
                            FoldersBottomSheet(
                                detent: $alarmsSheetDetent,
                                isPresented: $showAlarms,
                                containerHeight: geo.size.height
                            ) {
                                AlarmView(
                                    isPresented: $showAlarms,
                                    bottomContentInset: BottomSheetMetrics.tabBarContentInset
                                )
                                .environment(\.managedObjectContext, viewContext)
                            }
                            .transition(.move(edge: .bottom))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(showFolders || viewingFolder != nil || showAlarms)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showFolders)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewingFolder?.objectID)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showAlarms)
                }
            }
            .coordinateSpace(name: "calendarContainer")
            .frame(maxHeight: .infinity)
            .background(Color.screenBackground)
            .ignoresSafeArea(.container, edges: .bottom)
            .sheet(item: $selectedEvent) { event in
                ItemInfoView(item: .event(event))
            }
            .sheet(item: $selectedReminder) { reminder in
                ItemInfoView(item: .reminder(reminder))
            }
            .sheet(item: $selectedHabit) { habit in
                ItemInfoView(item: .habit(habit, occurrenceDay: selectedHabitOccurrenceDay))
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showMonthYearPicker) {
                MonthYearPickerView(
                    selectedDate: $currentMonth,
                    isPresented: $showMonthYearPicker
                )
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: showFolders) { _, _ in
                syncFolderSheetCoordinatorPresentation()
            }
            .onChange(of: viewingFolder) { _, folder in
                FolderSheetCoordinator.shared.viewingFolderID = folder?.id
                syncFolderSheetCoordinatorPresentation()
            }
            .onChange(of: showAlarms) { _, isOpen in
                AlarmSheetCoordinator.shared.isPresented = isOpen
                if !isOpen {
                    AlarmSheetCoordinator.shared.consumeAddAlarmRequest()
                }
            }
            .onChange(of: selectedDayManager.selectedDay) { oldValue, newValue in
                if let newDay = newValue {
                    selectedDay = newDay
                    currentMonth = newDay
                    updateFetchPredicates()
                }
            }
            .onChange(of: currentMonth) { _, _ in
                updateFetchPredicates()
            }
            .onAppear {
                selectedDay = selectedDayManager.selectedDay ?? Date()
                currentMonth = selectedDay ?? Date()
                updateFetchPredicates()
                FolderStore.ensureInboxExists(context: viewContext)
                reloadFolders()
                reloadAlarms()
                restoreViewingFolderIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
                viewContext.processPendingChanges()
                updateFetchPredicates()
                reloadFolders()
                reloadAlarms()
            }
        }
    }
    
    private var monthlyCalendarView: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                // Month Header - Left-aligned, clickable
                HStack {
                    Button(action: {
                        showMonthYearPicker = true
                    }) {
                        Text(monthYearString)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color.primaryText)
                    }

                    Spacer()

                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            showFoldersBar.toggle()
                        }
                    } label: {
                        Image(systemName: "text.below.folder")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassCapsulePill(active: showFoldersBar)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Weekday Headers
                HStack(spacing: 0) {
                    let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)

                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                    ForEach(daysInMonth, id: \.self) { date in
                        DayCellView(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: calendar.isDate(date, equalTo: currentMonth, toGranularity: .month),
                            hasItems: hasItems(on: date),
                            hasOverdueItems: hasOverdueItems(on: date),
                            selectedDate: selectedDay,
                            onTap: {
                                Haptics.selection()
                                selectedDay = date
                                selectedDayManager.selectedDay = date
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .animation(nil, value: currentMonth)
            }
            .id(monthIdentity)
            .transition(
                .asymmetric(
                    insertion: .move(edge: monthSlideDirection > 0 ? .bottom : .top),
                    removal: .move(edge: monthSlideDirection > 0 ? .top : .bottom)
                )
            )
        }
        .clipped()
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let horizontalAmount = value.translation.width
                    let verticalAmount = value.translation.height

                    guard abs(verticalAmount) > abs(horizontalAmount),
                          abs(verticalAmount) > 25
                    else { return }

                    if verticalAmount < 0 {
                        changeMonth(1)
                    } else {
                        changeMonth(-1)
                    }
                }
        )
    }

    private var monthIdentity: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
    }
    
    private func changeMonth(_ direction: Int) {
        guard !isMonthChanging,
              let newMonth = calendar.date(byAdding: .month, value: direction, to: currentMonth)
        else { return }

        isMonthChanging = true
        monthSlideDirection = direction
        selectedDay = nil

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            currentMonth = newMonth
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isMonthChanging = false
        }
    }
    
    private var sheetItemsList: some View {
        let displayItems = filteredDisplayItems()

        return List {
            if displayItems.isEmpty {
                EmptyListSkeletonView(accessibilityLabel: sheetEmptyMessage)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                    Group {
                        if let event = item.event {
                            CalendarSheetItemRow(item: event, occurrenceDay: selectedDay ?? Date()) {
                                selectedEvent = event
                            }
                        } else if let reminder = item.reminder {
                            CalendarSheetItemRow(item: reminder, occurrenceDay: selectedDay ?? Date()) {
                                selectedReminder = reminder
                            }
                        } else if let habit = item.habit {
                            CalendarSheetItemRow(item: habit, occurrenceDay: selectedDay ?? Date()) {
                                selectedHabitOccurrenceDay = selectedDay ?? Date()
                                selectedHabit = habit
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(index < displayItems.count - 1 ? .visible : .hidden, edges: .bottom)
                    .listRowSeparatorTint(Color.gray.opacity(0.25))
                    .listRowBackground(Color.sheetSurface)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.bottom, BottomSheetMetrics.tabBarContentInset)
        // Prevent UICollectionView invalid updates when day/filter/delete changes row counts.
        .animation(nil, value: displayItems.map(\.id))
    }

    private func filteredDisplayItems() -> [(id: String, event: Event?, reminder: Reminder?, habit: Habit?)] {
        let allItems = getItems(for: selectedDay ?? Date())

        return allItems.compactMap { item -> (id: String, event: Event?, reminder: Reminder?, habit: Habit?)? in
            if let event = item.event {
                if !sheetFilter.showsEvents { return nil }
                if !sheetFilter.matchesFolder(event.folder?.id) { return nil }
                if showFlaggedOnly && !event.isFlagged { return nil }
                return (id: event.objectID.uriRepresentation().absoluteString, event: event, reminder: nil, habit: nil)
            }
            if let reminder = item.reminder {
                if !sheetFilter.showsReminders { return nil }
                if !sheetFilter.matchesFolder(reminder.folder?.id) { return nil }
                if showFlaggedOnly && !reminder.isFlagged { return nil }
                return (id: reminder.objectID.uriRepresentation().absoluteString, event: nil, reminder: reminder, habit: nil)
            }
            if let habit = item.habit {
                if !sheetFilter.showsHabits { return nil }
                if !sheetFilter.matchesFolder(habit.folder?.id) { return nil }
                if showFlaggedOnly { return nil }
                return (id: habit.objectID.uriRepresentation().absoluteString, event: nil, reminder: nil, habit: habit)
            }
            return nil
        }
    }

    private func reloadFolders() {
        folders = FolderStore.fetchAll(context: viewContext)
    }

    private func reloadAlarms() {
        guard NSEntityDescription.entity(forEntityName: "Alarm", in: viewContext) != nil else {
            alarms = []
            return
        }
        let request = NSFetchRequest<Alarm>(entityName: "Alarm")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Alarm.time, ascending: true)]
        alarms = (try? viewContext.fetch(request)) ?? []
    }

    private func syncFolderSheetCoordinatorPresentation() {
        let isOpen = showFolders || viewingFolder != nil
        FolderSheetCoordinator.shared.isPresented = isOpen
        if !isOpen {
            FolderSheetCoordinator.shared.consumeAddFolderRequest()
        }
    }

    private func restoreViewingFolderIfNeeded() {
        guard viewingFolder == nil,
              let folderID = FolderSheetCoordinator.shared.viewingFolderID else { return }

        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.predicate = NSPredicate(format: "id == %@", folderID as CVarArg)
        request.fetchLimit = 1
        if let folder = try? viewContext.fetch(request).first {
            viewingFolder = folder
            showFolders = false
        } else {
            FolderSheetCoordinator.shared.viewingFolderID = nil
        }
    }

    private var sheetEmptyMessage: String {
        let targetDate = selectedDay ?? Date()
        let dayPhrase = calendar.isDateInToday(targetDate) ? String(localized: "today") : String(localized: "this day")
        let subject = sheetFilter.emptyListSubject(flaggedOnly: showFlaggedOnly)

        if case .folder(let folderID) = sheetFilter {
            let folderName = folders.first(where: { $0.id == folderID }).map { FolderStore.displayName(for: $0) } ?? String(localized: "folder")
            return String(localized: "No \(subject) in \(folderName) for \(dayPhrase)")
        }

        return String(localized: "No \(subject) for \(dayPhrase)")
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth).localizedCapitalized
    }
    
    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstDay = calendar.dateInterval(of: .month, for: currentMonth)?.start else {
            return []
        }
        
        let firstDayWeekday = calendar.component(.weekday, from: firstDay)
        let daysToSubtract = (firstDayWeekday - calendar.firstWeekday + 7) % 7
        
        guard let startDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDay) else {
            return []
        }

        let daysInMonthCount = calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 0
        let totalCells = daysToSubtract + daysInMonthCount
        let weeksNeeded = (totalCells + 6) / 7
        let totalDays = weeksNeeded * 7
        
        var days: [Date] = []
        var currentDate = startDate
        
        for _ in 0..<totalDays {
            days.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        return days
    }
    
    private func hasItems(on date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        
        let hasEvents = events.contains { event in
            guard let eventDate = event.date else { return false }
            let option = Recurrence.option(from: event.repeatOption)
            return Recurrence.occurs(
                on: dayStart,
                baseDate: eventDate,
                option: option,
                excludedDates: event.excludedDatesStorage,
                calendar: calendar
            )
        }
        
        let hasReminders = reminders.contains { reminder in
            guard let reminderDate = reminder.date else { return false }
            let option = Recurrence.option(from: reminder.repeatOption)
            return Recurrence.occurs(
                on: dayStart,
                baseDate: reminderDate,
                option: option,
                excludedDates: reminder.excludedDatesStorage,
                calendar: calendar
            )
        }

        let hasHabits = habits.contains { habit in
            guard let habitDate = habit.date else { return false }
            let option = Recurrence.option(from: habit.repeatOption)
            return Recurrence.occurs(
                on: dayStart,
                baseDate: habitDate,
                option: option,
                excludedDates: habit.excludedDatesStorage,
                calendar: calendar
            )
        }
        
        return hasEvents || hasReminders || hasHabits
    }
    
    private func hasOverdueItems(on date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: Date())
        guard dayStart <= todayStart else { return false }
        
        // Check for overdue events on this day (non-repeating only — repeats are expected on past days)
        let hasOverdueEvents = events.contains { event in
            guard let eventDate = event.date else { return false }
            let option = Recurrence.option(from: event.repeatOption)
            guard option == .never else { return false }
            guard Recurrence.occurs(
                on: dayStart,
                baseDate: eventDate,
                option: option,
                excludedDates: event.excludedDatesStorage,
                calendar: calendar
            ) else {
                return false
            }
            guard !event.isAllDay else { return false }
            let eventDateTime = event.startTime ?? eventDate
            let itemStart = calendar.startOfDay(for: eventDateTime)
            return itemStart < todayStart
        }
        
        let hasOverdueReminders = reminders.contains { reminder in
            guard !reminder.isCompleted, let reminderDate = reminder.date else { return false }
            let option = Recurrence.option(from: reminder.repeatOption)
            guard option == .never else { return false }
            guard Recurrence.occurs(
                on: dayStart,
                baseDate: reminderDate,
                option: option,
                excludedDates: reminder.excludedDatesStorage,
                calendar: calendar
            ) else {
                return false
            }
            let reminderDateTime = reminder.time ?? reminderDate
            let itemStart = calendar.startOfDay(for: reminderDateTime)
            return itemStart < todayStart
        }
        
        return hasOverdueEvents || hasOverdueReminders
    }
    
    private func updateFetchPredicates() {
        let range = currentMonthRange
        let never = RepeatOption.never.rawValue
        
        // Month items, plus any repeating items (may fall on days in this month)
        let eventPredicate = NSPredicate(
            format: "(date >= %@ AND date < %@) OR (repeatOption != nil AND repeatOption != %@)",
            range.start as NSDate,
            range.end as NSDate,
            never
        )
        events.nsPredicate = eventPredicate
        
        let reminderPredicate = NSPredicate(
            format: "(date >= %@ AND date < %@) OR (repeatOption != nil AND repeatOption != %@)",
            range.start as NSDate,
            range.end as NSDate,
            never
        )
        reminders.nsPredicate = reminderPredicate

        let habitPredicate = NSPredicate(
            format: "(date >= %@ AND date < %@) OR (repeatOption != nil AND repeatOption != %@)",
            range.start as NSDate,
            range.end as NSDate,
            never
        )
        habits.nsPredicate = habitPredicate
    }
    
    private func getItems(for date: Date) -> [(date: Date, event: Event?, reminder: Reminder?, habit: Habit?)] {
        let dayStart = calendar.startOfDay(for: date)
        
        let dayEvents = events.filter { event in
            guard let eventDate = event.date else { return false }
            let option = Recurrence.option(from: event.repeatOption)
            return Recurrence.occurs(
                on: dayStart,
                baseDate: eventDate,
                option: option,
                excludedDates: event.excludedDatesStorage,
                calendar: calendar
            )
        }
        
        let dayReminders = reminders.filter { reminder in
            guard let reminderDate = reminder.date else { return false }
            let option = Recurrence.option(from: reminder.repeatOption)
            return Recurrence.occurs(
                on: dayStart,
                baseDate: reminderDate,
                option: option,
                excludedDates: reminder.excludedDatesStorage,
                calendar: calendar
            )
        }

        let dayHabits = habits.filter { habit in
            guard let habitDate = habit.date else { return false }
            let option = Recurrence.option(from: habit.repeatOption)
            return Recurrence.occurs(
                on: dayStart,
                baseDate: habitDate,
                option: option,
                excludedDates: habit.excludedDatesStorage,
                calendar: calendar
            )
        }
        
        // Sort events by time
        let sortedEvents = dayEvents.sorted { event1, event2 in
            let date1 = event1.startTime ?? event1.date ?? Date.distantFuture
            let date2 = event2.startTime ?? event2.date ?? Date.distantFuture
            return date1 < date2
        }
        
        // Sort reminders by time
        let sortedReminders = dayReminders.sorted { reminder1, reminder2 in
            let date1 = reminder1.time ?? reminder1.date ?? Date.distantFuture
            let date2 = reminder2.time ?? reminder2.date ?? Date.distantFuture
            return date1 < date2
        }

        let sortedHabits = dayHabits.sorted { habit1, habit2 in
            let date1 = habit1.time ?? habit1.date ?? Date.distantFuture
            let date2 = habit2.time ?? habit2.date ?? Date.distantFuture
            return date1 < date2
        }
        
        // Combine and sort all items
        var allItems: [(date: Date, event: Event?, reminder: Reminder?, habit: Habit?)] = []
        
        for event in sortedEvents {
            let date = event.startTime ?? event.date ?? Date.distantFuture
            allItems.append((date: date, event: event, reminder: nil, habit: nil))
        }
        
        for reminder in sortedReminders {
            let date = reminder.time ?? reminder.date ?? Date.distantFuture
            allItems.append((date: date, event: nil, reminder: reminder, habit: nil))
        }

        for habit in sortedHabits {
            let date = habit.time ?? habit.date ?? Date.distantFuture
            allItems.append((date: date, event: nil, reminder: nil, habit: habit))
        }
        
        // Sort by time only so completing a reminder does not reorder the list
        allItems.sort { a, b in
            a.date < b.date
        }
        
        return allItems
    }
}

struct DayCellView: View {
    let date: Date
    let isToday: Bool
    let isCurrentMonth: Bool
    let hasItems: Bool
    let hasOverdueItems: Bool
    let selectedDate: Date?
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    private var isSelected: Bool {
        guard let selectedDate = selectedDate else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }
    
    private var shouldHighlight: Bool {
        // Highlight if day is selected, OR if it's today and no day is selected
        return isSelected || (isToday && selectedDate == nil)
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 18, weight: shouldHighlight ? .bold : .regular))
                .foregroundColor(
                    shouldHighlight
                        ? (isToday ? Color.white : Color.screenBackground)
                        : (isToday ? Color.flagRed : (isCurrentMonth ? Color.primaryText : .gray))
                )
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(
                            shouldHighlight
                                ? (isToday ? Color.flagRed : Color.primaryText)
                                : Color.clear
                        )
                )
            
            // Red dot indicator for days with items
            if hasItems {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 5, height: 5)
            } else {
                // Invisible spacer to maintain consistent height
                Circle()
                    .fill(Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Reusable sheet for changing item date (used by Calendar and Reminders rows).
struct QuickChangeDateView: View {
    @Binding var selectedDate: Date
    var onDone: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
            }
            .background(Color.screenBackground)
            .navigationTitle("Change Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton(accessibilityLabelText: "Done") { onDone() }
                }
            }
        }
    }
}

struct TodayItemRow: View {
    let item: Any
    let onTap: () -> Void
    var occurrenceDay: Date = Calendar.current.startOfDay(for: Date())
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showChangeDateSheet = false
    @State private var tempNewDate = Date()
    @State private var showRepeatDeleteConfirmation = false
    
    private var isOverdue: Bool {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        if let event = item as? Event {
            guard !event.isAllDay else { return false }
            guard let eventDate = event.date else { return false }
            return calendar.startOfDay(for: eventDate) < todayStart
        } else if let reminder = item as? Reminder {
            guard !reminder.isCompleted else { return false }
            guard let reminderDate = reminder.date else { return false }
            return calendar.startOfDay(for: reminderDate) < todayStart
        }
        return false
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon or Circle
                if let event = item as? Event {
                    // Blue calendar icon for events
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color(red: 0.098, green: 0.698, blue: 1.0))
                } else if let reminder = item as? Reminder {
                    // Yellow circle for reminders (clickable)
                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color(red: 1.0, green: 0.761, blue: 0.098))
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                Haptics.light()
                                if !reminder.isCompleted {
                                    _ = reminder.completeOrRollForward()
                                } else {
                                    reminder.isCompleted = false
                                    reminder.completionDate = nil
                                    if let reminderId = reminder.id?.uuidString {
                                        NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
                                        NotificationManager.shared.scheduleNotification(for: reminder)
                                    }
                                }
                                PersistenceController.shared.save()
                                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                            }
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(getTitle())
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor((isOverdue && item is Event) ? Color(red: 1.0, green: 0.3, blue: 0.3) : Color.primaryText)
                    
                    if let notes = getNotes(), !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Time badge at the end
                if let event = item as? Event, !event.isAllDay {
                    if let startTime = event.startTime {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatTime(startTime))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(isOverdue ? Color(red: 1.0, green: 0.3, blue: 0.3) : Color.primaryText)
                            
                            if let endTime = event.endTime {
                                Text(formatTime(endTime))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(isOverdue ? Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.8) : Color.primaryText.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                    }
                } else if let reminder = item as? Reminder, let time = reminder.time {
                    Text(formatTime(time))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button("Delete", role: .destructive) {
                requestDelete()
            }
        }
        .repeatDeleteConfirmation(
            isPresented: $showRepeatDeleteConfirmation,
            onDeleteThis: { performDelete(scope: .thisOccurrence) },
            onDeleteAll: { performDelete(scope: .allOccurrences) }
        )
        .sheet(isPresented: $showChangeDateSheet) {
            QuickChangeDateView(selectedDate: $tempNewDate, onDone: {
                applyNewDateToItem()
                showChangeDateSheet = false
            }, onCancel: {
                showChangeDateSheet = false
            })
        }
    }
    
    private func currentDateFromItem() -> Date {
        if let event = item as? Event {
            return event.date ?? Date()
        }
        if let reminder = item as? Reminder {
            return reminder.date ?? Date()
        }
        return Date()
    }
    
    private func requestDelete() {
        if let event = item as? Event, ItemActions.isRepeating(repeatOption: event.repeatOption) {
            showRepeatDeleteConfirmation = true
            return
        }
        if let reminder = item as? Reminder, ItemActions.isRepeating(repeatOption: reminder.repeatOption) {
            showRepeatDeleteConfirmation = true
            return
        }
        performDelete(scope: .allOccurrences)
    }
    
    private func performDelete(scope: RepeatDeleteScope) {
        if let event = item as? Event {
            ItemActions.deleteEvent(
                event,
                scope: scope,
                occurrenceDay: occurrenceDay,
                context: viewContext
            )
        } else if let reminder = item as? Reminder {
            ItemActions.deleteReminder(
                reminder,
                scope: scope,
                occurrenceDay: occurrenceDay,
                context: viewContext
            )
        }
    }
    
    private func applyNewDateToItem() {
        let calendar = Calendar.current
        let newDate = calendar.startOfDay(for: tempNewDate)
        
        if let event = item as? Event {
            event.date = newDate
            if !event.isAllDay {
                if let startTime = event.startTime {
                    event.startTime = combine(date: newDate, time: startTime)
                }
                if let endTime = event.endTime {
                    event.endTime = combine(date: newDate, time: endTime)
                }
            }
            let eventId = event.id?.uuidString ?? ""
            NotificationManager.shared.cancelAllNotifications(for: eventId, itemType: "event")
            NotificationManager.shared.scheduleNotification(for: event)
        } else if let reminder = item as? Reminder {
            reminder.date = newDate
            if let time = reminder.time {
                reminder.time = combine(date: newDate, time: time)
            }
            let reminderId = reminder.id?.uuidString ?? ""
            NotificationManager.shared.cancelAllNotifications(for: reminderId, itemType: "reminder")
            NotificationManager.shared.scheduleNotification(for: reminder)
        }
        do { try viewContext.save() } catch { }
        PersistenceController.shared.save()
    }
    
    private func combine(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dc = calendar.dateComponents([.year, .month, .day], from: date)
        let tc = calendar.dateComponents([.hour, .minute, .second], from: time)
        var combined = DateComponents()
        combined.year = dc.year; combined.month = dc.month; combined.day = dc.day
        combined.hour = tc.hour; combined.minute = tc.minute; combined.second = tc.second ?? 0
        return calendar.date(from: combined) ?? date
    }
    
    private func getTitle() -> String {
        if let event = item as? Event {
            return event.title ?? "Untitled Event"
        } else if let reminder = item as? Reminder {
            return reminder.title ?? "Untitled Reminder"
        }
        return "Unknown"
    }
    
    private func formatTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }
    
    private func getNotes() -> String? {
        if let event = item as? Event {
            return event.notes
        } else if let reminder = item as? Reminder {
            return reminder.notes
        }
        return nil
    }
}

struct MonthYearPickerView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool

    @State private var selectedMonth: Int
    @State private var selectedYear: Int

    private let months = ["January", "February", "March", "April", "May", "June",
                         "July", "August", "September", "October", "November", "December"]

    private let years: [Int]

    init(selectedDate: Binding<Date>, isPresented: Binding<Bool>) {
        _selectedDate = selectedDate
        _isPresented = isPresented

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: selectedDate.wrappedValue)
        let currentMonth = calendar.component(.month, from: selectedDate.wrappedValue)

        _selectedMonth = State(initialValue: currentMonth - 1)
        _selectedYear = State(initialValue: currentYear)

        let currentCalendarYear = calendar.component(.year, from: Date())
        years = Array((currentCalendarYear - 20)...(currentCalendarYear + 50))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("", selection: $selectedMonth) {
                        ForEach(0..<12, id: \.self) { index in
                            Text(months[index])
                                .tag(index)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 2)

                    Picker("", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            Text("\(year)")
                                .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .background(Color.screenBackground)
            .navigationTitle("Select Month & Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton(accessibilityLabelText: "Done") {
                        applySelection()
                    }
                }
            }
        }
    }

    private func applySelection() {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        components.year = selectedYear
        components.month = selectedMonth + 1

        if let newDate = calendar.date(from: components) {
            selectedDate = newDate
        }

        isPresented = false
    }
}

#Preview {
    CalendarView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

