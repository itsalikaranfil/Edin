//
//  AppearanceSettingsView.swift
//  One
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AccentSetting.tabHighlight.rawValue) private var tabHighlightRaw = AccentSetting.tabHighlight.defaultChoice.rawValue
    @AppStorage(AccentSetting.checkmark.rawValue) private var checkmarkRaw = AccentSetting.checkmark.defaultChoice.rawValue
    @AppStorage(AccentSetting.todayCircle.rawValue) private var todayCircleRaw = AccentSetting.todayCircle.defaultChoice.rawValue
    @AppStorage(AppTextSize.modeKey) private var textSizeModeRaw = AppTextSize.Mode.automatic.rawValue
    @AppStorage(AppTextSize.customIndexKey) private var textSizeIndex = AppTextSize.defaultIndex

    private var textSizeMode: AppTextSize.Mode {
        AppTextSize.Mode(rawValue: textSizeModeRaw) ?? .automatic
    }

    private var tabColor: Color { AccentChoice.color(for: tabHighlightRaw) }
    private var checkmarkColor: Color { AccentChoice.color(for: checkmarkRaw) }
    private var todayColor: Color { AccentChoice.color(for: todayCircleRaw) }

    private var appAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appAppearanceRaw) ?? .system },
            set: { newValue in
                appAppearanceRaw = newValue.rawValue
                AppAppearanceStore.save(newValue)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppearancePreviewCard(
                    tabColor: tabColor,
                    checkmarkColor: checkmarkColor,
                    todayColor: todayColor
                )

                section(String(localized: "Theme")) {
                    ThemePicker(selection: appAppearance, accent: checkmarkColor)
                }

                section(String(localized: "Text Size")) {
                    textSizeCard
                }

                section(String(localized: "Colors")) {
                    colorsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.screenBackground.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.25), value: textSizeModeRaw)
        .animation(.snappy(duration: 0.25), value: tabHighlightRaw)
        .animation(.snappy(duration: 0.25), value: checkmarkRaw)
        .animation(.snappy(duration: 0.25), value: todayCircleRaw)
    }

    // MARK: Sections

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
    }

    private var textSizeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconChip(systemName: "textformat.size", color: checkmarkColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Text Size")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(Color.primaryText)
                    Text(textSizeMode == .automatic
                         ? String(localized: "Matches your iPhone setting")
                         : String(localized: "Custom size for Edin"))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer(minLength: 8)
            }

            CapsuleSegmentedControl(
                options: [
                    SegmentOption(value: AppTextSize.Mode.automatic.rawValue, title: String(localized: "Automatic")),
                    SegmentOption(value: AppTextSize.Mode.custom.rawValue, title: String(localized: "Custom"))
                ],
                selection: $textSizeModeRaw,
                accent: checkmarkColor
            )

            if textSizeMode == .custom {
                TextSizeSlider(index: $textSizeIndex, accent: checkmarkColor)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .appearanceCard()
    }

    private var colorsCard: some View {
        VStack(spacing: 0) {
            AccentRow(setting: .tabHighlight, icon: "dock.rectangle", selection: $tabHighlightRaw)
            cardDivider
            AccentRow(setting: .checkmark, icon: "checkmark", isCircle: true, selection: $checkmarkRaw)
            cardDivider
            AccentRow(
                setting: .todayCircle,
                icon: "calendar",
                iconText: "\(Calendar.current.component(.day, from: Date()))",
                isCircle: true,
                selection: $todayCircleRaw
            )
        }
        .appearanceCard()
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.18))
            .frame(height: 0.5)
            .padding(.leading, 60)
    }
}

// MARK: - Card style

private extension View {
    func appearanceCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.appBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.14), lineWidth: 0.5)
        )
    }
}

private struct IconChip: View {
    let systemName: String
    let color: Color
    /// Shown instead of the symbol when set (e.g. today's day number).
    var text: String? = nil
    var isCircle = false

    var body: some View {
        Group {
            if let text {
                Text(text)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .foregroundColor(.white)
        .frame(width: 32, height: 32)
        .background {
            if isCircle {
                Circle().fill(color.gradient)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.gradient)
            }
        }
    }
}

// MARK: - Live preview

private struct AppearancePreviewCard: View {
    let tabColor: Color
    let checkmarkColor: Color
    let todayColor: Color

    private let calendar = Calendar.current

    private var weekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let isToday = calendar.isDateInToday(day)
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 16, weight: isToday ? .bold : .regular))
                            .foregroundColor(isToday ? .white : Color.primaryText)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(isToday ? todayColor : .clear))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 12) {
                Capsule()
                    .fill(Color.eventBlue)
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Design review")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(Color.primaryText)
                    Text("Today, 17:00")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(checkmarkColor.mix(with: .white, by: 0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(checkmarkColor.gradient))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.pillBackground.opacity(0.55))
            )

            HStack(spacing: 0) {
                previewTab(icon: "calendar", title: String(localized: "Calendar"), selected: true)
                previewTab(icon: "list.bullet", title: String(localized: "Upcoming"), selected: false)
                previewTab(icon: "gearshape", title: String(localized: "Settings"), selected: false)
            }
            .padding(5)
            .background(Capsule().fill(Color.pillBackground.opacity(0.55)))
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.appBackground)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [todayColor.opacity(0.16), tabColor.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.14), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview"))
    }

    private func previewTab(icon: String, title: String, selected: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(selected ? tabColor : Color.primaryText.opacity(0.7))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(selected ? Color.primaryText.opacity(0.08) : .clear)
        )
    }
}

// MARK: - Theme

private struct ThemePicker: View {
    @Binding var selection: AppAppearance
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppAppearance.allCases) { option in
                let isSelected = option == selection
                Button {
                    Haptics.selection()
                    selection = option
                } label: {
                    VStack(spacing: 10) {
                        ThemeThumbnail(appearance: option)
                            .frame(height: 92)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isSelected ? accent : Color.gray.opacity(0.25), lineWidth: isSelected ? 2.5 : 0.5)
                            )

                        HStack(spacing: 5) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isSelected ? accent : .gray.opacity(0.6))
                            Text(option.title)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundColor(Color.primaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(16)
        .appearanceCard()
    }
}

private struct ThemeThumbnail: View {
    let appearance: AppAppearance

    var body: some View {
        switch appearance {
        case .system:
            HStack(spacing: 0) {
                MiniScreen(isDark: false)
                MiniScreen(isDark: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .light:
            MiniScreen(isDark: false)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .dark:
            MiniScreen(isDark: true)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Tiny mock screen: a few content bars on a light or dark page.
private struct MiniScreen: View {
    let isDark: Bool

    var body: some View {
        let page = isDark ? Color(white: 0.08) : Color(white: 0.96)
        let card = isDark ? Color(white: 0.2) : Color.white
        let bar = isDark ? Color(white: 0.4) : Color(white: 0.78)

        ZStack(alignment: .topLeading) {
            page
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(bar).frame(width: 26, height: 5)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(card)
                    .frame(height: 22)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(card)
                    .frame(height: 22)
            }
            .padding(10)
        }
    }
}

// MARK: - Text size

private struct SegmentOption: Identifiable {
    let value: String
    let title: String

    var id: String { value }
}

private struct CapsuleSegmentedControl: View {
    let options: [SegmentOption]
    @Binding var selection: String
    let accent: Color

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    Haptics.selection()
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : Color.primaryText.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(accent.gradient)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.pillBackground.opacity(0.7)))
    }
}

private struct TextSizeSlider: View {
    @Binding var index: Int
    let accent: Color

    private var lastIndex: Int { AppTextSize.steps.count - 1 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("A")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)

                Slider(
                    value: Binding(
                        get: { Double(index) },
                        set: { newValue in
                            let rounded = Int(newValue.rounded())
                            if rounded != index {
                                Haptics.selection()
                                index = rounded
                            }
                        }
                    ),
                    in: 0...Double(lastIndex),
                    step: 1
                )
                .tint(accent)
                .accessibilityLabel(Text("Text Size"))

                Text("A")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.gray)
            }

            // Thumb centers stop about half a thumb width in from the track ends.
            HStack(spacing: 0) {
                ForEach(0...lastIndex, id: \.self) { step in
                    Circle()
                        .fill(step <= index ? accent : Color.gray.opacity(0.35))
                        .frame(width: step == index ? 6 : 4, height: step == index ? 6 : 4)
                    if step < lastIndex {
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.leading, 35)
            .padding(.trailing, 41)
        }
    }
}

// MARK: - Colors

private struct AccentRow: View {
    let setting: AccentSetting
    let icon: String
    var iconText: String? = nil
    var isCircle = false
    @Binding var selection: String

    private var selectedChoice: AccentChoice {
        AccentChoice(rawValue: selection) ?? setting.defaultChoice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconChip(systemName: icon, color: selectedChoice.color, text: iconText, isCircle: isCircle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(Color.primaryText)
                    Text(setting.subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer(minLength: 8)
                Text(selectedChoice.title)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(AccentChoice.allCases) { choice in
                        swatch(choice)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.leading, 44)
        }
        .padding(16)
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        let isSelected = choice == selectedChoice
        return Button {
            Haptics.selection()
            selection = choice.rawValue
        } label: {
            Circle()
                .fill(choice.color.gradient)
                .frame(width: 30, height: 30)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
                .padding(3)
                .overlay(
                    Circle()
                        .strokeBorder(choice.color, lineWidth: isSelected ? 2 : 0)
                )
                .scaleEffect(isSelected ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
