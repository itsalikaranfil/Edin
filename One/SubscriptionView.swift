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
        return String(localized: "Unlock the full Edin experience, all in one place.")
    }

    private var headlineTitle: String {
        if !purchaseManager.hasLifetimePurchase,
           let annual = annualProduct, let monthly = monthlyProduct,
           let months = annual.oneAnnualPriceInMonths(comparedTo: monthly) {
            return String(localized: "Get 12 months for the price of \(months)")
        }
        return String(localized: "Plan your days without limits")
    }
    
    private var primaryButtonTitle: String {
        if isPurchasing { return String(localized: "Processing...") }
        if showTrialCTA {
            return String(localized: "Start My Free Trial")
        }
        if isManaging { return String(localized: "Upgrade") }
        return String(localized: "Continue")
    }

    private var ctaCaption: String? {
        guard canSubscribe, !isPurchasing else { return nil }
        if showTrialCTA, let product = selectedResolvedProduct, let trial = product.oneTrialDurationText {
            return String(
                localized: "\(trial) free, then \(product.displayPrice)/\(product.oneShortPeriodLabel). Cancel anytime."
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
            Color.paywallBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                        .padding(.top, 44)

                    if purchaseManager.hasLifetimePurchase {
                        Text("You already own Edin+ Lifetime. No further purchase is needed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        benefitsSection
                        plansSection
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
        .environment(\.colorScheme, .dark)
        .presentationBackground(Color.paywallBackground)
        .background(SquareSheetBottomCorners())
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

    private var heroSection: some View {
        VStack(spacing: 10) {
            PaywallHeadline(
                savingsPercent: purchaseManager.hasLifetimePurchase ? nil : annualSavingsPercent,
                isLoading: orderedProducts.isEmpty && !purchaseManager.hasLifetimePurchase
            )
                .padding(.bottom, 4)

            Text(headlineTitle)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(taglineText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            PaywallGlow()
                .padding(.horizontal, -20)
                .offset(y: -44)
        }
    }

    private var benefitsSection: some View {
        VStack(spacing: 18) {
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
        .padding(.horizontal, 4)
    }

    private var plansSection: some View {
        VStack(spacing: 4) {
            if purchaseManager.isLoading && orderedProducts.isEmpty {
                ProgressView()
                    .padding()
            } else if !orderedProducts.isEmpty {
                // Annual first: it is the default pick and carries the savings and trial.
                ForEach(orderedProducts.reversed(), id: \.id) { product in
                    PaywallPlanOption(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        isCurrent: product.id == currentPlanID,
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
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
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
                        .foregroundStyle(Color.premiumRedBright)
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
                colors: [Color.paywallBackground.opacity(0), Color.paywallBackground],
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
            .tint(.white)
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

extension View {
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            SubscriptionView()
        }
    }
}

/// Keeps the hosting sheet's top corners rounded but squares its bottom corners so the
/// sheet reaches the display edges. UIKit re-applies corner masks during presentation and
/// rotation, so they're reapplied on every layout pass.
private struct SquareSheetBottomCorners: UIViewRepresentable {
    func makeUIView(context: Context) -> CornerMaskingView {
        CornerMaskingView()
    }

    func updateUIView(_ uiView: CornerMaskingView, context: Context) {
        uiView.applyMask()
    }

    final class CornerMaskingView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyMask()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyMask()
            DispatchQueue.main.async { [weak self] in self?.applyMask() }
        }

        func applyMask() {
            var view = superview
            while let current = view, !(current is UIWindow) {
                if current.layer.cornerRadius > 0 {
                    current.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                }
                view = current.superview
            }
        }
    }
}

#Preview {
    SubscriptionView()
}
