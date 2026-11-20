//
//  AppleCalendarEventRow.swift
//  One
//

import SwiftUI
import EventKit

/// Row for an Apple Calendar event. Editable calendars open the event editor and can be
/// swiped to delete; holidays, birthdays, and subscribed calendars are display-only.
struct AppleCalendarEventRow: View {
    let event: AppleCalendarEvent
    /// Upcoming list rows get their insets from the List; Calendar sheet rows pad themselves.
    var groupedStyle: Bool = false

    @State private var presentedEvent: PresentedAppleEvent?
    @State private var showRepeatDeleteConfirmation = false

    var body: some View {
        if event.isEditable {
            Button {
                if let ekEvent = AppleCalendarStore.shared.ekEvent(for: event) {
                    presentedEvent = PresentedAppleEvent(event: ekEvent)
                }
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: !event.isRecurring) {
                // Destructive role eagerly removes the row; repeating deletes need a confirmation first.
                if event.isRecurring {
                    SwipeDeleteButton(isDestructive: false) { requestDelete() }
                } else {
                    SwipeDeleteButton { requestDelete() }
                }
            }
            .contextMenu {
                Button("Delete", role: .destructive) { requestDelete() }
            }
            .repeatDeleteConfirmation(
                isPresented: $showRepeatDeleteConfirmation,
                onDeleteThis: { delete(allOccurrences: false) },
                onDeleteAll: { delete(allOccurrences: true) }
            )
            .sheet(item: $presentedEvent) { presented in
                AppleEventInfoView(event: presented.event)
            }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(Color.importedEventBlue)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body)
                    .fontWeight(groupedStyle ? .medium : .semibold)
                    .foregroundColor(Color.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(event.color)
                        .frame(width: 6, height: 6)
                    Text(event.calendarTitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(event.timeText)
                .font(.caption)
                .foregroundColor(Color.primaryText.opacity(0.9))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, groupedStyle ? 0 : 16)
        .padding(.vertical, groupedStyle ? 12 : 14)
        .contentShape(Rectangle())
    }

    private func requestDelete() {
        if event.isRecurring {
            showRepeatDeleteConfirmation = true
        } else {
            delete(allOccurrences: false)
        }
    }

    private func delete(allOccurrences: Bool) {
        let store = AppleCalendarStore.shared
        guard let ekEvent = store.ekEvent(for: event) else { return }
        DispatchQueue.main.async {
            store.delete(ekEvent, allOccurrences: allOccurrences)
        }
    }
}

private struct PresentedAppleEvent: Identifiable {
    let id = UUID()
    let event: EKEvent
}
