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

    private var checkmarkColor: Color {
        AccentChoice.color(for: checkmarkRaw)
    }

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
            VStack(alignment: .leading, spacing: 28) {
                textSizeSection

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(title: String(localized: "Theme"), subtitle: nil)
                    Picker("Theme", selection: appAppearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                accentSection(.tabHighlight, selection: $tabHighlightRaw)
                accentSection(.checkmark, selection: $checkmarkRaw)
                accentSection(.todayCircle, selection: $todayCircleRaw)
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .background(Color.screenBackground)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var textSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: String(localized: "Text Size"), subtitle: nil)

            VStack(spacing: 0) {
                textSizeModeRow(.automatic, title: String(localized: "Automatic"))
                Divider()
                textSizeModeRow(.custom, title: String(localized: "Custom"))

                if textSizeMode == .custom {
                    TextSizeSlider(index: $textSizeIndex)
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: textSizeMode)

            Text("“Automatic” matches Edin to your iPhone’s text size setting.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func textSizeModeRow(_ mode: AppTextSize.Mode, title: String) -> some View {
        Button {
            Haptics.selection()
            textSizeModeRaw = mode.rawValue
        } label: {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundColor(Color.primaryText)
                Spacer()
                if textSizeMode == mode {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(checkmarkColor)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.8))
            }
        }
    }

    private func accentSection(_ setting: AccentSetting, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: setting.title, subtitle: setting.subtitle)
            AccentSwatchGrid(selection: selection)
        }
    }
}

private struct TextSizeSlider: View {
    @Binding var index: Int

    private var lastIndex: Int { AppTextSize.steps.count - 1 }

    var body: some View {
        HStack(spacing: 12) {
            Text("A")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)

            VStack(spacing: 6) {
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
                .tint(.gray)
                .accessibilityLabel(Text("Text Size"))

                // Thumb centers stop about half a thumb width in from the track ends.
                HStack(spacing: 0) {
                    ForEach(0...lastIndex, id: \.self) { step in
                        Capsule()
                            .fill(Color.gray.opacity(step == index ? 0.9 : 0.45))
                            .frame(width: 1.5, height: step == index ? 8 : 6)
                        if step < lastIndex {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 13)
            }

            Text("A")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.gray)
        }
    }
}

private struct AccentSwatchGrid: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    private var selectedChoice: AccentChoice {
        AccentChoice(rawValue: selection) ?? .red
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AccentChoice.allCases) { choice in
                let isSelected = choice == selectedChoice
                Button {
                    Haptics.selection()
                    selection = choice.rawValue
                } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 40, height: 40)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(3)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? choice.color : .clear, lineWidth: 2)
                        )
                        .frame(maxWidth: .infinity)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
