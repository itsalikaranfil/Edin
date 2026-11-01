//
//  AlarmAuthorizationStore.swift
//  One
//

import AlarmKit
import Combine
import Foundation
import UIKit

@MainActor
final class AlarmAuthorizationStore: ObservableObject {
    static let shared = AlarmAuthorizationStore()

    @Published private(set) var isAuthorized = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        refresh()
        updatesTask = Task {
            for await state in AlarmManager.shared.authorizationUpdates {
                isAuthorized = state == .authorized
            }
        }
    }

    func refresh() {
        isAuthorized = AlarmManager.shared.authorizationState == .authorized
    }

    func requestAuthorization() async -> Bool {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            isAuthorized = state == .authorized
            return isAuthorized
        } catch {
            refresh()
            return false
        }
    }

    /// Prompt for AlarmKit access, or open Settings if previously denied.
    func handlePermissionTap() {
        guard !isAuthorized else { return }
        Task {
            switch AlarmManager.shared.authorizationState {
            case .notDetermined:
                let granted = await requestAuthorization()
                if !granted {
                    openSystemSettings()
                }
            case .denied:
                openSystemSettings()
            case .authorized:
                break
            @unknown default:
                openSystemSettings()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
