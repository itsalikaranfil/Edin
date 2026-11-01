//
//  PaywallStyle.swift
//  One
//
//  Shared Edin+ paywall and Settings premium card primitives.
//

import SwiftUI
import StoreKit

extension LinearGradient {
    /// Bright premium blue gradient used by the paywall CTA and Settings card.
    static let premiumGradient = LinearGradient(
        colors: [Color.premiumBlueBright, Color.premiumBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PaywallBadge: View {
    enum Style {
        case filled
        case outlined
    }

    let text: String
    var style: Style = .filled

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundColor(style == .filled ? .white : Color.premiumBlue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if style == .filled {
                    Capsule().fill(Color.premiumBlue)
                } else {
                    Capsule()
                        .strokeBorder(Color.premiumBlue.opacity(0.55), lineWidth: 1)
                        .background(Capsule().fill(Color.premiumBlue.opacity(0.1)))
                }
            }
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.premiumBlue)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.premiumBlue.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct PremiumGlowBackground: View {
    var body: some View {
        ZStack {
            Color.screenBackground
            RadialGradient(
                colors: [
                    Color.premiumBlue.opacity(0.28),
                    Color.premiumBlue.opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 320
            )
            .offset(y: -40)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct PaywallPlanCard: View {
    let product: Product
    let isSelected: Bool
    var isCurrent: Bool = false
    var showTrialBadge: Bool = false
    var savingsPercent: Int? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.oneDisplayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primaryText)
                            .lineLimit(1)

                        if showTrialBadge {
                            PaywallBadge(
                                text: String(localized: "\(product.oneTrialDurationText ?? "7 days") FREE").uppercased()
                            )
                        }

                        if let savingsPercent {
                            PaywallBadge(
                                text: String(localized: "SAVE \(savingsPercent)%"),
                                style: .outlined
                            )
                        }

                        if isCurrent {
                            PaywallBadge(text: String(localized: "CURRENT"), style: .outlined)
                        }
                    }

                    Text(product.onePeriodDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color.primaryText)
                    Text("/\(product.oneShortPeriodLabel)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(isSelected ? Color.premiumBlue : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.premiumBlue.opacity(0.12) : Color.appBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.premiumBlue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

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
                    HStack(spacing: 12) {
                        Text("Edin+")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if eligibleForTrial {
                            Text("7 DAYS FREE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.22)))
                                .overlay(
                                    Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                                )
                        }
                    }

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
                        .foregroundColor(Color.premiumBlue)
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
        .background(Color.premiumBlue)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.premiumBlue.opacity(0.3), radius: 16, x: 0, y: 8)
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
