//
//  SubscriptionView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    
    @State private var selectedProduct: Product?
    @State private var selectedProductID: String?
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    // Ordered subscription products: Weekly, Monthly, Annual
    private var orderedProducts: [Product] {
        let productOrder: [String] = [
            ProductID.weekly.rawValue,
            ProductID.monthly.rawValue,
            ProductID.annual.rawValue
        ]
        
        return productOrder.compactMap { productID in
            purchaseManager.products.first { $0.id == productID }
        }
    }

    private var annualProduct: Product? {
        orderedProducts.first { $0.id == ProductID.annual.rawValue }
    }

    private var monthlyProduct: Product? {
        orderedProducts.first { $0.id == ProductID.monthly.rawValue }
    }
    
    private var isManaging: Bool {
        purchaseManager.activeSubscriptionPlan != nil && !purchaseManager.hasLifetimePurchase
    }
    
    private var currentPlanID: String? {
        purchaseManager.activeSubscriptionPlan?.rawValue
    }

    private var selectedResolvedProduct: Product? {
        if let selectedProduct { return selectedProduct }
        if let selectedProductID {
            return orderedProducts.first { $0.id == selectedProductID }
        }
        return nil
    }

    /// Trial length for the selected plan, falling back to any plan carrying an offer.
    private var trialDurationText: String? {
        if let selected = selectedResolvedProduct, let text = selected.oneTrialDurationText {
            return text
        }
        return orderedProducts.compactMap(\.oneTrialDurationText).first
    }

    private var showTrialCTA: Bool {
        purchaseManager.isEligibleForFreeTrial
            && !isManaging
            && selectedResolvedProduct?.oneFreeTrialOffer != nil
    }
    
    private var taglineText: String {
        if purchaseManager.hasLifetimePurchase {
            return String(localized: "You own Edin+ Lifetime")
        }
        if let plan = purchaseManager.activeSubscriptionPlan {
            return String(localized: "You are subscribed to \(plan.shortName)")
        }
        return String(localized: "Plan your days without limits.")
    }
    
    private var primaryButtonTitle: String {
        if isPurchasing { return String(localized: "Processing...") }
        if showTrialCTA {
            return String(localized: "Start My Free Trial")
        }
        if isManaging { return String(localized: "Upgrade") }
        return String(localized: "Get Edin+")
    }

    private var ctaCaption: String? {
        guard canSubscribe, !isPurchasing else { return nil }
        if showTrialCTA, let product = selectedResolvedProduct {
            return String(
                localized: "No payment now. Then \(product.displayPrice)/\(product.oneShortPeriodLabel), cancel anytime."
            )
        }
        if let product = selectedResolvedProduct {
            return String(
                localized: "\(product.displayPrice)/\(product.oneShortPeriodLabel). Cancel anytime."
            )
        }
        return String(localized: "Cancel anytime")
    }
    
    // Whether the user can start a purchase (real StoreKit product required, not current plan)
    private var canSubscribe: Bool {
        guard let selectedID = selectedProduct?.id ?? selectedProductID,
              !orderedProducts.isEmpty else { return false }
        if purchaseManager.hasLifetimePurchase { return false }
        if let currentPlanID, selectedID == currentPlanID { return false }
        return selectedProduct != nil
    }

    private var annualSavingsPercent: Int? {
        guard let annual = annualProduct, let monthly = monthlyProduct else { return nil }
        return annual.oneAnnualSavingsPercent(comparedTo: monthly)
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    PaywallHero(tagline: taglineText)
                        .padding(.top, 52)

                    if purchaseManager.hasLifetimePurchase {
                        Text("You already own Edin+ Lifetime. No further purchase is needed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        benefitsSection
                        plansSection
                        trialTimelineSection
                        legalSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showTrialCTA)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                if !purchaseManager.hasLifetimePurchase {
                    ctaSection
                }
            }

            SheetClosePill(size: 40) {
                dismiss()
            }
            .padding(.leading, 20)
            .padding(.top, 16)
        }
        .presentationBackground(Color.screenBackground)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your subscription is now active! Thank you for your purchase.")
        }
        .onAppear {
            Task {
                await purchaseManager.loadProducts()
                await purchaseManager.updatePurchasedProducts()
                applyDefaultSelection()
            }
        }
        .onChange(of: purchaseManager.products) { _, newValue in
            if let productID = selectedProductID,
               selectedProduct == nil,
               let product = newValue.first(where: { $0.id == productID }) {
                selectedProduct = product
            }
            if selectedProduct == nil {
                applyDefaultSelection()
            }
        }
        .onChange(of: purchaseManager.isEligibleForFreeTrial) { _, _ in
            applyDefaultSelection()
        }
    }

    // MARK: - Sections

    private var benefitsSection: some View {
        VStack(spacing: 16) {
            PaywallBenefitRow(
                icon: "infinity",
                title: "Unlimited everything",
                subtitle: "Reminders, events and habits — no 6-item cap."
            )
            PaywallBenefitRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Habit streaks & stats",
                subtitle: "Track progress and keep the streak alive."
            )
            PaywallBenefitRow(
                icon: "alarm.fill",
                title: "Alarms & widgets",
                subtitle: "Wake up and glance at your day from Home Screen."
            )
            PaywallBenefitRow(
                icon: "icloud.fill",
                title: "iCloud sync",
                subtitle: "Your plans stay in sync across devices."
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.appBackground)
        )
    }

    @ViewBuilder
    private var trialTimelineSection: some View {
        if showTrialCTA,
           let product = selectedResolvedProduct,
           let trialDurationText = product.oneTrialDurationText,
           let trialEndDate = product.oneTrialEndDate() {
            PaywallTrialTimeline(
                trialDurationText: trialDurationText,
                trialEndDate: trialEndDate,
                renewalPriceText: "\(product.displayPrice)/\(product.oneShortPeriodLabel)"
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var plansSection: some View {
        VStack(spacing: 10) {
            if purchaseManager.isLoading && orderedProducts.isEmpty {
                ProgressView()
                    .padding()
            } else if !orderedProducts.isEmpty {
                // Annual first: it is the default pick and carries the savings and trial.
                ForEach(orderedProducts.reversed(), id: \.id) { product in
                    let isAnnual = product.id == ProductID.annual.rawValue
                    PaywallPlanOption(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        isCurrent: product.id == currentPlanID,
                        showTrialBadge: purchaseManager.isEligibleForFreeTrial
                            && product.oneFreeTrialOffer != nil,
                        savingsPercent: isAnnual ? annualSavingsPercent : nil,
                        onTap: {
                            selectedProduct = product
                            selectedProductID = product.id
                        }
                    )
                }
            } else {
                VStack(spacing: 12) {
                    Text("Unable to load plans")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await purchaseManager.loadProducts()
                        }
                    } label: {
                        Text("Tap to retry")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.screenBackground)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.primaryText))
                    }
                    .buttonStyle(PaywallPressStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 10) {
            PaywallCTAButton(
                title: primaryButtonTitle,
                isEnabled: canSubscribe && !isPurchasing,
                isLoading: isPurchasing
            ) {
                purchaseSelectedProduct()
            }

            if let ctaCaption {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                    Text(ctaCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button(action: {
                Task {
                    let result = await purchaseManager.restorePurchases()
                    switch result {
                    case .restored:
                        showSuccess = true
                    case .nothingFound:
                        errorMessage = String(localized: "No previous purchases found for this Apple ID.")
                        showError = true
                    case .failed(let message):
                        errorMessage = message
                        showError = true
                    }
                }
            }) {
                Text("Restore purchase")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                colors: [Color.screenBackground.opacity(0), Color.screenBackground],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.3)
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if purchaseManager.isEligibleForFreeTrial, let trialDurationText {
                Text("New subscribers get a \(trialDurationText) free trial on any Edin+ plan. After the trial, the plan you chose renews at its listed price unless you cancel at least 24 hours before the trial ends. The free trial is available once per Apple ID.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your Account Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("TestFlight / Sandbox may show shortened renewal dates (for example, a monthly plan ending in a day). Production billing follows the weekly, monthly, or yearly period.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 20) {
                Link("Terms of Use", destination: LegalURLs.termsOfUse)
                Link("Privacy Policy", destination: LegalURLs.privacyPolicy)
            }
            .font(.caption)
            .fontWeight(.medium)
            .tint(Color.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
    
    private func applyDefaultSelection() {
        if purchaseManager.hasLifetimePurchase {
            selectedProduct = nil
            selectedProductID = nil
            return
        }
        
        // When managing, prefer the first plan that isn't the current one.
        if isManaging, let currentPlanID {
            if let upgrade = orderedProducts.first(where: { $0.id != currentPlanID }) {
                selectedProduct = upgrade
                selectedProductID = upgrade.id
                return
            }
        }

        // Prefer annual when the free trial is available — that plan carries the offer.
        if purchaseManager.isEligibleForFreeTrial,
           let annual = annualProduct {
            selectedProduct = annual
            selectedProductID = annual.id
            return
        }
        
        if selectedProduct == nil && selectedProductID == nil,
           let firstProduct = annualProduct ?? orderedProducts.first ?? purchaseManager.products.first {
            selectedProduct = firstProduct
            selectedProductID = firstProduct.id
        }
    }
    
    private func purchaseSelectedProduct() {
        Haptics.light()
        guard canSubscribe else {
            if let currentPlanID,
               (selectedProduct?.id ?? selectedProductID) == currentPlanID {
                errorMessage = String(localized: "This is your current plan. Choose another option to upgrade.")
            } else {
                errorMessage = String(localized: "Please select a subscription option")
            }
            showError = true
            return
        }

        if purchaseManager.isLoading {
            Task {
                await purchaseManager.loadProducts()
                await MainActor.run {
                    purchaseSelectedProduct()
                }
            }
            return
        }

        let productToPurchase: Product?
        if let product = selectedProduct {
            productToPurchase = product
        } else if let productID = selectedProductID {
            productToPurchase = purchaseManager.products.first(where: { $0.id == productID })

            if productToPurchase == nil {
                Task {
                    await purchaseManager.loadProducts()
                    await MainActor.run {
                        if let product = purchaseManager.products.first(where: { $0.id == productID }) {
                            selectedProduct = product
                            purchaseSelectedProduct()
                        } else {
                            errorMessage = String(localized: "Product is currently unavailable. Please try again later.")
                            showError = true
                        }
                    }
                }
                return
            }
        } else {
            errorMessage = String(localized: "Please select a subscription option")
            showError = true
            return
        }

        guard let product = productToPurchase else {
            errorMessage = String(localized: "Product is currently unavailable. Please try again later.")
            showError = true
            return
        }
        
        isPurchasing = true
        
        Task { @MainActor in
            defer {
                isPurchasing = false
            }
            
            do {
                try await purchaseManager.purchase(product)
                
                // Check if purchase was successful
                if purchaseManager.hasUnlimitedAccess {
                    isPurchasing = false
                    dismiss()
                } else {
                    // Purchase completed but access not yet granted (might be pending)
                    // The transaction listener will handle this
                    errorMessage = String(localized: "Purchase completed. Your subscription will be activated shortly.")
                    showError = true
                }
            } catch let error as PurchaseError {
                // Handle specific purchase errors
                switch error {
                case .userCancelled:
                    // Don't show error for user cancellation
                    return
                case .pending:
                    // Pending is not an error - show info message
                    errorMessage = String(localized: "Your purchase is pending approval. You'll be notified when it's complete.")
                    showError = true
                default:
                    errorMessage = error.errorDescription ?? String(localized: "An error occurred during purchase. Please try again.")
                    showError = true
                }
            } catch {
                // Handle other errors
                errorMessage = error.localizedDescription
                if errorMessage.isEmpty {
                    errorMessage = String(localized: "An unexpected error occurred. Please try again.")
                }
                showError = true
            }
        }
    }
}

#Preview {
    SubscriptionView()
}
