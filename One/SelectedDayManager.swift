//
//  SelectedDayManager.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import Foundation
import Combine

class SelectedDayManager: ObservableObject {
    static let shared = SelectedDayManager()
    
    @Published var selectedDay: Date?
    
    private init() {}

    var isViewingToday: Bool {
        guard let selectedDay else { return true }
        return Calendar.current.isDateInToday(selectedDay)
    }

    func jumpToToday() {
        selectedDay = Calendar.current.startOfDay(for: Date())
    }
}
