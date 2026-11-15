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
