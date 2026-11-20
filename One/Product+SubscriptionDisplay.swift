//
//  Product+SubscriptionDisplay.swift
//  One
//
//  Clear title, length, and price copy for subscription IAP (Guideline 3.1.2(c)).
//

import StoreKit

extension Product {
    /// Full product title for display (matches App Store IAP name where possible).
    var oneDisplayTitle: String {
        if let pid = ProductID(rawValue: id) {
            return pid.displayName
        }
        return displayName
    }

    /// Free-trial introductory offer when present.
    var oneFreeTrialOffer: Product.SubscriptionOffer? {
        guard let offer = subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            return nil
        }
        return offer
    }

    /// User-facing trial length, e.g. "7 days".
    var oneTrialDurationText: String? {
        guard let offer = oneFreeTrialOffer else { return nil }
        let period = offer.period
        switch period.unit {
        case .day:
            return period.value == 1
                ? String(localized: "1 day")
                : String(localized: "\(period.value) days")
        case .week:
            // Present a 1-week trial as "7 days" for clearer marketing copy.
            return period.value == 1
                ? String(localized: "7 days")
                : String(localized: "\(period.value * 7) days")
        case .month:
            return period.value == 1
                ? String(localized: "1 month")
                : String(localized: "\(period.value) months")
        case .year:
            return period.value == 1
                ? String(localized: "1 year")
                : String(localized: "\(period.value) years")
        @unknown default:
            return nil
        }
    }

    /// Headline price for plan rows: annual as its monthly equivalent, others per their own period.
    var onePlanPriceLabel: String {
        guard let period = subscription?.subscriptionPeriod else { return displayPrice }
        switch (period.unit, period.value) {
        case (.year, 1):
            let perMonth = (price / 12).formatted(priceFormatStyle)
            return String(localized: "\(perMonth)/mo")
        case (.month, 1):
            return String(localized: "\(displayPrice)/mo")
        case (.week, 1), (.day, 7):
            return String(localized: "\(displayPrice)/wk")
        default:
            return "\(displayPrice)/\(oneShortPeriodLabel)"
        }
    }

    /// The amount actually billed, shown under the selected plan.
    var onePlanBillingDetail: String {
        guard let period = subscription?.subscriptionPeriod else { return onePeriodDescription }
        switch (period.unit, period.value) {
        case (.year, 1):
            return String(localized: "Billed yearly at \(displayPrice)")
        case (.month, 1):
            return String(localized: "Billed monthly at \(displayPrice)")
        case (.week, 1), (.day, 7):
            return String(localized: "Billed weekly at \(displayPrice)")
        default:
            return onePeriodDescription
        }
    }

    /// How many months of `monthly` the annual price equals, for "12 months for the price of N".
    func oneAnnualPriceInMonths(comparedTo monthly: Product) -> Int? {
        guard id == ProductID.annual.rawValue,
              monthly.id == ProductID.monthly.rawValue,
              monthly.price > 0 else {
            return nil
        }
        let months = NSDecimalNumber(decimal: price / monthly.price).doubleValue.rounded()
        guard months >= 1, months < 12 else { return nil }
        return Int(months)
    }

    /// Short period unit for compact labels ("week" / "month" / "year").
    var oneShortPeriodLabel: String {
        if let period = subscription?.subscriptionPeriod {
            switch period.unit {
            case .day:
                // StoreKit reports a P1W period as 7 days, so fold whole weeks back into weeks.
                if period.value % 7 == 0 {
                    let weeks = period.value / 7
                    return weeks == 1
                        ? String(localized: "week")
                        : String(localized: "\(weeks) weeks")
                }
                return period.value == 1
                    ? String(localized: "day")
                    : String(localized: "\(period.value) days")
            case .week:
                return period.value == 1
                    ? String(localized: "week")
                    : String(localized: "\(period.value) weeks")
            case .month:
                return period.value == 1
                    ? String(localized: "month")
                    : String(localized: "\(period.value) months")
            case .year:
                return period.value == 1
                    ? String(localized: "year")
                    : String(localized: "\(period.value) years")
            @unknown default: break
            }
        }
        if id.contains("weekly") { return String(localized: "week") }
        if id.contains("monthly") { return String(localized: "month") }
        if id.contains("annual") { return String(localized: "year") }
        return ""
    }

    /// Percent saved vs paying monthly for a year. Nil when not meaningful.
    func oneAnnualSavingsPercent(comparedTo monthly: Product) -> Int? {
        guard id == ProductID.annual.rawValue,
              monthly.id == ProductID.monthly.rawValue else {
            return nil
        }
        let yearlyIfMonthly = monthly.price * Decimal(12)
        guard yearlyIfMonthly > 0, yearlyIfMonthly > price else { return nil }
        let saved = yearlyIfMonthly - price
        let percent = (saved / yearlyIfMonthly) * Decimal(100)
        // NSDecimalNumber.intValue returns garbage for long repeating decimals (e.g. 16.666…).
        let rounded = Int(NSDecimalNumber(decimal: percent).doubleValue.rounded(.down))
        return rounded > 0 ? rounded : nil
    }

    /// Subscription length and billing unit.
    var onePeriodDescription: String {
        if let period = subscription?.subscriptionPeriod {
            switch period.unit {
            case .day:
                // StoreKit reports a P1W period as 7 days, so describe whole weeks as weekly.
                if period.value % 7 == 0 {
                    let weeks = period.value / 7
                    return weeks == 1
                        ? String(localized: "1 week subscription, auto-renewing. Billed weekly.")
                        : String(localized: "Auto-renewing every \(weeks) weeks.")
                }
                return period.value == 1
                    ? String(localized: "Auto-renewing every day.")
                    : String(localized: "Auto-renewing every \(period.value) days.")
            case .week:
                return period.value == 1
                    ? String(localized: "1 week subscription, auto-renewing. Billed weekly.")
                    : String(localized: "Auto-renewing every \(period.value) weeks.")
            case .month:
                return period.value == 1
                    ? String(localized: "1 month subscription, auto-renewing. Billed monthly.")
                    : String(localized: "\(period.value) months per period, auto-renewing.")
            case .year:
                return period.value == 1
                    ? String(localized: "1 year subscription, auto-renewing. Billed annually.")
                    : String(localized: "\(period.value) years per period, auto-renewing.")
            @unknown default:
                return String(localized: "Auto-renewing subscription.")
            }
        }
        if id.contains("weekly") {
            return String(localized: "1 week subscription, auto-renewing. Billed weekly.")
        }
        if id.contains("monthly") {
            return String(localized: "1 month subscription, auto-renewing. Billed monthly.")
        }
        if id.contains("annual") {
            return String(localized: "1 year subscription, auto-renewing. Billed annually.")
        }
        return ""
    }
}
