//
//  PaywallStyle.swift
//  One
//
//  Shared Edin+ paywall and Settings premium card primitives.
//

import SwiftUI
import StoreKit

// MARK: - Glow

/// Red light falling from the top edge: a soft bloom plus four faint white light streaks.
struct PaywallGlow: View {
    var height: CGFloat = 360
    var intensity: Double = 1

    private let streakWidths: [CGFloat] = [10, 18, 14, 8]

    var body: some View {
        ZStack(alignment: .top) {
            Ellipse()
                .fill(Color.premiumRed.opacity(0.5 * intensity))
                .frame(width: height * 1.3, height: height * 0.75)
                .blur(radius: height * 0.2)
                .offset(y: -height * 0.32)

            HStack(spacing: 0) {
                ForEach(streakWidths.indices, id: \.self) { index in
                    if index > 0 {
                        Spacer(minLength: 0)
                    }
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.07 * intensity), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: streakWidths[index])
                }
            }
            .padding(.horizontal, 14)
            .blur(radius: 4)
            .frame(height: height * 0.85, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Headline

/// Heavy rounded text with a deep red outline and a red glow.
struct PaywallGlowText: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let outline = max(size * 0.035, 1.5)
        let label = Text(verbatim: text)
            .font(.system(size: size, weight: .black, design: .rounded))

        ZStack {
            // Eight offset copies draw the outline; SwiftUI has no text stroke.
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) / 8 * 2 * .pi
                label
                    .foregroundStyle(Color.premiumRedDeep)
                    .offset(x: cos(angle) * outline, y: sin(angle) * outline)
            }
            label
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.premiumRedBright, Color.premiumRed],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .compositingGroup()
        .shadow(color: Color.premiumRed.opacity(0.6), radius: size * 0.2)
    }
}

/// Big savings figure ("30%"). While plans load it holds the space with a placeholder; the Edin+
/// wordmark only appears when there is no saving at all.
struct PaywallHeadline: View {
    let savingsPercent: Int?
    var isLoading: Bool = false

    var body: some View {
        Group {
            if let savingsPercent {
                percentFigure(savingsPercent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Save \(savingsPercent)%"))
            } else if isLoading {
                percentFigure(30)
                    .redacted(reason: .placeholder)
                    .opacity(0.35)
                    .accessibilityHidden(true)
            } else {
                PaywallGlowText(text: "Edin+", size: 72)
                    .accessibilityLabel(Text(verbatim: "Edin+"))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func percentFigure(_ percent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            PaywallGlowText(text: "\(percent)", size: 104)
            PaywallGlowText(text: "%", size: 54)
        }
    }
}

// MARK: - Benefits

struct PaywallBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Badges

struct PaywallBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}

// MARK: - Plans

/// Selected plan sits on a raised card; the others are plain rows.
struct PaywallPlanOption: View {
    let product: Product
    let isSelected: Bool
    var isCurrent: Bool = false
    let onTap: () -> Void

    private var title: String {
        ProductID(rawValue: product.id)?.shortName ?? product.displayName
    }

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: isSelected ? 19 : 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if isCurrent {
                            PaywallBadge(text: String(localized: "CURRENT"))
                        }
                    }

                    if isSelected {
                        Text(product.onePlanBillingDetail)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Text(product.onePlanPriceLabel)
                    .font(.system(size: isSelected ? 20 : 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, isSelected ? 18 : 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.07 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.06 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PaywallPressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - CTA

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
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEnabled ? Color.premiumRed : Color.white.opacity(0.1))
            )
            .shadow(color: Color.premiumRed.opacity(isEnabled ? 0.35 : 0), radius: 16, x: 0, y: 6)
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

/// Plain dark card in the paywall's palette.
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
                .frame(height: 120)

            case .upgrade(let eligibleForTrial):
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Edin+")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)

                        Text(
                            eligibleForTrial
                                ? String(localized: "Try everything free for 7 days, then keep it all.")
                                : String(localized: "Unlock unlimited reminders, events and habits.")
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onUpgrade) {
                        Text(
                            eligibleForTrial
                                ? String(localized: "Start Free Trial")
                                : String(localized: "Upgrade to Edin+")
                        )
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.premiumRed)
                        )
                    }
                    .buttonStyle(PaywallPressStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

            case .active(let plan):
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.premiumRedBright)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.07)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.displayName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("You are subscribed to \(plan.shortName)")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Spacer(minLength: 8)
                    }

                    Button(action: onManage) {
                        Text("Manage")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(PaywallPressStyle())
                }
                .padding(18)
            }
        }
        .background(Color.paywallBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}
