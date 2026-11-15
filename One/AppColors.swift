//
//  AppColors.swift
//  One
//

import SwiftUI
import UIKit

extension Color {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// Full-screen page background.
    static let screenBackground = dynamic(
        light: UIColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1),
        dark: .black
    )

    /// Main surface for item groups and rows.
    static let appBackground = dynamic(
        light: UIColor(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1),
        dark: UIColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1)
    )

    /// Draggable sheet surface.
    static let sheetSurface = dynamic(
        light: UIColor(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1),
        dark: UIColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1)
    )

    /// Calendar tab sheets, the calendar Folders/Alarms bars, and Upcoming item sections.
    static let calendarSheetSurface = dynamic(
        light: .white,
        dark: UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    )

    /// Hairline top edge highlight on the calendar tab sheets.
    static let calendarSheetEdge = dynamic(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.06)
    )

    /// Filter pill background.
    static let pillBackground = dynamic(
        light: UIColor(red: 228 / 255, green: 228 / 255, blue: 230 / 255, alpha: 1),
        dark: UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
    )

    /// Primary labels and titles.
    static let primaryText = dynamic(
        light: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
        dark: .white
    )

    /// Event accent blue.
    static let eventBlue = Color(red: 0.098, green: 0.698, blue: 1.0)

    /// Reminder accent orange.
    static let reminderOrange = Color(red: 1.0, green: 0.761, blue: 0.098)

    /// Alarm accent orange (#FF9500).
    static let alarmOrange = Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255)

    /// Folder icon cyan.
    static let folderCyan = Color(red: 0.0, green: 0.82, blue: 0.95)

    /// Flagged indicator red (#FF1919).
    static let flagRed = Color(red: 255 / 255, green: 25 / 255, blue: 25 / 255)

    /// Edin+ premium red.
    static let premiumRed = Color(red: 1.0, green: 0.12, blue: 0.14)

    /// Brighter premium red for CTAs and Settings cards.
    static let premiumRedBright = Color(red: 1.0, green: 0.32, blue: 0.34)

    /// Deeper red for soft glows only.
    static let premiumRedDeep = Color(red: 0.62, green: 0.03, blue: 0.09)
}
