//
//  ContentView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import UIKit
import CoreData

extension Notification.Name {
    static let dataDidChange = Notification.Name("dataDidChange")
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var selectedDayManager = SelectedDayManager.shared
    @StateObject private var folderSheetCoordinator = FolderSheetCoordinator.shared
    @StateObject private var alarmSheetCoordinator = AlarmSheetCoordinator.shared
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
    @State private var selectedTab = 0
    @State private var newItemPresentation: NewItemPresentation?
    @State private var presentTypeMenu = false
    @State private var showSubscription = false
    @State private var showNewAlarm = false
    @State private var showNewHabit = false
    @State private var newItemInitialDate: Date = Date()
    @State private var newItemInitialFolderID: UUID?
    
    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRaw) ?? .system
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                // Re-tap Today while already on Calendar (off today) → jump to today.
                // Switching back from another tab keeps the day you left on.
                if newValue == 0, selectedTab == 0, !selectedDayManager.isViewingToday {
                    selectedDayManager.jumpToToday()
                }
                selectedTab = newValue
            }
        )
    }

    /// Tab bar ignores Label foregroundStyle; use an always-original blue glyph instead.
    private var todayTabBackIcon: Image {
        let config = UIImage.SymbolConfiguration(scale: .large)
        let uiImage = UIImage(systemName: "arrow.backward", withConfiguration: config)?
            .withTintColor(UIColor(Color.premiumBlue), renderingMode: .alwaysOriginal)
        return Image(uiImage: uiImage ?? UIImage())
    }

    private var showsTodayTab: Bool {
        selectedTab == 0 && !selectedDayManager.isViewingToday
    }

    private var plusTabRole: TabRole {
        if #available(iOS 27.0, *) {
            return .prominent
        }
        return .search
    }
    
    var body: some View {
        TabView(selection: tabSelection) {
            Tab(value: 0) {
                CalendarView()
                    .ignoresSafeArea(.container, edges: .bottom)
                    // No tab-level blue tint — it paints swipe Delete blue.
            } label: {
                if showsTodayTab {
                    Label {
                        Text("Today")
                    } icon: {
                        todayTabBackIcon
                    }
                } else {
                    Label("Calendar", systemImage: "calendar")
                }
            }
            Tab("Upcoming", systemImage: "list.bullet", value: 1) {
                RemindersView()
            }
            Tab("Settings", systemImage: "gearshape", value: 2) {
                SettingsView()
                    .tint(.blue)
            }
            // Trailing capsule, separate from the main tabs. Prominent on iOS 27; search role is the iOS 26 split.
            Tab(value: 3, role: plusTabRole) {
                Color.clear
                    .accessibilityHidden(true)
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(appAppearance.preferredColorScheme)
        // Selected tab highlight (forms that need neutral accents set .tint(.secondary) locally).
        .tint(Color.premiumBlue)
        .overlay(alignment: .bottomTrailing) {
            // Invisible UIMenu anchor over the plus control — same system liquid glass menu as filter.
            SystemMenuAnchor(
                present: $presentTypeMenu,
                canAddItem: ItemLimitManager.shared.canAddItem(context: viewContext),
                onSelect: { choice in
                    presentPlusChoice(choice)
                },
                onNeedSubscription: {
                    showSubscription = true
                }
            )
            .frame(width: 56, height: 56)
            .padding(.trailing, 10)
            .padding(.bottom, 2)
            .allowsHitTesting(
                (!folderSheetCoordinator.isPresented || folderSheetCoordinator.viewingFolderID != nil)
                    && !alarmSheetCoordinator.isPresented
            )
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 3 {
                selectedTab = oldValue
                if alarmSheetCoordinator.isPresented {
                    Haptics.selection()
                    alarmSheetCoordinator.triggerAddAlarm()
                } else if folderSheetCoordinator.viewingFolderID != nil {
                    // Inside a folder → add item to that folder.
                    prepareNewItemContext()
                    checkLimitAndPresentTypeMenu()
                } else if folderSheetCoordinator.isPresented {
                    Haptics.selection()
                    folderSheetCoordinator.triggerAddFolder()
                } else {
                    // Fallback when the plus tab is activated without hitting the menu anchor.
                    prepareNewItemContext()
                    checkLimitAndPresentTypeMenu()
                }
            }
        }
        .sheet(item: $newItemPresentation) { presentation in
            NewItemView(
                initialDate: presentation.date,
                initialFolderID: presentation.folderID,
                initialItemType: presentation.type
            )
            .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showNewAlarm) {
            NewAlarmView(onSaved: {})
                .environment(\.managedObjectContext, viewContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewHabit) {
            NewHabitView(
                initialDate: newItemInitialDate,
                initialFolderID: newItemInitialFolderID
            )
            .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionView()
        }
        .onOpenURL { url in
            if url.scheme == "oneapp", url.host == "new" {
                prepareNewItemContext(useToday: true)
                checkLimitAndPresentTypeMenu()
            }
        }
        .onAppear {
            FolderStore.ensureInboxExists(context: viewContext)
            WidgetPendingCompletionDrainer.drain()
            // Request notification permission on first launch
            Task {
                await NotificationManager.shared.requestAuthorization()
                // Reschedule all notifications for existing items
                await MainActor.run {
                    NotificationManager.shared.rescheduleAllNotifications(context: viewContext)
                    // Keep widgets in sync even if previous completion flows missed an export.
                    WidgetSnapshotExporter.shared.scheduleExport()
                }
            }
        }
    }
    
    private func prepareNewItemContext(useToday: Bool = false) {
        if useToday {
            newItemInitialDate = Date()
        } else {
            newItemInitialDate = selectedTab == 1 ? Date() : (selectedDayManager.selectedDay ?? Date())
        }
        newItemInitialFolderID = folderSheetCoordinator.viewingFolderID
    }
    
    private func presentPlusChoice(_ choice: PlusMenuChoice) {
        switch choice {
        case .event:
            presentNewItem(type: .event)
        case .habit:
            prepareNewItemContext()
            showNewHabit = true
        case .reminder:
            presentNewItem(type: .reminder)
        case .alarm:
            showNewAlarm = true
        }
    }

    private func presentNewItem(type: ItemType) {
        prepareNewItemContext()
        newItemPresentation = NewItemPresentation(
            type: type,
            date: newItemInitialDate,
            folderID: newItemInitialFolderID
        )
    }
    
    private func checkLimitAndPresentTypeMenu() {
        if ItemLimitManager.shared.canAddItem(context: viewContext) {
            presentTypeMenu = true
        } else {
            showSubscription = true
        }
    }
}

// MARK: - New Item Presentation

private struct NewItemPresentation: Identifiable {
    let id = UUID()
    let type: ItemType
    let date: Date
    let folderID: UUID?
}

// MARK: - System Menu Anchor (matches filter Menu animation)

private struct SystemMenuAnchor: UIViewRepresentable {
    @Binding var present: Bool
    var canAddItem: Bool
    var onSelect: (PlusMenuChoice) -> Void
    var onNeedSubscription: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onNeedSubscription: onNeedSubscription)
    }
    
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .clear
        button.accessibilityLabel = "Add"
        context.coordinator.attach(to: button)
        return button
    }
    
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onNeedSubscription = onNeedSubscription
        context.coordinator.canAddItem = canAddItem
        context.coordinator.refreshMenu(on: button)
        
        if present {
            DispatchQueue.main.async {
                if canAddItem {
                    button.performPrimaryAction()
                } else {
                    onNeedSubscription()
                }
                present = false
            }
        }
    }
    
    final class Coordinator {
        var onSelect: (PlusMenuChoice) -> Void
        var onNeedSubscription: () -> Void
        var canAddItem = true
        private var subscriptionAction: UIAction?
        
        init(onSelect: @escaping (PlusMenuChoice) -> Void, onNeedSubscription: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onNeedSubscription = onNeedSubscription
        }
        
        func attach(to button: UIButton) {
            let action = UIAction { [weak self] _ in
                guard let self, !self.canAddItem else { return }
                self.onNeedSubscription()
            }
            subscriptionAction = action
            button.addAction(action, for: .touchUpInside)
            refreshMenu(on: button)
        }
        
        func refreshMenu(on button: UIButton) {
            if canAddItem {
                button.showsMenuAsPrimaryAction = true
                button.menu = makeMenu()
            } else {
                button.showsMenuAsPrimaryAction = false
                button.menu = nil
            }
        }
        
        func makeMenu() -> UIMenu {
            let eventColor = UIColor(Color.eventBlue)
            let habitColor = UIColor(Color.flagRed)
            let todoColor = UIColor(Color.reminderOrange)
            let alarmColor = UIColor(Color.alarmOrange)
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            let eventImage = UIImage(systemName: "calendar", withConfiguration: symbolConfig)?
                .withTintColor(eventColor, renderingMode: .alwaysOriginal)
            let habitImage = UIImage(systemName: "circle.dotted", withConfiguration: symbolConfig)?
                .withTintColor(habitColor, renderingMode: .alwaysOriginal)
            let todoImage = UIImage(systemName: "circle", withConfiguration: symbolConfig)?
                .withTintColor(todoColor, renderingMode: .alwaysOriginal)
            let alarmImage = UIImage(systemName: "alarm", withConfiguration: symbolConfig)?
                .withTintColor(alarmColor, renderingMode: .alwaysOriginal)
            
            let events = UIAction(title: String(localized: "Event"), image: eventImage) { [weak self] _ in
                Haptics.selection()
                self?.onSelect(.event)
            }
            let habits = UIAction(title: String(localized: "Habit"), image: habitImage) { [weak self] _ in
                Haptics.selection()
                self?.onSelect(.habit)
            }
            let todo = UIAction(title: String(localized: "Reminder"), image: todoImage) { [weak self] _ in
                Haptics.selection()
                self?.onSelect(.reminder)
            }
            let alarm = UIAction(title: String(localized: "Alarm"), image: alarmImage) { [weak self] _ in
                Haptics.selection()
                self?.onSelect(.alarm)
            }
            let menu = UIMenu(children: [events, todo, habits, alarm])
            menu.preferredElementSize = .large
            return menu
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
