//
//  CalendarEventsSettingsView.swift
//  One
//

import SwiftUI
import EventKit
import UIKit

struct CalendarEventsSettingsView: View {
    @ObservedObject private var store = AppleCalendarStore.shared
    @AppStorage(AccentSetting.checkmark.rawValue) private var checkmarkRaw = AccentSetting.checkmark.defaultChoice.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var checkmarkColor: Color { AccentChoice.color(for: checkmarkRaw) }

    private var showEvents: Binding<Bool> {
        Binding(
            get: { store.isActive },
            set: { newValue in
                Haptics.light()
                Task { await store.setEnabled(newValue) }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                introCard

                toggleCard

                if store.isDenied {
                    deniedCard
                }

                if store.isActive {
                    ForEach(store.calendarGroups) { group in
                        section(group.title) {
                            calendarsCard(group.calendars)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.screenBackground.ignoresSafeArea())
        .navigationTitle("Calendar Events")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.25), value: store.isActive)
        .animation(.snappy(duration: 0.25), value: store.hiddenCalendarIDs)
        .onAppear { store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }

    // MARK: Cards

    private var introCard: some View {
        VStack(spacing: 14) {
            CalendarEventsArtwork()

            Text("Events from your personal and shared calendars can be shown alongside your to-dos in the Today and Upcoming lists.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .appearanceCard()
    }

    private var toggleCard: some View {
        Toggle(isOn: showEvents) {
            Text("Show Calendar Events")
                .font(.body)
                .foregroundColor(Color.primaryText)
        }
        .tint(.green)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appearanceCard()
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar access is turned off. Allow Full Access for Edin in Settings to show your events.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appearanceCard()
    }

    private func calendarsCard(_ calendars: [EKCalendar]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                if index > 0 {
                    Divider().padding(.leading, 44)
                }
                CalendarVisibilityRow(
                    title: calendar.title,
                    color: Color(cgColor: calendar.cgColor),
                    isOn: store.isVisible(calendar),
                    checkmarkColor: checkmarkColor
                ) {
                    Haptics.light()
                    store.setVisible(!store.isVisible(calendar), for: calendar)
                }
            }
        }
        .appearanceCard()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.6)
                .foregroundColor(.gray)
                .padding(.leading, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalendarVisibilityRow: View {
    let title: String
    let color: Color
    let isOn: Bool
    let checkmarkColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .frame(width: 16)

                Text(title)
                    .font(.body)
                    .foregroundColor(Color.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.35), lineWidth: 1.5)
                        .opacity(isOn ? 0 : 1)
                    Circle()
                        .fill(checkmarkColor)
                        .opacity(isOn ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(isOn ? 1 : 0)
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Calendar page icon in the spirit of the system Calendar app, showing today's date.
private struct CalendarEventsArtwork: View {
    private let today = Date()

    var body: some View {
        VStack(spacing: 0) {
            Text(today.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(Color.flagRed)

            Text("\(Calendar.current.component(.day, from: today))")
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}
