//
//  OneApp.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import CoreData
import StoreKit

@main
struct OneApp: App {
    let persistenceController = PersistenceController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
    
    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRaw) ?? .system
    }
    
    init() {
        AppAppearanceStore.syncStandardToAppGroup()
        // Set up transaction listener for StoreKit 2
        Task { @MainActor in
            for await result in StoreKit.Transaction.updates {
                await Self.handleTransactionUpdate(result)
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            AppLifecycleView {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .sheet(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { _ in }
                    )) {
                        OnboardingView {
                            hasCompletedOnboarding = true
                        }
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .presentationDetents([.height(OnboardingView.preferredSheetHeight)])
                        .presentationDragIndicator(.hidden)
                        .presentationBackground(Color.sheetSurface)
                        .interactiveDismissDisabled()
                    }
                    .preferredColorScheme(appAppearance.preferredColorScheme)
            }
        }
    }

    @MainActor
    private static func handleTransactionUpdate(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            // Update purchase status
            await PurchaseManager.shared.updatePurchasedProducts()
            // Finish the transaction
            await transaction.finish()
        case .unverified:
            // Log unverified transaction but don't block
            #if DEBUG
            print("Unverified transaction detected")
            #endif
        }
    }
}

private struct AppLifecycleView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { @MainActor in
                    WidgetPendingCompletionDrainer.drain()
                    await PurchaseManager.shared.refreshEntitlements(syncWithAppStore: false)
                }
            }
    }
}
