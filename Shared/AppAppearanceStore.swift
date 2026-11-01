//
//  AppAppearanceStore.swift
//  Shared between the main app and widget extension.
//

import SwiftUI
import WidgetKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppAppearanceStore {
    static let key = "appAppearance"
    static let appGroupID = WidgetSnapshot.appGroupID

    static func load() -> AppAppearance {
        if let group = UserDefaults(suiteName: appGroupID),
           let raw = group.string(forKey: key),
           let value = AppAppearance(rawValue: raw) {
            return value
        }
        if let raw = UserDefaults.standard.string(forKey: key),
           let value = AppAppearance(rawValue: raw) {
            return value
        }
        return .system
    }

    /// Writes to both standard and App Group defaults, then reloads widgets.
    static func save(_ appearance: AppAppearance, reloadWidgets: Bool = true) {
        UserDefaults.standard.set(appearance.rawValue, forKey: key)
        UserDefaults(suiteName: appGroupID)?.set(appearance.rawValue, forKey: key)
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Copies the main-app @AppStorage value into the App Group for the widget.
    static func syncStandardToAppGroup(reloadWidgets: Bool = false) {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppAppearance.system.rawValue
        UserDefaults(suiteName: appGroupID)?.set(raw, forKey: key)
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
