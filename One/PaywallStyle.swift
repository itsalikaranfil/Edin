//
//  PaywallStyle.swift
//  One
//
//  Shared Edin+ paywall and Settings premium card primitives.
//

import SwiftUI
import StoreKit

// MARK: - Hero

/// Logo, title, and tagline. A soft spotlight lifts the logo off the page in both appearances.
struct PaywallHero: View {
    let tagline: String

    private let logoSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 16) {
            Image("logoOne")
                .resizable()
                .scaledToFill()
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.225, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: logoSize * 0.225, style: .continuous)
                        .strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
                .background(
                    Circle()
                        .fill(Color.primaryText.opacity(0.06))
                        .frame(width: logoSize * 2.2, height: logoSize * 2.2)
                        .blur(radius: 30)
                )
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Edin+")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.primaryText)

                Text(tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
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
                .foregroundStyle(Color.primaryText)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.pillBackground))

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Badges

struct PaywallBadge: View {
    enum Style {
        case solid
        case subtle
    }

    let text: String
    var style: Style = .solid

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(style == .solid ? Color.screenBackground : Color.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(style == .solid ? Color.primaryText : Color.pillBackground)
            )
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
                selectionIndicator

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
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
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if showTrialBadge, let trial = product.oneTrialDurationText {
                        Text("\(trial) free, then auto-renews")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(product.displayPrice)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.primaryText)
                    Text("/\(product.oneShortPeriodLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.appBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.primaryText : Color.primaryText.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PaywallPressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primaryText.opacity(isSelected ? 0 : 0.25), lineWidth: 1.5)
            if isSelected {
                Circle()
                    .fill(Color.primaryText)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.screenBackground)
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
                .foregroundStyle(Color.primaryText)

            VStack(alignment: .leading, spacing: 18) {
                step(
                    icon: "lock.open.fill",
                    title: String(localized: "Today"),
                    detail: String(localized: "Unlock everything in Edin+ for \(trialDurationText), free.")
                )
                step(
                    icon: "calendar",
                    title: String(localized: "Before \(endDateText)"),
                    detail: String(localized: "Cancel anytime in Settings and you won’t be charged.")
                )
                step(
                    icon: "checkmark",
                    title: endDateText,
                    detail: String(localized: "Your plan starts at \(renewalPriceText).")
                )
            }
            .background(alignment: .leading) {
                Rectangle()
                    .fill(Color.primaryText.opacity(0.12))
                    .frame(width: 2)
                    .padding(.vertical, 16)
                    .padding(.leading, 15)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.appBackground)
        )
    }

    private func step(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.screenBackground)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primaryText))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CTA

/// Solid, inverted capsule (black in Light, white in Dark).
struct PaywallCTAButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(Color.screenBackground)
                        .scaleEffect(0.85)
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isEnabled ? Color.screenBackground : Color.primaryText.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule().fill(isEnabled ? Color.primaryText : Color.pillBackground)
            )
            .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(PaywallPressStyle())
        .disabled(!isEnabled)
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
