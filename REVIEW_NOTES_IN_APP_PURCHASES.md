# App Store Connect — Review Notes for In-App Purchases

Copy the appropriate section below into the **Review Notes** or **Notes for Review** field for each product in App Store Connect.

---

## General Instructions (for all products)

**How to access the paywall:**
1. Open the app and tap the **Settings** tab (gear icon).
2. If not subscribed, tap the **Upgrade** button to open the subscription screen.
3. Alternatively, try adding a reminder or event when at the free limit — the paywall will appear.

**Sandbox testing:** Use a Sandbox Apple ID. Sign out of your Apple ID in Settings → App Store, then sign in when prompted during purchase.

**Restore purchases:** Tap "Restore purchase" at the bottom of the subscription screen.

---

## One+ Monthly (com.ali.oneapp.monthly)

**Product type:** Auto-renewable subscription (monthly)

**What it unlocks:** Unlimited reminders and events. The free tier has a limited number of items.

**Review notes:**
```
One+ Monthly is a recurring monthly subscription ($4.99/month) that unlocks unlimited reminders and events in the One calendar app.

HOW TO TEST:
1. Open app → Settings tab → tap "Upgrade"
2. Select "Monthly" and tap "Subscribe"
3. Complete purchase with Sandbox account
4. Verify: Settings shows "Active Subscription - Monthly"
5. Add reminders/events — limit should be removed

Restore: "Restore purchase" button at bottom of subscription sheet.
```

---

## One+ Annual (com.ali.oneapp.annual)

**Product type:** Auto-renewable subscription (annual)

**What it unlocks:** Same as Monthly — unlimited reminders and events. Billed yearly for a lower per-month cost.

**Review notes:**
```
One+ Annual is a recurring annual subscription ($44.99/year) that unlocks unlimited reminders and events in the One calendar app.

HOW TO TEST:
1. Open app → Settings tab → tap "Upgrade"
2. Select "Annual" and tap "Subscribe"
3. Complete purchase with Sandbox account
4. Verify: Settings shows "Active Subscription - Annual"
5. Add reminders/events — limit should be removed

Restore: "Restore purchase" button at bottom of subscription sheet.
```

---

## One+ Lifetime (com.ali.oneapp.lifetime)

**Product type:** Non-consumable (one-time purchase)

**What it unlocks:** Same as subscriptions — unlimited reminders and events, permanently. No recurring billing.

**Review notes:**
```
One+ Lifetime is a one-time purchase ($89.99) that permanently unlocks unlimited reminders and events in the One calendar app. No subscription — single payment for lifetime access.

HOW TO TEST:
1. Open app → Settings tab → tap "Upgrade"
2. Select "Lifetime" and tap "Subscribe"
3. Complete purchase with Sandbox account
4. Verify: Settings shows "Active Subscription - Lifetime"
5. Add reminders/events — limit should be removed
6. Delete app, reinstall, tap "Restore purchase" — access should persist

Restore: "Restore purchase" button at bottom of subscription sheet.
```

---

## Subscription group: One (FF081157)

If App Store Connect asks for subscription group notes:

**Review notes:**
```
Subscription group "One" contains Monthly and Annual subscriptions. Users can only have one active subscription at a time. Both provide the same benefits (unlimited reminders/events); the only difference is billing frequency.

Access: Settings → Upgrade, or when adding items at the free limit.
```
