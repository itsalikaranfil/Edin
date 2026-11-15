//
//  AccentColors.swift
//  One
//

import SwiftUI

/// Colors offered on the Appearance page for each customizable accent.
enum AccentChoice: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case blue
    case indigo
    case purple
    case pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .flagRed
        case .orange: return Color(uiColor: .systemOrange)
        case .yellow: return Color(uiColor: .systemYellow)
        case .green: return Color(uiColor: .systemGreen)
        case .mint: return Color(uiColor: .systemMint)
        case .teal: return Color(uiColor: .systemTeal)
        case .blue: return Color(uiColor: .systemBlue)
        case .indigo: return Color(uiColor: .systemIndigo)
        case .purple: return Color(uiColor: .systemPurple)
        case .pink: return Color(uiColor: .systemPink)
        }
    }

    var title: String {
        switch self {
        case .red: return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .mint: return String(localized: "Mint")
        case .teal: return String(localized: "Teal")
        case .blue: return String(localized: "Blue")
        case .indigo: return String(localized: "Indigo")
        case .purple: return String(localized: "Purple")
        case .pink: return String(localized: "Pink")
        }
    }

    /// Color for a stored raw value; unknown values fall back to the default red.
    static func color(for rawValue: String) -> Color {
        (AccentChoice(rawValue: rawValue) ?? .red).color
    }
}

/// Each accent the user can recolor separately. Raw values are the `@AppStorage` keys.
enum AccentSetting: String, CaseIterable, Identifiable {
    case tabHighlight = "accentTabHighlight"
    case checkmark = "accentCheckmark"
    case todayCircle = "accentTodayCircle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tabHighlight: return String(localized: "Tab Highlight")
        case .checkmark: return String(localized: "Checkmarks")
        case .todayCircle: return String(localized: "Today Circle")
        }
    }

    var subtitle: String {
        switch self {
        case .tabHighlight: return String(localized: "Selected tab in the tab bar")
        case .checkmark: return String(localized: "Save and Done buttons, selected options")
        case .todayCircle: return String(localized: "Today's date in the calendar")
        }
    }

    var defaultChoice: AccentChoice { .red }
}

/// App-wide text size from the Appearance page. Automatic follows the system Dynamic Type setting.
enum AppTextSize {
    static let modeKey = "textSizeMode"
    static let customIndexKey = "textSizeCustomIndex"

    enum Mode: String {
        case automatic
        case custom
    }

    /// Slider steps, smallest to largest; `.large` is the system default.
    static let steps: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3
    ]

    static var defaultIndex: Int {
        steps.firstIndex(of: .large) ?? 3
    }

    static func size(forIndex index: Int) -> DynamicTypeSize {
        steps[min(max(index, 0), steps.count - 1)]
    }
}

/// Applies the custom text size from the Appearance page, or leaves the system size alone.
struct AppTextSizeModifier: ViewModifier {
    @AppStorage(AppTextSize.modeKey) private var modeRaw = AppTextSize.Mode.automatic.rawValue
    @AppStorage(AppTextSize.customIndexKey) private var customIndex = AppTextSize.defaultIndex
    @Environment(\.dynamicTypeSize) private var systemSize

    // Always applied (system size when automatic) so switching modes keeps the view tree intact.
    func body(content: Content) -> some View {
        let isCustom = AppTextSize.Mode(rawValue: modeRaw) == .custom
        content.dynamicTypeSize(isCustom ? AppTextSize.size(forIndex: customIndex) : systemSize)
    }
}
