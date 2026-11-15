//
//  AppleCalendarEventRow.swift
//  One
//

import SwiftUI
import EventKit
import EventKitUI

/// Read-only row for an Apple Calendar event; tapping opens the system event details.
struct AppleCalendarEventRow: View {
    let event: AppleCalendarEvent
    /// Upcoming list rows get their insets from the List; Calendar sheet rows pad themselves.
    var groupedStyle: Bool = false

    @State private var presentedEvent: PresentedAppleEvent?

    var body: some View {
        Button {
            if let ekEvent = AppleCalendarStore.shared.event(withIdentifier: event.eventIdentifier) {
                presentedEvent = PresentedAppleEvent(event: ekEvent)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(event.color)

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
        .buttonStyle(.plain)
        .sheet(item: $presentedEvent) { presented in
            AppleCalendarEventDetailView(event: presented.event)
                .ignoresSafeArea()
        }
    }
}

private struct PresentedAppleEvent: Identifiable {
    let id = UUID()
    let event: EKEvent
}

/// Wraps `EKEventViewController` so events open with the same details screen as Apple Calendar.
private struct AppleCalendarEventDetailView: UIViewControllerRepresentable {
    let event: EKEvent
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = true
        controller.allowsCalendarPreview = true
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        let dismiss: () -> Void

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
        }

        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            dismiss()
        }
    }
}
