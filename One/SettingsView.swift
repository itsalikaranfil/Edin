//
//  SettingsView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI
import CoreData
import StoreKit
import CloudKit
import UIKit

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var alarmAuthorization = AlarmAuthorizationStore.shared
    @StateObject private var cloudSyncStatus = CloudSyncStatus.shared
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
    
    @State private var showSubscription = false
    @State private var showManageSubscriptions = false
    
    private var appAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appAppearanceRaw) ?? .system },
            set: { newValue in
                appAppearanceRaw = newValue.rawValue
                AppAppearanceStore.save(newValue)
            }
        )
    }

    private var premiumCardState: SettingsPremiumCardState {
        if !purchaseManager.hasFinishedInitialEntitlementCheck {
            return .loading
        }
        if let plan = purchaseManager.activeSubscriptionPlan {
            return .active(plan: plan)
        }
        return .upgrade(eligibleForTrial: purchaseManager.isEligibleForFreeTrial)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Custom Header
                    HStack {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color.primaryText)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Compact Upgrade / Active Subscription (hidden for lifetime)
                    if !purchaseManager.hasLifetimePurchase {
                        SettingsPremiumCard(
                            state: premiumCardState,
                            onUpgrade: {
                                Haptics.light()
                                showSubscription = true
                            },
                            onManage: {
                                Haptics.light()
                                showManageSubscriptions = true
                            }
                        )
                        .padding(.horizontal)
                    }
                    
                    // Settings Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Settings")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.body)
                                    .foregroundColor(Color.primaryText)
                                    .frame(width: 24)

                                Text("Appearance")
                                    .font(.body)
                                    .foregroundColor(Color.primaryText)

                                Spacer()
                            }

                            Picker("Appearance", selection: appAppearance) {
                                ForEach(AppAppearance.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .font(.body)
                                .foregroundColor(Color.primaryText)
                                .frame(width: 24)
                            
                            Text("Notifications")
                                .font(.body)
                                .foregroundColor(Color.primaryText)
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { notificationManager.authorizationStatus == .authorized },
                                set: { _ in }
                            ))
                            .labelsHidden()
                            .tint(.green)
                            .disabled(true)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if notificationManager.authorizationStatus != .authorized,
                               let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .padding(.vertical, 4)

                        HStack(spacing: 12) {
                            Image(systemName: "alarm.fill")
                                .font(.body)
                                .foregroundColor(Color.primaryText)
                                .frame(width: 24)

                            Text("Alarms")
                                .font(.body)
                                .foregroundColor(Color.primaryText)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { alarmAuthorization.isAuthorized },
                                set: { _ in }
                            ))
                            .labelsHidden()
                            .tint(.green)
                            .disabled(true)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            alarmAuthorization.handlePermissionTap()
                        }
                        .padding(.vertical, 4)

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "icloud.fill")
                                .font(.body)
                                .foregroundColor(Color.primaryText)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("iCloud Sync")
                                    .font(.body)
                                    .foregroundColor(Color.primaryText)

                                Text(cloudSyncStatus.statusDescription)
                                    .font(.caption)
                                    .foregroundColor(cloudSyncStatus.accountStatus == .available ? .gray : .orange)

                                if cloudSyncStatus.isExportInProgress {
                                    Text("Syncing…")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }

                                if !cloudSyncStatus.isUsingCloudKit {
                                    Text("Local only — not syncing")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                    Text("Data stays on this device. Deleting the app will erase your items; they won’t restore from iCloud until sync is working.")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if let lastError = cloudSyncStatus.lastError {
                                    Text("Sync error: \(lastError)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if let lastSyncDescription = cloudSyncStatus.lastSyncDescription {
                                    Text(lastSyncDescription)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)
                    
                    // About Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                        
                        Link(destination: URL(string: "https://x.com/iamalikaranfil")!) {
                            AboutLinkRow(
                                icon: "xmark",
                                title: "Follow me on X"
                            )
                        }
                        
                        Link(destination: LegalURLs.termsOfUse) {
                            AboutLinkRow(
                                icon: "link",
                                title: "Terms of Service"
                            )
                        }
                        
                        Link(destination: LegalURLs.privacyPolicy) {
                            AboutLinkRow(
                                icon: "link",
                                title: "Privacy Policy"
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color.screenBackground)
            .paywallSheet(isPresented: $showSubscription)
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .onChange(of: showManageSubscriptions) { _, isPresented in
                if !isPresented {
                    Task {
                        await purchaseManager.refreshAfterManageSubscriptions()
                    }
                }
            }
            .onChange(of: scenePhase) { oldValue, newValue in
                if newValue == .active {
                    Task {
                        await notificationManager.checkAuthorizationStatus()
                        alarmAuthorization.refresh()
                        await cloudSyncStatus.refresh()
                        if purchaseManager.hasFinishedInitialEntitlementCheck {
                            await purchaseManager.loadProducts()
                            await purchaseManager.updatePurchasedProducts()
                        }
                    }
                }
            }
            .onAppear {
                AppAppearanceStore.syncStandardToAppGroup()
                Task {
                    await notificationManager.checkAuthorizationStatus()
                    alarmAuthorization.refresh()
                    await purchaseManager.loadProducts()
                    if purchaseManager.hasFinishedInitialEntitlementCheck {
                        await purchaseManager.updatePurchasedProducts()
                    }
                    await cloudSyncStatus.refresh()
                }
            }
        }
    }
}

struct AboutLinkRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(Color.primaryText)
                .frame(width: 24)
            
            Text(LocalizedStringKey(title))
                .font(.body)
                .foregroundColor(Color.primaryText)
            
            Spacer()
            
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

