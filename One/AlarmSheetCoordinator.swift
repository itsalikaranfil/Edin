//
//  AlarmSheetCoordinator.swift
//  One
//

import Foundation
import Combine

final class AlarmSheetCoordinator: ObservableObject {
    static let shared = AlarmSheetCoordinator()

    @Published var isPresented = false
    @Published var requestAddAlarm = false

    private init() {}

    func triggerAddAlarm() {
        requestAddAlarm = true
    }

    func consumeAddAlarmRequest() {
        requestAddAlarm = false
    }
}
