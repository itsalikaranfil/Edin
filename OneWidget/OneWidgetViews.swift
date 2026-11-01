import WidgetKit
import SwiftUI
import UIKit
import AppIntents

// MARK: - Design tokens

private enum WD {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let primaryText = dynamic(
        light: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
        dark: .white
    )
    static let primaryTextMuted = dynamic(
        light: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 0.7),
        dark: UIColor.white.withAlphaComponent(0.7)
    )
    static let primaryTextSoft = dynamic(
        light: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 0.85),
        dark: UIColor.white.withAlphaComponent(0.85)
    )
    static let reminderOrange = Color(red: 1, green: 0.584, blue: 0)
    static let habitRed = Color(red: 255 / 255, green: 25 / 255, blue: 25 / 255)
    static let secondary = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let salmon = Color(red: 1, green: 0.396, blue: 0.373)
}

private extension View {
    func widgetAppAppearance() -> some View {
        preferredColorScheme(AppAppearanceStore.load().preferredColorScheme)
    }
}

extension WidgetSnapshot {
    /// Returns Tomorrow first when available, then future-day sections.
    func resolvedSectionsAfterToday() -> [WidgetDatedSection] {
        var sections: [WidgetDatedSection] = []
        if !tomorrowRows.isEmpty {
            sections.append(WidgetDatedSection(title: "Tomorrow", rows: tomorrowRows))
        }
        if let s = afterTodaySections, !s.isEmpty {
            // Avoid duplicate Tomorrow blocks from older snapshots that may already include it.
            sections.append(contentsOf: s.filter { section in
                !(section.title == "Tomorrow" && !tomorrowRows.isEmpty)
            })
        }
        return sections
    }
}

// MARK: - Shared sub-views

private struct WidgetPlusButton: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var body: some View {
        Link(destination: URL(string: "oneapp://new")!) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(WD.primaryText)
                .frame(width: 30, height: 30)
                .widgetGlassCircle()
                .contentShape(Circle())
        }
        .widgetAccentable(widgetRenderingMode == .accented)
    }
}

private struct RowView: View {
    let row: WidgetRow
    var compact: Bool = false

    private var isCompleting: Bool {
        row.isCompleting == true || WidgetPendingCompletions.isCompleting(rowID: row.id)
    }
    private var iconSize: CGFloat { compact ? 17 : 19 }
    private var iconFontSize: CGFloat { compact ? 17 : 19 }

    var body: some View {
        HStack(spacing: 8) {
            switch row.kind {
            case .reminder:
                if isCompleting {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: iconFontSize, weight: .regular))
                        .foregroundColor(WD.reminderOrange)
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(1.1)
                } else {
                    Button(
                        intent: CompleteWidgetItemIntent(
                            kind: WidgetRowKind.reminder.rawValue,
                            itemID: row.entityIDForCompletion,
                            rowID: row.id,
                            occurrenceDayKey: nil
                        )
                    ) {
                        Image(systemName: "circle")
                            .font(.system(size: iconFontSize, weight: .regular))
                            .foregroundColor(WD.reminderOrange)
                            .frame(width: iconSize, height: iconSize)
                            .contentShape(Rectangle().inset(by: -6))
                    }
                    .buttonStyle(.plain)
                }
            case .habit:
                if isCompleting {
                    Image(systemName: "checkmark.circle.dotted")
                        .font(.system(size: iconFontSize, weight: .regular))
                        .foregroundColor(WD.habitRed)
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(1.1)
                } else {
                    Button(
                        intent: CompleteWidgetItemIntent(
                            kind: WidgetRowKind.habit.rawValue,
                            itemID: row.entityIDForCompletion,
                            rowID: row.id,
                            occurrenceDayKey: row.occurrenceDayKey
                        )
                    ) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: iconFontSize, weight: .regular))
                            .foregroundColor(WD.habitRed)
                            .frame(width: iconSize, height: iconSize)
                            .contentShape(Rectangle().inset(by: -6))
                    }
                    .buttonStyle(.plain)
                }
            case .event:
                Image(systemName: "calendar")
                    .font(.system(size: compact ? 15 : 17, weight: .regular))
                    .foregroundColor(Color(red: 0.098, green: 0.698, blue: 1.0))
                    .frame(width: iconSize, height: iconSize)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: compact ? 14 : 15, weight: .medium))
                    .foregroundColor(isCompleting ? WD.secondary : WD.primaryText)
                    .strikethrough(isCompleting, color: WD.secondary)
                    .lineLimit(1)
                if let sub = row.subtitle {
                    Text(sub)
                        .font(.system(size: compact ? 12 : 13))
                        .foregroundColor(WD.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, compact ? 4 : 6)
        .opacity(isCompleting ? 0.85 : 1)
    }
}

extension WidgetSnapshot {
    /// Empty copy for the Today section only.
    var todayEmptyMessage: String {
        (todayHadCompletedItems == true)
            ? "Tasks completed for today"
            : "No tasks today"
    }
}

private struct ItemList: View {
    let rows: [WidgetRow]
    let maxVisible: Int
    var compact: Bool = false
    /// Empty-state copy; Today uses "No tasks today" / "Tasks completed for today".
    var emptyMessage: String = "No items"

    var body: some View {
        if rows.isEmpty {
            Text(LocalizedStringKey(emptyMessage))
                .font(.system(size: 14))
                .foregroundColor(WD.secondary.opacity(0.6))
                .padding(.horizontal, 3)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let visible = Array(rows.prefix(maxVisible))
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, row in
                    RowView(row: row, compact: compact)
                }
                if rows.count > maxVisible {
                    Text("+ \(rows.count - maxVisible) more")
                        .font(.system(size: 12))
                        .foregroundColor(WD.secondary)
                        .padding(.bottom, 5)
                }
            }
        }
    }
}

// MARK: - Small: Date widget

struct OneDateWidget: Widget {
    let kind = "OneDateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OneWidgetProvider()) { entry in
            DateWidgetView(entry: entry)
        }
        .configurationDisplayName("Date")
        .description("Today's date at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

private struct DateWidgetView: View {
    let entry: OneWidgetEntry

    private var dayName: String   { formatted("EEE").uppercased() }
    private var dayNumber: String { formatted("d") }
    private var monthName: String { formatted("MMM").localizedCapitalized }

    private func formatted(_ format: String) -> String {
        let f = DateFormatter(); f.dateFormat = format
        return f.string(from: entry.date)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(dayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(WD.salmon)
                .tracking(1.5)
            Text(dayNumber)
                .font(.system(size: 96, weight: .bold))
                .foregroundColor(WD.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.vertical, -10)
            Text(monthName)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(WD.primaryTextMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .containerBackground(.clear, for: .widget)
        .widgetAppAppearance()
    }
}

// MARK: - Small: Today list widget (with + button)

struct OneTodaySmallWidget: Widget {
    let kind = "OneTodaySmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OneWidgetProvider()) { entry in
            SmallTodayListWidgetView(entry: entry)
        }
        .configurationDisplayName("Today List")
        .description("Today's tasks and events with a quick-add button.")
        .supportedFamilies([.systemSmall])
    }
}

private struct SmallTodayListWidgetView: View {
    let entry: OneWidgetEntry

    private var shortDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM"
        return f.string(from: entry.date).localizedCapitalized
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(WD.primaryText)
                    Spacer()
                    Text(shortDate)
                        .font(.system(size: 11))
                        .foregroundColor(WD.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                ItemList(
                    rows: entry.snapshot?.todayRows ?? [],
                    maxVisible: 4,
                    compact: true,
                    emptyMessage: entry.snapshot?.todayEmptyMessage ?? "No tasks today"
                )

                Spacer(minLength: 0)
            }
//            .padding(.horizontal, -10)

            WidgetPlusButton()
//            .padding(.horizontal, -10)
        }
        .containerBackground(.clear, for: .widget)
        .widgetAppAppearance()
    }
}

// MARK: - Medium: Date column + Today / Tomorrow (design mockup)

private struct MediumAgendaWidgetView: View {
    let entry: OneWidgetEntry

    private var dayName: String { formatted("EEEE").uppercased() }
    private var dayNumber: String { formatted("d") }
    private var monthName: String { formatted("MMMM").localizedCapitalized }

    private func formatted(_ format: String) -> String {
        let f = DateFormatter()
        f.dateFormat = format
        return f.string(from: entry.date)
    }

    private func maxVisibleAfterTodaySections(_ sectionCount: Int) -> Int {
        if sectionCount <= 1 { return 2 }
        return 1
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geo in
                let hPad: CGFloat = 4
                let vPad: CGFloat = 6
                let innerW = geo.size.width - hPad * 2
                let leftW = innerW * 0.34
                let midGap: CGFloat = 10
                let rightW = innerW - leftW - midGap
                let afterToday = Array((entry.snapshot?.resolvedSectionsAfterToday() ?? []).prefix(2))
                let afterTodayMaxVisible = maxVisibleAfterTodaySections(afterToday.count)

                HStack(alignment: .top, spacing: midGap) {
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Text(dayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(WD.salmon)
                            .tracking(1.2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text(dayNumber)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(WD.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text(monthName)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(WD.primaryTextSoft)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                    .frame(width: leftW)
                    .frame(maxHeight: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        AgendaSectionBlock(
                            title: "Today",
                            rows: entry.snapshot?.todayRows ?? [],
                            maxVisible: 4,
                            emptyMessage: entry.snapshot?.todayEmptyMessage ?? "No tasks today"
                        )
                        if !afterToday.isEmpty {
                            ForEach(Array(afterToday.enumerated()), id: \.offset) { _, section in
                                AgendaSectionBlock(
                                    title: section.title,
                                    rows: section.rows,
                                    maxVisible: afterTodayMaxVisible
                                )
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: rightW, alignment: .leading)
                    .padding(.top, -5)
                    .padding(.trailing, 32)
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }

            WidgetPlusButton()
//            .padding(0)
        }
        .containerBackground(.clear, for: .widget)
        .widgetAppAppearance()
    }
}

private struct AgendaSectionBlock: View {
    let title: String
    let rows: [WidgetRow]
    let maxVisible: Int
    var compact: Bool = true
    var emptyMessage: String = "No items"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: compact ? 13 : 15, weight: .medium))
                .foregroundColor(WD.secondary)
            ItemList(rows: rows, maxVisible: maxVisible, compact: compact, emptyMessage: emptyMessage)
        }
    }
}

// MARK: - Large: Today list

private struct TodayListWidgetLayout: View {
    let entry: OneWidgetEntry

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: entry.date).localizedCapitalized
    }

    private var sectionsAfterToday: [WidgetDatedSection] {
        entry.snapshot?.resolvedSectionsAfterToday() ?? []
    }

    private func maxVisibleLargeAfterToday(_ sectionCount: Int) -> Int {
        switch sectionCount {
        case 0: return 0
        case 1: return 8
        case 2: return 4
        default: return 3
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geo in
                let hPad: CGFloat = 4
                let vPad: CGFloat = 6

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(WD.primaryText)
                        Spacer()
                        Text(dateString)
                            .font(.system(size: 13))
                            .foregroundColor(WD.secondary)
                    }

                    ItemList(
                        rows: entry.snapshot?.todayRows ?? [],
                        maxVisible: 10,
                        emptyMessage: entry.snapshot?.todayEmptyMessage ?? "No tasks today"
                    )
                        .padding(.trailing, 32)

                    if !sectionsAfterToday.isEmpty {
                        ForEach(Array(sectionsAfterToday.enumerated()), id: \.offset) { _, section in
                            AgendaSectionBlock(
                                title: section.title,
                                rows: section.rows,
                                maxVisible: maxVisibleLargeAfterToday(sectionsAfterToday.count),
                                compact: false
                            )
                            .padding(.trailing, 32)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .padding(.bottom, 4)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }

            WidgetPlusButton()
        }
        .containerBackground(.clear, for: .widget)
        .widgetAppAppearance()
    }
}

struct OneTodayWidget: Widget {
    let kind = "OneTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OneWidgetProvider()) { entry in
            MediumAgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Today's date with today and upcoming items at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Large: Overview

struct OneOverviewWidget: Widget {
    let kind = "OneOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OneWidgetProvider()) { entry in
            TodayListWidgetLayout(entry: entry)
        }
        .configurationDisplayName("Overview")
        .description("Today and upcoming events and reminders in a large layout.")
        .supportedFamilies([.systemLarge])
    }
}
