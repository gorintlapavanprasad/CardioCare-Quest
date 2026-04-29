# Offline / Local-Storage E2E Test Plan (Strategy C)

Goal: confirm that **every research-grade write** (BP, exercise, meal,
medication, trivia, quest movement data, quest completions, surveys, profile
updates) is durably backed up locally and reaches Firebase even if the device
is offline mid-flow, killed mid-flow, or both. Workshop-grade resilience.

If any step fails, capture the device clock, the failing step, the sync badge
state, and the Firebase Console state — paste back to the assistant.

---

## Architecture summary (what changed)

| Layer | Storage | Purpose |
|---|---|---|
| Firestore SDK offline cache | App sandbox SQLite (unlimited) | First line of defense — Firestore SDK queues all writes locally and replays automatically when online. |
| `LoggingService` | Hive box `event_queue` | Telemetry events (dog_quest_opened, etc.) — same pattern netguage uses. |
| `OfflineQueue` (NEW) | Hive box `offline_write_queue` | Generic Firestore write queue. ALL research-grade writes go through it: BP, exercise, meal, medication, trivia, dog quest periodic+completion, walk buddy periodic+completion, onboarding survey, login profile, PIN, BMI, profile creation/merge. |
| `connectivity_plus` | — | Drives sync triggers on both queues. |
| `flutter_secure_storage` | Encrypted prefs | Caches `participant_id` so a returning participant can log in offline. |

**`serverTimestamp()` semantics:** has been replaced everywhere with
`OfflineFieldValue.nowTimestamp()` which captures the **device clock** at
queue time and stores it as a `Timestamp`. Research analyses get true event
time even if sync happens hours later. Where `serverTimestamp` is still needed
the queue replay can be customised.

**`FieldValue.increment(N)`** is preserved across replay — multiple offline
increments merge correctly server-side.

**`FieldValue.delete()`** is preserved across replay (used in quest cleanup).

**`GeoPoint`** is preserved across replay (location pings, completion lat/lng).

**HTML offline assets:** `dog_quest.html` no longer loads Google Fonts —
Nunito (600/700/800) is now bundled in `assets/game/fonts/`. `walk_buddy.html`
has been added to `pubspec.yaml` (it was previously not bundled at all).

---

## Pre-test setup

1. `flutter pub get`
2. Build a debug APK / install on a clean device or emulator. **Hot reload is
   not enough** for this test — do a full restart so the new singletons
   (`OfflineQueue`) are registered.
3. Sign in as a test participant **while connected to Wi-Fi**.
4. Confirm the dashboard shows the new sync badge to the LEFT of the "X pts"
   pill in the header. Idle state → green pill with "Synced".
5. Open Firebase Console in another window: Firestore → `events`, `userData`,
   `Movement Data`, `responses`. Keep it visible the whole test.
6. Note the device clock.

If you don't see the badge: confirm it's a clean install (uninstall first,
not hot-reload), and that `pubspec.yaml` was reloaded by `flutter pub get`
before build.

---

## Test 1 — Sanity (online)

1. Online: log a BP reading (sys 120, dia 80, mood 🙂).
2. Watch the badge: should briefly flip to "Syncing 1" (or higher), then back
   to green "Synced".
3. Within ~3 s, see in Firebase Console:
   - `userData/{uid}/dailyLogs/{today}` → `systolic: 120`, `diastolic: 80`,
     `mood: 3`, `timestamp` (a real Timestamp, not null).
   - `userData/{uid}` → `points` incremented +50, `lastBPLogDate: today`.
   - `events/*` → a new `bp_reading_logged` event.
4. Repeat for: Exercise (Movement → 15 min Walking), Meal (Plate → 🙂 mood),
   Medication (Medicine → I took it), Trivia (Game Catalog → BP Trivia, run
   to end).

✅ PASS criteria: every write lands in Firestore on the first try. Badge stays
near 0.

---

## Test 2 — Short offline → reconnect

1. Toggle airplane mode ON.
2. Log BP, log meal, log medication. Open dog_quest, walk a route to ~30%
   completion, exit (save and exit).
3. Badge: should show `cloud_off` and a count > 0 (probably 6+ from periodic
   GPS pings + the daily-log writes + telemetry events).
4. Tap the badge: SnackBar shows "X items waiting to sync (Y writes, Z
   events)…".
5. Toggle airplane mode OFF.
6. Within ~3 s, badge briefly shows "Syncing N", then drops to "Synced".
7. Confirm in Firebase Console:
   - All daily-log fields present.
   - `Movement Data/{sessionId}` exists with `LocationData` sub-collection
     populated.
   - `events/*` shows the `bp_reading_logged`, `meal_logged`,
     `medication_logged`, `dog_quest_opened`, `dog_quest_quest_started` etc.
   - Timestamps reflect the **time the events happened on the device**, not
     the reconnect time.

✅ PASS criteria: badge correctly counts then drains; no data lost; timestamps
reflect device clock at event time.

---

## Test 3 — Long offline (10 minutes)

1. Airplane mode ON.
2. Trigger ~20 mixed events: 1 BP, 2 exercise, 2 meals, 1 medication, 2
   trivia rounds, 1 full dog_quest completion (use Routes → loop on).
3. Wait 10 minutes with the app in foreground.
4. Badge still shows the accumulated count.
5. Airplane mode OFF.
6. Watch badge drain. Confirm everything in Firebase Console.

✅ PASS criteria: queue is stable while offline, drains cleanly on reconnect.

---

## Test 4 — Force-stop with offline data still queued (HIGH STAKES)

This is the workshop-killer test. Both queues MUST survive a process kill.

1. Airplane mode ON.
2. Log BP, log medication, complete a full dog quest. Badge should reach
   ~10+ pending.
3. Settings → Apps → CardioCare Quest → Force stop. Do NOT background; force
   stop.
4. With airplane mode still ON, relaunch the app and unlock.
5. Confirm the badge on the home screen still shows the same pending count.
   Tap it: SnackBar reflects the queue state.
6. Airplane mode OFF.
7. Badge drains to "Synced".
8. Verify in Firebase Console that all the data from before the force-stop
   landed.

✅ PASS criteria: the queue survives a process kill on both Hive boxes
(`event_queue` and `offline_write_queue`). No data lost.

❌ FAIL = the Hive flush ordering may need a tweak. Capture the badge count
before vs after kill.

---

## Test 5 — Brand-new participant, never been online (case 8)

1. Wipe the app's storage: Settings → Apps → CardioCare Quest → Storage →
   Clear data. (Or `adb shell pm clear com.nau.cardiocarequest`.)
2. Airplane mode ON.
3. Launch the app, sign up via "Join the Circle" / onboarding.

EXPECTED: onboarding will fail because `signInAnonymously()` requires a
network round-trip to Firebase Auth. There is no engineering fix for this
without setting up a federated auth solution. Workshop guidance: register all
new participants while connected to the registration-table Wi-Fi.

✅ PASS criteria for this test: the app surfaces a network error message
gracefully rather than hanging indefinitely.

---

## Test 6 — Returning participant offline (case 9)

1. While ONLINE: log in as participant ID `TEST-ID`. Confirm dashboard loads.
   The login flow now caches `TEST-ID` in `flutter_secure_storage`.
2. Force-stop the app.
3. Airplane mode ON.
4. Relaunch. Splash screen → biometric unlock.

EXPECTED: dashboard loads from Firestore offline cache. Badge shows "Synced"
(or whatever was queued). Participant can play and log.

5. Trigger a few writes. Sign out (if there's a sign-out path) or just leave
   the queue populated.
6. Airplane mode OFF. Confirm sync.

✅ PASS criteria: returning participant can log in and use the app fully
offline as long as they were online at least once for that account on this
device.

---

## Test 7 — Quest completes when GPS goes silent

This was the bug from earlier. The watchdog Timer should now catch it.

1. Online or offline, doesn't matter.
2. Open dog_quest.
3. Use Extended Controls → Routes. Choose a route shorter than the quest
   target distance (e.g. quest target 1000m, route only ~600m).
4. Play route. The progress will reach the route's max (~600m) and stop.
5. Now choose another route in the emulator that picks up where the first
   ended, and play it. Once cumulative `_distanceWalked` ≥ target, the quest
   should complete within 1.5 s — even if the route ends exactly at the
   threshold.
6. In Logcat / Debug Console, look for: `🎮 DogQuest: Watchdog triggered
   _endGame at ...`

✅ PASS criteria: completion screen shows. No "stuck at 100%".

Alternative: enable the **Repeat playback** toggle in Extended Controls so
the route loops past the threshold.

---

## Test 8 — Direct-to-Firebase write count drops to zero

Regression check. Before Strategy C, lots of writes hit Firestore directly.
After Strategy C, the only direct writes left are reads / auth.

1. Online. Log a BP reading.
2. Open Firebase Console → Firestore → events. The `bp_reading_logged`
   document should now be created with the **same UUID** as the one
   queued locally (search the Hive box `offline_write_queue` for the same
   ID).

This proves the queue's idempotency model is intact.

✅ PASS criteria: events in Firestore correspond 1:1 to queued items by ID,
with `syncedAt` reflecting the actual sync time.

---

## What to record per test

For each test, capture:
- Date/time started.
- Device + OS version.
- PASS / FAIL.
- Sync badge state at each milestone.
- If FAIL: which step, what the badge said, what was missing in Firestore,
  any logcat output mentioning `OfflineQueue`, `LoggingService`, `Firestore`,
  `Hive`.

---

## Known remaining gaps (intentional, mention if hit)

1. **Brand-new offline signup** — `signInAnonymously()` requires network.
   Mitigation: workshop SOP must register participants on Wi-Fi.
2. **Onboarding screen images** — `onboarding_screen.dart:27,33,39` loads
   three Unsplash images. They will fail offline; the screen falls back to
   the dark backdrop. Cosmetic, not functional. Bundle locally if you want
   pixel-perfect offline visuals.
3. **`fetchUserData` recursion when no doc exists offline** —
   `user_data_manager.dart:170-174` calls `createUserDocument` then recurses.
   If the user doc was never created online, the recursion will end with the
   minimal fallback object (line 178-185). Dashboard renders, but personalised
   data is missing until first sync.
4. **WriteBatch atomicity** — replays preserve atomicity *per batch* (each
   queued `PendingBatch` becomes one Firestore `WriteBatch`). Two separate
   `enqueueBatch` calls are NOT atomic with each other.
5. **Pre-existing test failure** — `test/widget_test.dart` references a
   `MyApp` class and the wrong package name. Unrelated to offline work; not
   breaking the build.

If everything passes, Strategy C is done and we can move to Goal #1 (generic
Twine host) and #2 (hooks repository).
