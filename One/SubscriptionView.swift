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
    @Environment(\.paywallDismiss) private var paywallDismiss
    @Environment(\.paywallPullDown) private var paywallPullDown
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, overscroll in
                paywallPullDown?.changed(overscroll)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                guard oldPhase == .interacting, newPhase != .interacting else { return }
                let geometry = context.geometry
                let overscroll = max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                paywallPullDown?.released(overscroll, context.velocity?.dy ?? 0)
            }
            .safeAreaInset(edge: .bottom) {
                if !purchaseManager.hasLifetimePurchase {
                    ctaSection
                }
            }

            SheetClosePill(size: 40) {
                closePaywall()
            }
            .padding(.leading, 20)
            .padding(.top, 16)
        }
        .environment(\.colorScheme, .dark)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {
                closePaywall()
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
    
    private func closePaywall() {
        if let paywallDismiss {
            paywallDismiss()
        } else {
            dismiss()
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
                    closePaywall()
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
    /// Presents the paywall as a custom sheet: top corners rounded, bottom edge square so it
    /// covers the bottom of the display. The system sheet always rounds its bottom corners.
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        modifier(PaywallSheetModifier(isPresented: isPresented))
    }
}

extension EnvironmentValues {
    @Entry var paywallDismiss: (() -> Void)?
    @Entry var paywallPullDown: PaywallPullDown?
}

/// Lets the paywall's scroll view drive the custom sheet: pulling down past the top moves
/// the sheet, and releasing far or fast enough closes it.
struct PaywallPullDown {
    var changed: (_ overscroll: CGFloat) -> Void
    var released: (_ overscroll: CGFloat, _ velocity: CGFloat) -> Void
}

private struct PaywallSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var coverPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, newValue in
                setCover(newValue)
            }
            .onChange(of: coverPresented) { _, newValue in
                if !newValue, isPresented { isPresented = false }
            }
            .onAppear {
                if isPresented { setCover(true) }
            }
            .fullScreenCover(isPresented: $coverPresented) {
                PaywallSheetContainer {
                    setCover(false)
                    isPresented = false
                }
                .presentationBackground(.clear)
            }
    }

    private func setCover(_ value: Bool) {
        guard coverPresented != value else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { coverPresented = value }
    }
}

private struct PaywallSheetContainer: View {
    let onDismissed: () -> Void

    @State private var isShown = false
    @State private var dragOffset: CGFloat = 0
    @State private var pullOffset: CGFloat = 0
    @State private var isClosing = false

    private let cornerRadius: CGFloat = 38
    private let slideAnimation = Animation.spring(response: 0.42, dampingFraction: 0.92)

    var body: some View {
        GeometryReader { proxy in
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let topGap = proxy.safeAreaInsets.top + 10

            ZStack(alignment: .top) {
                Color.black
                    .opacity(isShown ? 0.35 * dimFraction(fullHeight) : 0)
                    .ignoresSafeArea()

                SubscriptionView()
                    .environment(\.paywallDismiss, close)
                    .environment(\.paywallPullDown, pullDown)
                    .mask(alignment: .top) {
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            topTrailingRadius: cornerRadius,
                            style: .continuous
                        )
                        .padding(.bottom, -200)
                    }
                    .overlay(alignment: .top) {
                        dragHandleArea(fullHeight: fullHeight)
                    }
                    .padding(.top, topGap)
                    .offset(y: isShown ? sheetOffset : fullHeight)
            }
        }
        .onAppear {
            withAnimation(slideAnimation) { isShown = true }
        }
    }

    private func dimFraction(_ fullHeight: CGFloat) -> CGFloat {
        max(0, 1 - sheetOffset / max(fullHeight, 1))
    }

    private var sheetOffset: CGFloat {
        dragOffset + pullOffset
    }

    private var pullDown: PaywallPullDown {
        PaywallPullDown(
            changed: { overscroll in
                guard !isClosing else { return }
                pullOffset = overscroll
            },
            released: { overscroll, velocity in
                guard !isClosing else { return }
                // Overscroll is rubber-banded, so a short distance already means a long pull.
                if overscroll > 60 || (overscroll > 12 && velocity < -900) {
                    close()
                }
            }
        )
    }

    /// Drag strip along the top of the sheet; it starts right of the close button so taps reach it.
    private func dragHandleArea(fullHeight: CGFloat) -> some View {
        Color.clear
            .frame(height: 76)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.leading, 72)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let y = value.translation.height
                        dragOffset = y > 0 ? y : y / 8
                    }
                    .onEnded { value in
                        let shouldClose = value.translation.height > 140
                            || value.predictedEndTranslation.height > 360
                        if shouldClose {
                            close()
                        } else {
                            withAnimation(slideAnimation) { dragOffset = 0 }
                        }
                    }
            )
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeIn(duration: 0.25)) {
            isShown = false
        } completion: {
            onDismissed()
        }
    }
}

#Preview {
    SubscriptionView()
}
