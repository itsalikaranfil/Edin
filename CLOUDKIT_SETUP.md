# Core Data + CloudKit Setup (Fix Error 134060)

Error **134060** ("Core Data model incompatibility") with `NSPersistentCloudKitContainer` usually means the **CloudKit schema** doesn’t match your Core Data model, or the schema was never created. Follow these steps in order.

---

## 1. Apple Developer Portal

1. Go to [developer.apple.com](https://developer.apple.com) → **Account** → **Certificates, Identifiers & Profiles**.
2. **Identifiers** → select your app’s **App ID** (e.g. `com.ali.OneApp` or your bundle ID).
3. Enable **iCloud** and, if listed, **CloudKit**.
4. Under iCloud, ensure the container **iCloud.com.ali.OneApp** is selected (or create it with **+**).
5. **Identifiers** → **iCloud Containers** → confirm **iCloud.com.ali.OneApp** exists. Create it if missing.
6. Save.

---

## 2. Xcode Capabilities

1. Open the project in Xcode.
2. Select the **One** target → **Signing & Capabilities**.
3. Click **+ Capability** and add **iCloud** if it’s not there.
4. Enable **iCloud** and **CloudKit**.
5. Under **Containers**, add or select **iCloud.com.ali.OneApp** (must match the identifier in code and portal).
6. Ensure **Signing** uses the same Team that owns the App ID and container.

---

## 3. Reset CloudKit Development Schema (Critical for 134060)

If the app has already run with CloudKit, the schema in the cloud may be wrong or out of date. Reset it so the app can export a fresh schema.

### Where to find the reset option

Apple has changed the CloudKit UI over time. Try these in order:

**Option A — iCloud CloudKit Console (current)**

1. Go to [https://icloud.developer.apple.com](https://icloud.developer.apple.com) and sign in.
2. In the left sidebar, click **Containers** and select **iCloud.com.ali.OneApp**.
3. Look for:
   - A **Schema** tab or **Schema** in the left sidebar → then look for **Reset**, **Reset to Development**, or **Clear Development Data** (button or link, sometimes in a **⋯** or **Actions** menu).
   - A **Development** / **Production** environment switcher at the top → switch to **Development**, then look for a **Reset** or **Reset Development** option near it.
   - **Settings** or a gear icon for the container → reset may be under there.
4. If you see **Deploy Schema** or **Save Changes**, the reset is often on the same page or in a dropdown next to it.

**Option B — Apple Developer portal (older path)**

1. Go to [developer.apple.com](https://developer.apple.com) → **Account** → sign in.
2. Open **Certificates, Identifiers & Profiles**.
3. In the left sidebar, look for **CloudKit** or **Resources → CloudKit** (or a link that opens the CloudKit Dashboard).
4. Open your container **iCloud.com.ali.OneApp** → **Schema** or **Development** → look for **Reset to Development** or **Reset Development Environment**.

**If you still can’t find “Reset to Development”**

- The option may be named **Reset**, **Clear development data**, or **Reset development schema**.
- It only appears when the **Development** environment is selected (not Production).
- If your container is new and has never had a schema deployed, you may not see a reset option; in that case skip to step 4 (delete app, clean, run) and let the app create the schema.

**Workaround: use a new container**

If reset isn’t available or doesn’t fix 134060:

1. In [developer.apple.com](https://developer.apple.com) → **Identifiers** → **iCloud Containers** → **+** to create a new container, e.g. **iCloud.com.ali.OneApp.v2**.
2. Add this container to your App ID (iCloud capability) and in Xcode capabilities.
3. In the app code (e.g. `Persistence.swift`), change the container identifier from `iCloud.com.ali.OneApp` to `iCloud.com.ali.OneApp.v2`.
4. Delete the app, clean build, and run. The new container has no schema yet, so the app can create it cleanly.

---

## 4. Clean Local Data and Run Again

1. **Delete the app** from the simulator or device (so the local Core Data store and any cached CloudKit state are removed).
2. In Xcode: **Product** → **Clean Build Folder** (⇧⌘K).
3. Build and run (**⌘R**).

On first launch the app will:

- Create a new local store.
- Export the Core Data model to CloudKit (schema initialization).
- Use **iCloud.com.ali.OneApp** for sync.

If 134060 still appears after these steps, check:

- The container ID in code (`iCloud.com.ali.OneApp`) matches Xcode and the developer portal exactly.
- The App ID has iCloud + CloudKit and the correct container.
- You really reset the **development** schema for **iCloud.com.ali.OneApp** in the CloudKit Console.

---

## 5. Optional: Initialize Schema from Code (Development)

The app can call `initializeCloudKitSchema(options:completionHandler:)` once after the store loads so the schema is pushed to CloudKit. This is already done in development when the CloudKit store loads successfully. After the schema is deployed, you can rely on automatic schema handling; the one-time call is mainly for first-time setup or after model changes.

---

## 6. TestFlight / Production (required for reinstall restore)

Debug builds talk to the CloudKit **Development** environment. **TestFlight and App Store** builds use **Production**.

Deleting the app wipes the local Core Data store (Application Support). Items only come back after reinstall if they were previously uploaded to the **Production** private database for **iCloud.com.ali.OneApp**.

### Deploy schema to Production

1. Run a Debug build once so Development has a current schema (see steps 3–4 if needed). Debug calls `initializeCloudKitSchema`, which creates record types for **all** Core Data entities — including newer ones such as **Alarm**.
2. Open [CloudKit Console](https://icloud.developer.apple.com) → container **iCloud.com.ali.OneApp**.
3. Confirm **Development** shows your Core Data record types: **CD_Event, CD_Reminder, CD_Habit, CD_Folder, CD_Alarm** (names may appear without the `CD_` prefix depending on Console UI).
4. Use **Deploy Schema** (or equivalent) to promote Development → **Production**.
5. After any Core Data model change that adds/renames fields or entities (especially **Alarm**), deploy to Production again **before** shipping a new TestFlight build that depends on sync. TestFlight/App Store builds **cannot** create new Production record types; missing `CD_Alarm` causes Alarm exports to fail and can block mixed batches that also contain events/reminders.

### Verify before delete/reinstall tests

1. Install the TestFlight build; sign in with the same iCloud Apple ID you will use after reinstall.
2. Open **Settings** → **iCloud Sync**:
   - Must **not** say “Local only — not syncing” (that means data is device-only and will be lost on delete).
   - Account should be **Available**.
   - Must **not** show a sync error about schema (deploy Production schema if it does).
3. Create a test item (including an **alarm**) and wait until **Syncing…** clears and **Last synced** updates. Local save success alone does not mean CloudKit has the records yet.
4. Delete the app → reinstall from TestFlight → the item should reappear. Alarms also need AlarmKit permission on the new device; the app reschedules system alarms after CloudKit import.

If Settings shows local-only or a sync error **before** you delete the app, Production sync is not working—fix schema deploy / account / 134060 before testing restore.

---

## Summary Checklist

- [ ] Developer portal: App ID has iCloud + CloudKit; container **iCloud.com.ali.OneApp** exists and is linked.
- [ ] Xcode: iCloud capability with CloudKit; container **iCloud.com.ali.OneApp** selected; correct Team.
- [ ] CloudKit Console: **Reset to Development** for **iCloud.com.ali.OneApp** (when fixing 134060 in Development).
- [ ] Delete app, clean build, run again (Development).
- [ ] CloudKit Console: **Deploy Schema** Development → **Production** before TestFlight restore tests. Confirm Production includes **CD_Alarm** (and Habit) after those entities were added.
- [ ] TestFlight Settings: iCloud Available, not “Local only”, **Last synced** updates after creating an item (wait for Syncing… to clear). No schema sync error.

After this, Core Data + CloudKit sync for events/reminders/**alarms** should work without 134060, and TestFlight delete→reinstall can restore data from Production.
