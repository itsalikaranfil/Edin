//
//  PaywallStyle.swift
//  One
//
//  Shared Edin+ paywall and Settings premium card primitives.
//

import SwiftUI
import StoreKit

extension LinearGradient {
    /// Edin+ brand gradient used by the paywall CTA, badges, and selection rings.
    static let paywallBrand = LinearGradient(
        colors: [Color.paywallViolet, Color.paywallPink, Color.paywallOrange],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let paywallBrandDiagonal = LinearGradient(
        colors: [Color.paywallViolet, Color.paywallPink, Color.paywallOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Background

/// Slowly drifting aurora that fades into black, so content stays readable below the hero.
struct PaywallAuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = {
        let top: [Color] = [.paywallViolet, .paywallPink, .paywallOrange]
        let glow: [Color] = [
            Color(red: 0.20, green: 0.09, blue: 0.42),
            Color(red: 0.42, green: 0.07, blue: 0.30),
            Color(red: 0.38, green: 0.14, blue: 0.05)
        ]
        let fade: [Color] = [
            Color(red: 0.04, green: 0.03, blue: 0.07),
            Color(red: 0.05, green: 0.02, blue: 0.06),
            Color(red: 0.04, green: 0.03, blue: 0.05)
        ]
        let bottom: [Color] = [.black, .black, .black]
        return top + glow + fade + bottom
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : Float(context.date.timeIntervalSinceReferenceDate)
            MeshGradient(width: 3, height: 4, points: Self.points(at: time), colors: Self.colors)
        }
        .ignoresSafeArea()
    }

    private static func points(at time: Float) -> [SIMD2<Float>] {
        let slow = time * 0.35
        let topMidX: Float = 0.5 + 0.12 * sin(slow)
        let leftY: Float = 0.26 + 0.04 * sin(slow * 1.3)
        let centerX: Float = 0.5 + 0.16 * cos(slow * 0.9)
        let centerY: Float = 0.30 + 0.05 * sin(slow)
        let rightY: Float = 0.24 + 0.04 * cos(slow * 1.1)
        let lowMidX: Float = 0.5 + 0.10 * sin(slow * 0.7)

        var points: [SIMD2<Float>] = []
        points.append(SIMD2(0, 0))
        points.append(SIMD2(topMidX, 0))
        points.append(SIMD2(1, 0))
        points.append(SIMD2(0, leftY))
        points.append(SIMD2(centerX, centerY))
        points.append(SIMD2(1, rightY))
        points.append(SIMD2(0, 0.55))
        points.append(SIMD2(lowMidX, 0.58))
        points.append(SIMD2(1, 0.55))
        points.append(SIMD2(0, 1))
        points.append(SIMD2(0.5, 1))
        points.append(SIMD2(1, 1))
        return points
    }
}

// MARK: - Hero

struct PaywallHero: View {
    let tagline: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var haloRotation: Double = 0

    private let logoSize: CGFloat = 104

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.paywallViolet, .paywallPink, .paywallOrange, .paywallViolet],
                            center: .center
                        )
                    )
                    .frame(width: logoSize * 1.5, height: logoSize * 1.5)
                    .blur(radius: 36)
                    .opacity(0.9)
                    .rotationEffect(.degrees(haloRotation))

                Image("logoOne")
                    .resizable()
                    .scaledToFill()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.225, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: logoSize * 0.225, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 14)
            }
            .frame(height: logoSize * 1.5)
            .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text("Edin")
                    .foregroundStyle(.white)
                Text("+")
                    .foregroundStyle(LinearGradient.paywallBrand)
            }
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            .accessibilityElement(children: .combine)

            Text(tagline)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                haloRotation = 360
            }
        }
    }
}

// MARK: - Benefits

struct PaywallBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient.paywallBrandDiagonal)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Badges

struct PaywallBadge: View {
    enum Style {
        case gradient
        case subtle
    }

    let text: String
    var style: Style = .gradient

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                switch style {
                case .gradient:
                    Capsule().fill(LinearGradient.paywallBrand)
                case .subtle:
                    Capsule().fill(Color.white.opacity(0.14))
                }
            }
    }
}

// MARK: - Plans

struct PaywallPlanOption: View {
    let product: Product
    let isSelected: Bool
    var isCurrent: Bool = false
    var showTrialBadge: Bool = false
    var savingsPercent: Int? = nil
    let onTap: () -> Void

    private var title: String {
        ProductID(rawValue: product.id)?.shortName ?? product.displayName
    }

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                selectionRing

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let savingsPercent {
                            PaywallBadge(text: String(localized: "SAVE \(savingsPercent)%"))
                        }

                        if isCurrent {
                            PaywallBadge(text: String(localized: "CURRENT"), style: .subtle)
                        }
                    }

                    Text(product.oneBillingSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if showTrialBadge, let trial = product.oneTrialDurationText {
                        Text("\(trial) free, then auto-renews")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LinearGradient.paywallBrand)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(product.displayPrice)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("/\(product.oneShortPeriodLabel)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(LinearGradient.paywallBrand) : AnyShapeStyle(Color.white.opacity(0.10)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PaywallPressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionRing: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(isSelected ? 0 : 0.3), lineWidth: 1.5)
            if isSelected {
                Circle()
                    .fill(LinearGradient.paywallBrandDiagonal)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Trial timeline

/// Dated trial sequence (today, cancel window, first charge) so the free trial reads as safe.
struct PaywallTrialTimeline: View {
    let trialDurationText: String
    let trialEndDate: Date
    let renewalPriceText: String

    private var endDateText: String {
        trialEndDate.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How your free trial works")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 18) {
                step(
                    icon: "lock.open.fill",
                    title: String(localized: "Today"),
                    detail: String(localized: "Unlock everything in Edin+ for \(trialDurationText), free.")
                )
                step(
                    icon: "bell.fill",
                    title: String(localized: "Before \(endDateText)"),
                    detail: String(localized: "Cancel anytime in Settings and you won’t be charged.")
                )
                step(
                    icon: "crown.fill",
                    title: endDateText,
                    detail: String(localized: "Your plan starts at \(renewalPriceText).")
                )
            }
            .background(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.paywallViolet, .paywallPink, .paywallOrange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .padding(.leading, 14.5)
                    .opacity(0.7)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func step(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LinearGradient.paywallBrandDiagonal))
                .background(Circle().fill(Color.black).padding(-3))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CTA

struct PaywallCTAButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -0.6

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                if isEnabled {
                    Capsule().fill(LinearGradient.paywallBrand)
                } else {
                    Capsule().fill(Color.white.opacity(0.12))
                }
            }
            .overlay {
                if isEnabled && !reduceMotion {
                    shimmer
                }
            }
            .clipShape(Capsule())
            .shadow(color: isEnabled ? Color.paywallPink.opacity(0.5) : .clear, radius: 20, x: 0, y: 8)
        }
        .buttonStyle(PaywallPressStyle())
        .disabled(!isEnabled)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.4).delay(0.8).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.4
            }
        }
    }

    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.38), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.3)
            .rotationEffect(.degrees(18))
            .offset(x: geo.size.width * shimmerPhase)
        }
        .allowsHitTesting(false)
    }
}

struct PaywallPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Settings card

enum SettingsPremiumCardState {
    case loading
    case upgrade(eligibleForTrial: Bool)
    case active(plan: ProductID)
}

struct SettingsPremiumCard: View {
    let state: SettingsPremiumCardState
    let onUpgrade: () -> Void
    let onManage: () -> Void

    var body: some View {
        Group {
            switch state {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .frame(height: 96)

            case .upgrade(let eligibleForTrial):
                VStack(alignment: .leading, spacing: 16) {
                    Text("Edin+")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(
                        eligibleForTrial
                            ? String(localized: "Try everything free for 7 days, then keep it all.")
                            : String(localized: "Unlock unlimited reminders, events and habits.")
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        benefitChip("infinity", "Unlimited")
                        benefitChip("square.grid.2x2.fill", "Widgets")
                        benefitChip("icloud.fill", "Sync")
                    }

                    Button(action: onUpgrade) {
                        HStack(spacing: 6) {
                            Text(
                                eligibleForTrial
                                    ? String(localized: "Start Free Trial")
                                    : String(localized: "Upgrade to Edin+")
                            )
                            .font(.system(size: 16, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(Color.premiumRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)

            case .active(let plan):
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        glyph(systemName: "checkmark.seal.fill")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("You are subscribed to \(plan.shortName)")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Spacer(minLength: 8)
                    }

                    Button(action: onManage) {
                        Text("Manage")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                            .overlay(
                                Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
        .background(Color.premiumRed)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.premiumRed.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    private func glyph(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white.opacity(0.22)))
    }

    private func benefitChip(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.18)))
    }
}
