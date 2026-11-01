//
//  PurchaseManager.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import Foundation
import StoreKit
import Combine

/// Product IDs for subscriptions
enum ProductID: String, CaseIterable {
    case weekly = "com.ali.oneapp.weekly"
    case monthly = "com.ali.oneapp.monthly"
    case annual = "com.ali.oneapp.annual"
    
    var displayName: String {
        switch self {
        case .weekly: return String(localized: "Edin+ Weekly")
        case .monthly: return String(localized: "Edin+ Monthly")
        case .annual: return String(localized: "Edin+ Annual")
        }
    }
    
    /// Short plan label without the Edin+ prefix (e.g. "Monthly").
    var shortName: String {
        switch self {
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        case .annual: return String(localized: "Annual")
        }
    }
    
    var price: String {
        switch self {
        case .weekly: return "$1.99"
        case .monthly: return "$4.99"
        case .annual: return "$49.99"
        }
    }
    
    /// All recurring subscription product IDs.
    static var recurringIDs: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

/// Manages in-app purchases and subscription status
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    /// Legacy one-time purchase ID — no longer sold, still honored for access.
    static let legacyLifetimeProductID = "com.ali.oneapp.lifetime"
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    /// Published so Settings / Manage UI refresh immediately when the active plan changes.
    @Published private(set) var activeSubscriptionProductID: String?
    /// False until the first launch entitlement pass (and optional App Store sync) finishes.
    @Published private(set) var hasFinishedInitialEntitlementCheck = false
    /// True when the user can redeem the annual plan's free-trial introductory offer.
    @Published private(set) var isEligibleForFreeTrial = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userDefaults = UserDefaults.standard
    private let hasUnlimitedAccessKey = "hasUnlimitedAccess"
    private let activeSubscriptionProductIDKey = "activeSubscriptionProductID"
    
    @Published var hasUnlimitedAccess: Bool = false {
        didSet {
            userDefaults.set(hasUnlimitedAccess, forKey: hasUnlimitedAccessKey)
        }
    }
    
    private init() {
        // Load saved state
        hasUnlimitedAccess = userDefaults.bool(forKey: hasUnlimitedAccessKey)
        activeSubscriptionProductID = userDefaults.string(forKey: activeSubscriptionProductIDKey)
        
        Task { @MainActor in
            // Never auto-sync on launch — AppStore.sync() prompts for Apple ID.
            await refreshEntitlements(syncWithAppStore: false)
            hasFinishedInitialEntitlementCheck = true
        }
    }
    
    /// True when the user owns the legacy one-time lifetime purchase.
    var hasLifetimePurchase: Bool {
        purchasedProductIDs.contains(Self.legacyLifetimeProductID)
    }
    
    /// Active recurring plan. Nil for lifetime-only or free users.
    var activeSubscriptionPlan: ProductID? {
        if let id = activeSubscriptionProductID, let plan = ProductID(rawValue: id) {
            return plan
        }
        // Fallback if published ID is missing but IDs are present (prefer longer plans)
        if purchasedProductIDs.contains(ProductID.annual.rawValue) { return .annual }
        if purchasedProductIDs.contains(ProductID.monthly.rawValue) { return .monthly }
        if purchasedProductIDs.contains(ProductID.weekly.rawValue) { return .weekly }
        return nil
    }
    
    /// Get the active subscription product for display.
    var activeSubscriptionProduct: Product? {
        guard !purchasedProductIDs.isEmpty else { return nil }
        
        if let id = activeSubscriptionProductID,
           purchasedProductIDs.contains(id),
           let product = products.first(where: { $0.id == id }) {
            return product
        }
        
        if let plan = activeSubscriptionPlan,
           let product = products.first(where: { $0.id == plan.rawValue }) {
            return product
        }
        
        return products.first { purchasedProductIDs.contains($0.id) }
    }
    
    /// Load available products from App Store
    @MainActor
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let productIDs = ProductID.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIDs)
            await refreshFreeTrialEligibility()
        } catch {
            errorMessage = String(localized: "Failed to load products: \(error.localizedDescription)")
            isEligibleForFreeTrial = false
            #if DEBUG
            print("Error loading products: \(error)")
            #endif
        }
    }

    /// Refresh whether a free-trial intro offer is available for this Apple ID.
    /// Eligibility is per subscription group, so any plan carrying a trial answers for all of them.
    @MainActor
    func refreshFreeTrialEligibility() async {
        guard !hasUnlimitedAccess,
              let trialProduct = products.first(where: {
                  $0.subscription?.introductoryOffer?.paymentMode == .freeTrial
              }),
              let subscription = trialProduct.subscription else {
            isEligibleForFreeTrial = false
            return
        }
        isEligibleForFreeTrial = await subscription.isEligibleForIntroOffer
    }
    
    /// Update purchased products status
    @MainActor
    func updatePurchasedProducts(forceApplyEmptyResult: Bool = false) async {
        var purchasedIDs = Set<String>()
        
        // Prefer Apple's renewal preference (what the user selected in Manage Subscriptions).
        var renewalPreferredProductID: String?
        // Fallback: newest recurring entitlement by purchaseDate.
        var newestSubscriptionProductID: String?
        var newestSubscriptionPurchaseDate: Date?
        
        var expiredOrRevokedIDs = Set<String>()
        var successfullyQueriedProductIDs = Set<String>()
        var sawActiveSubscriptionStatus = false
        var sawAnyVerifiedEntitlement = false
        
        // Fetch subscription statuses concurrently — serial awaits are slow on TestFlight/Sandbox.
        struct StatusQueryResult {
            let productID: String
            let statuses: [Product.SubscriptionInfo.Status]?
        }
        
        let statusResults: [StatusQueryResult] = await withTaskGroup(of: StatusQueryResult.self) { group in
            for product in products {
                guard let subscription = product.subscription else { continue }
                let productID = product.id
                group.addTask {
                    let statuses = try? await subscription.status
                    return StatusQueryResult(productID: productID, statuses: statuses)
                }
            }
            var collected: [StatusQueryResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        
        for result in statusResults {
            guard let statuses = result.statuses else { continue }
            successfullyQueriedProductIDs.insert(result.productID)
            
            for status in statuses {
                let state = status.state
                switch state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    purchasedIDs.insert(result.productID)
                    sawActiveSubscriptionStatus = true
                    #if DEBUG
                    print("✅ Active subscription found: \(result.productID) (\(state))")
                    #endif
                    
                    if case .verified(let renewalInfo) = status.renewalInfo {
                        // What the customer selected to renew as (updates immediately in Manage).
                        if let preference = renewalInfo.autoRenewPreference,
                           ProductID.recurringIDs.contains(preference) {
                            renewalPreferredProductID = preference
                        }
                        // Currently entitled product in the group (iOS 17+).
                        let currentID = renewalInfo.currentProductID
                        if renewalPreferredProductID == nil,
                           ProductID.recurringIDs.contains(currentID) {
                            renewalPreferredProductID = currentID
                        }
                    }
                    
                    if case .verified(let transaction) = status.transaction,
                       ProductID.recurringIDs.contains(transaction.productID) {
                        if let currentNewest = newestSubscriptionPurchaseDate {
                            if transaction.purchaseDate > currentNewest {
                                newestSubscriptionPurchaseDate = transaction.purchaseDate
                                newestSubscriptionProductID = transaction.productID
                            }
                        } else {
                            newestSubscriptionPurchaseDate = transaction.purchaseDate
                            newestSubscriptionProductID = transaction.productID
                        }
                    }
                case .expired, .revoked:
                    expiredOrRevokedIDs.insert(result.productID)
                    #if DEBUG
                    print("⚠️ Subscription \(state): \(result.productID)")
                    #endif
                default:
                    #if DEBUG
                    print("❓ Unknown subscription state for: \(result.productID)")
                    #endif
                }
            }
        }
        
        // Entitlements (access + purchaseDate fallback)
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                purchasedIDs.insert(transaction.productID)
                sawAnyVerifiedEntitlement = true
                #if DEBUG
                print("✅ Active entitlement found: \(transaction.productID)")
                #endif
                
                if ProductID.recurringIDs.contains(transaction.productID) {
                    if let currentNewest = newestSubscriptionPurchaseDate {
                        if transaction.purchaseDate > currentNewest {
                            newestSubscriptionPurchaseDate = transaction.purchaseDate
                            newestSubscriptionProductID = transaction.productID
                        }
                    } else {
                        newestSubscriptionPurchaseDate = transaction.purchaseDate
                        newestSubscriptionProductID = transaction.productID
                    }
                }
            case .unverified:
                #if DEBUG
                print("⚠️ Unverified transaction for product: \(result)")
                #endif
            }
        }
        
        let activeRecurring = purchasedIDs.intersection(ProductID.recurringIDs)
        let preferred = renewalPreferredProductID
            ?? newestSubscriptionProductID
            ?? activeRecurring.first
        
        if purchasedIDs.isEmpty {
            let shouldClear = forceApplyEmptyResult
                || Self.shouldClearAccessAfterEmptyResult(
                    products: products,
                    successfullyQueriedProductIDs: successfullyQueriedProductIDs,
                    expiredOrRevokedIDs: expiredOrRevokedIDs,
                    sawActiveSubscriptionStatus: sawActiveSubscriptionStatus,
                    sawAnyVerifiedEntitlement: sawAnyVerifiedEntitlement
                )
            
            if shouldClear {
                #if DEBUG
                print("ℹ️ Clearing access — StoreKit reports no active entitlements")
                #endif
                applyPurchasedIDs([], preferredSubscriptionID: nil)
            } else {
                #if DEBUG
                print("ℹ️ Preserving prior access — inconclusive empty StoreKit result (products=\(products.count), queried=\(successfullyQueriedProductIDs.count), expired=\(expiredOrRevokedIDs.count))")
                #endif
            }
        } else {
            // Keep unlimited access for any active recurring/lifetime entitlement,
            // but surface a single active plan ID for Settings / paywall UI.
            applyPurchasedIDs(purchasedIDs, preferredSubscriptionID: preferred)
        }
        
        // Access may have just changed, so recompute trial eligibility against the new state.
        await refreshFreeTrialEligibility()
        
        #if DEBUG
        if hasUnlimitedAccess {
            print("✅ User has unlimited access - Products: \(purchasedProductIDs), active: \(activeSubscriptionProductID ?? "nil"), renewalPreferred: \(renewalPreferredProductID ?? "nil")")
        } else {
            print("ℹ️ User does not have unlimited access")
        }
        print("ℹ️ Free trial eligible: \(isEligibleForFreeTrial)")
        #endif
    }
    
    /// True when empty entitlements are backed by explicit expiry/revocation for every sold recurring product.
    private static func shouldClearAccessAfterEmptyResult(
        products: [Product],
        successfullyQueriedProductIDs: Set<String>,
        expiredOrRevokedIDs: Set<String>,
        sawActiveSubscriptionStatus: Bool,
        sawAnyVerifiedEntitlement: Bool
    ) -> Bool {
        guard !sawActiveSubscriptionStatus, !sawAnyVerifiedEntitlement else { return false }
        
        let recurringProductIDs = Set(
            products
                .map(\.id)
                .filter { ProductID.recurringIDs.contains($0) }
        )
        
        // No products loaded and no entitlements — treat as inconclusive (don't wipe).
        guard !recurringProductIDs.isEmpty else { return false }
        
        // Only clear when we successfully queried every recurring product and each is expired/revoked.
        guard successfullyQueriedProductIDs.isSuperset(of: recurringProductIDs) else { return false }
        return recurringProductIDs.isSubset(of: expiredOrRevokedIDs)
    }
    
    /// Load products and refresh entitlements. When `syncWithAppStore` is true, sync with
    /// the App Store first (needed after reinstall before entitlements appear).
    @MainActor
    func refreshEntitlements(syncWithAppStore: Bool) async {
        var didSyncWithAppStore = false
        if syncWithAppStore {
            do {
                try await AppStore.sync()
                didSyncWithAppStore = true
                errorMessage = nil
            } catch {
                #if DEBUG
                print("⚠️ AppStore.sync failed: \(error.localizedDescription)")
                #endif
                errorMessage = String(localized: "Could not sync purchases: \(error.localizedDescription)")
            }
        }
        
        await loadProducts()
        // After a successful App Store sync, trust an empty result and clear stale local access.
        await updatePurchasedProducts(forceApplyEmptyResult: didSyncWithAppStore)
        if hasUnlimitedAccess {
            errorMessage = nil
        }
        objectWillChange.send()
    }
    
    /// Refresh entitlements after Manage Subscriptions dismisses (no Apple ID prompt).
    @MainActor
    func refreshAfterManageSubscriptions() async {
        await loadProducts()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await updatePurchasedProducts()
        objectWillChange.send()
    }
    
    /// Purchase a product
    @MainActor
    func purchase(_ product: Product) async throws {
        #if DEBUG
        print("🛒 Attempting to purchase: \(product.id)")
        #endif
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                #if DEBUG
                print("✅ Purchase verified: \(transaction.productID)")
                #endif
                
                // Immediately add to purchasedProductIDs for all purchase types
                // This ensures UI updates immediately, even before entitlements sync
                var updatedIDs = purchasedProductIDs
                updatedIDs.insert(transaction.productID)
                
                // If purchasing a recurring plan, remove the other recurring plans
                var preferredSubscriptionID: String? = activeSubscriptionProductID
                if ProductID.recurringIDs.contains(transaction.productID) {
                    for id in ProductID.recurringIDs where id != transaction.productID {
                        updatedIDs.remove(id)
                    }
                    preferredSubscriptionID = transaction.productID
                    #if DEBUG
                    print("🔄 Kept \(transaction.productID); removed other recurring plans")
                    #endif
                }
                
                applyPurchasedIDs(updatedIDs, preferredSubscriptionID: preferredSubscriptionID)
                #if DEBUG
                print("✅ Purchase immediately recognized: \(transaction.productID)")
                print("✅ Current purchased products: \(updatedIDs), active: \(activeSubscriptionProductID ?? "nil")")
                #endif
                
                await transaction.finish()
                // Don't await full StoreKit status refresh — it can hang TestFlight/Sandbox for a long time.
                objectWillChange.send()
                Task { @MainActor in
                    await updatePurchasedProducts()
                    objectWillChange.send()
                }
            case .unverified(_, let error):
                #if DEBUG
                print("❌ Purchase unverified: \(error)")
                #endif
                throw PurchaseError.unverifiedTransaction
            }
        case .userCancelled:
            #if DEBUG
            print("ℹ️ User cancelled purchase")
            #endif
            throw PurchaseError.userCancelled
        case .pending:
            #if DEBUG
            print("⏳ Purchase pending (awaiting approval)")
            #endif
            // Don't throw for pending - it's a valid state that will be handled by the listener
            Task { @MainActor in
                await updatePurchasedProducts()
            }
        @unknown default:
            #if DEBUG
            print("❓ Unknown purchase result")
            #endif
            throw PurchaseError.unknown
        }
    }
    
    /// Restore previous purchases
    @MainActor
    func restorePurchases() async -> RestorePurchasesResult {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await refreshEntitlements(syncWithAppStore: true)
        if hasUnlimitedAccess {
            return .restored
        }
        if let errorMessage {
            return .failed(errorMessage)
        }
        return .nothingFound
    }
    
    /// Applies purchased IDs and refreshes the published active subscription plan.
    @MainActor
    private func applyPurchasedIDs(_ purchasedIDs: Set<String>, preferredSubscriptionID: String?) {
        purchasedProductIDs = purchasedIDs
        hasUnlimitedAccess = !purchasedIDs.isEmpty
        
        let hasAnyRecurring = !purchasedIDs.intersection(ProductID.recurringIDs).isEmpty
        
        // Prefer Apple's renewal selection even when the new plan isn't entitled yet
        // (e.g. downgrade scheduled for next period).
        let resolved: String?
        if let preferred = preferredSubscriptionID,
           ProductID.recurringIDs.contains(preferred),
           purchasedIDs.contains(preferred) || hasAnyRecurring {
            resolved = preferred
        } else if purchasedIDs.contains(ProductID.annual.rawValue) {
            resolved = ProductID.annual.rawValue
        } else if purchasedIDs.contains(ProductID.monthly.rawValue) {
            resolved = ProductID.monthly.rawValue
        } else if purchasedIDs.contains(ProductID.weekly.rawValue) {
            resolved = ProductID.weekly.rawValue
        } else {
            resolved = nil
        }
        
        activeSubscriptionProductID = resolved
        if let resolved {
            userDefaults.set(resolved, forKey: activeSubscriptionProductIDKey)
        } else {
            userDefaults.removeObject(forKey: activeSubscriptionProductIDKey)
        }
    }
}

enum RestorePurchasesResult {
    case restored
    case nothingFound
    case failed(String)
}

enum PurchaseError: LocalizedError {
    case unverifiedTransaction
    case userCancelled
    case pending
    case unknown
    case productUnavailable
    
    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            return String(localized: "Transaction could not be verified. Please try again or contact support.")
        case .userCancelled:
            return String(localized: "Purchase was cancelled")
        case .pending:
            return String(localized: "Your purchase is pending approval. You'll be notified when it's complete.")
        case .unknown:
            return String(localized: "An unknown error occurred. Please try again.")
        case .productUnavailable:
            return String(localized: "This product is currently unavailable. Please try again later.")
        }
    }
}
