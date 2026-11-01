//
//  FolderSheetCoordinator.swift
//  One
//

import Foundation
import Combine

final class FolderSheetCoordinator: ObservableObject {
    static let shared = FolderSheetCoordinator()

    @Published var isPresented = false
    @Published var requestAddFolder = false
    @Published var viewingFolderID: UUID?

    private init() {}

    func triggerAddFolder() {
        requestAddFolder = true
    }

    func consumeAddFolderRequest() {
        requestAddFolder = false
    }
}
