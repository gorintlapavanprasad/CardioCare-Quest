# CardioCare Quest — Feature Status

A quick reference for developers picking up the project. Lists only **shipping features** — pages that render real UI and persist data. "Coming soon" stubs are intentionally excluded to keep this clean (see `lib/features/dashboard/screens/coming_soon_screen.dart` if you want the placeholder).

---

## Authentication & Onboarding

| Feature | File | Saves to |
|---|---|---|
| QR / Barcode login | `lib/features/auth/login_screen.dart` | reads `userData/{uid}` |
| PIN creation | `lib/features/auth/create_pin_screen.dart` | `userData/{uid}` (pin hash + signature) |
| Onboarding survey | `lib/features/onboarding/onboarding_screen.dart` | `userData/{uid}` (basicInfo, demographics) |
| Splash + Face ID re-entry | `lib/features/splash/splash_screen.dart` | local only (no Firestore write) |
| Auth state provider | `lib/features/auth/auth_provider.dart` | session glue |

Each demo user gets a unique UID, encoded as a QR code, and scanned at login. After first login, biometrics (Face ID / fingerprint) gate re-entry locally.

---

## Dashboard (Home Tab)

`lib/features/dashboard/screens/home_tab.dart`

Reads `userData/{uid}` via `UserDataProvider` and live-streams it for:
- Header (name, XP)
- Latest BP reading + average
- Daily BP quest completion check
- Family snippet (aggregated steps stream)
- Game catalog row + Health Pillar grid

No writes from this screen — it's the orchestrator.

---

## Daily Quest — Blood Pressure Logging

`lib/features/blood_pressure/bp_log_screen.dart`

User enters systolic / diastolic + mood. **One tap fans out to three writes** in a single batch:

| Path | Fields |
|---|---|
| `userData/{uid}/dailyLogs/{YYYY-MM-DD}` | `systolic`, `diastolic`, `mood`, `timestamp`, `date` |
| `userData/{uid}` (update) | `points +50`, `totalSessions +1`, `measurementsTaken +1`, `lastSystolic`, `lastDiastolic`, `lastBPLogDate`, `lastLogDate` |
| `events/{auto}` | `event: 'bp_reading_logged'`, plus payload |

**Reads (chart history):** streams the latest 7 entries from `userData/{uid}/dailyLogs` ordered by `timestamp desc`.

---

## Health Pillars (the 6-tile grid on home)

All six tiles work and route to live screens.

### 1. Heart → `lib/features/statistics/heart_statistics_screen.dart`
- **Reads only** — pulls `userData/{uid}/dailyLogs` and renders BP-over-time charts via `fl_chart`.
- No writes.

### 2. Movement → `lib/features/exercise_log/exercise_log_screen.dart`
Logs an exercise session (type + minutes). Three-write batch:

| Path | Fields |
|---|---|
| `userData/{uid}/dailyLogs/{YYYY-MM-DD}` | `exercise`, `exerciseMinutes`, `exerciseTimestamp`, ... |
| `userData/{uid}` (update) | `points +50`, `exercisesLogged +1`, `totalExerciseMinutes +N` |
| `events/{auto}` | `event: 'exercise_logged'` |

### 3. Plate → `lib/features/games/dash_diet_game/diet_log_screen.dart`
> ⚠️ Despite living in the `dash_diet_game/` folder, this is the **working DASH-style meal logger** — NOT the coming-soon "DASH Diet Game" listed in the Game Catalog. Don't confuse them.

Logs a meal (with optional photo via `image_picker`). Three-write batch:

| Path | Fields |
|---|---|
| `userData/{uid}/dailyLogs/{YYYY-MM-DD}` | `meal`, `mealTimestamp`, optional photo metadata |
| `userData/{uid}` (update) | `points +25`, `mealsLogged +1` |
| `events/{auto}` | `event: 'meal_logged'` |

### 4. Education → `lib/features/education/health_education_screen.dart`
- **Read-only static content** (no Firestore writes).
- Self-contained markdown-style hypertension education cards.

### 5. Medicine → `lib/features/medication_reminder/medication_reminder_screen.dart`
Marks medication as taken / not taken. Three-write batch:

| Path | Fields |
|---|---|
| `userData/{uid}/dailyLogs/{YYYY-MM-DD}` | `medicationTaken`, `medicationTimestamp` |
| `userData/{uid}` (update) | `points +20` (if taken) or `+5` (if not), updated streak |
| `events/{auto}` | `event: 'medication_logged'` |

Reads `userData/{uid}` to seed today's UI.

### 6. Family → `lib/features/family_circle/family_circle_screen.dart`
- **Read-only stream** of all `userData` docs to compute aggregate community steps.
- No writes.

---

## Games

### Game Catalog
`lib/features/dashboard/screens/game_catalog_screen.dart`

Square 2-column grid of game tiles. Pulls catalog metadata from `lib/features/games/game_stories.dart`.

### Active game: Dog Walking (`dog_quest`)
`lib/features/games/dog_quest.dart` + `assets/game/dog_quest.html`

Hybrid Flutter + WebView game. Most complex feature. **Heavy Firestore integration** — every active walk performs incremental writes:

| Path | Trigger | Fields |
|---|---|---|
| `Movement Data/{sessionId}` | every 5th GPS point + on `_endGame` | `sessionId`, `userId`, `game`, `created`, `endedAt`, `totalDistance`, `pointsEarned`, `dogName`/`buddyName` |
| `Movement Data/{sessionId}/LocationData/{auto}` | every 5th GPS point | `geopoint`, `geohash`, `lat`, `lng`, `datetime` |
| `Movement Data/{sessionId}/CheckData/{auto}` | on `_endGame` | `event: 'dog_quest_completed'`, location, session metadata |
| `data_points/{auto}` | every 5th GPS point | `location.geopoint`, `geohash`, `userId`, `sessionId`, `game`, `timestamp` (heatmap feed) |
| `userData/{uid}/gameStates/{game}` | every 5th GPS point | resume state: `ongoingDistance`, `ongoingTarget`, `ongoingSessionId`, `ongoingPath` |
| `userData/{uid}` (update on completion) | on `_endGame` | `points +30/+60/+100`, `totalDistance +N`, `totalSessions +1`, `distanceTraveled +N`, `measurementsTaken +1`, `lastPlayedAt` |
| `events/{auto}` | various | `dog_quest_opened`, `dog_quest_quest_started`, `dog_quest_quest_completed`, `dog_quest_closed` |

Resume logic: if user exits mid-walk and confirms "save and exit", `gameStates` carries the in-progress walk; opening the game again hydrates and resumes seamlessly.

Weekly quest count on scene 3 ("N quests completed so far this week!") queries `Movement Data` filtered by `userId == uid` (single-equality, no composite index required), then filters `game` and `endedAt >= ISO Monday 00:00` client-side.

---

## Firestore Schema (used in production code)

Mirrors the `netguage_firebase_structure.txt` reference architecture.

| Collection | Path | Purpose |
|---|---|---|
| `userData` | `/userData/{uid}` | Profile + lifetime aggregates (points, totals, last readings) |
| `userData/{uid}/dailyLogs` | sub | Per-day log per user (BP, meals, exercise, medication merged into one doc per day) |
| `userData/{uid}/gameStates` | sub | Per-game resume state (currently only `dog_quest`) |
| `Movement Data` | `/Movement Data/{sessionId}` | Per-session walk metadata |
| `Movement Data/{sessionId}/LocationData` | sub | GPS points |
| `Movement Data/{sessionId}/CheckData` | sub | Network/event checkpoints |
| `data_points` | `/data_points/{auto}` | Global geospatial heatmap feed (read by future map / community features) |
| `events` | `/events/{auto}` | Telemetry / analytics events for every meaningful user action |

Path constants live in `lib/core/constants/firestore_paths.dart`. Every screen uses these constants — never hardcode strings.

---

## Cross-cutting infrastructure

- **`lib/core/providers/user_data_manager.dart`** — `UserDataProvider` (ChangeNotifier). Single source of truth for the logged-in user's `userData` doc. Call `provider.fetchUserData()` after any write that mutates user-level fields so the dashboard refreshes.
- **`lib/core/services/activity_logs.dart`** — `LoggingService` registered via `get_it`. Use `loggingService.logEvent(name, parameters: ..., phone: ...)` to write to `events` collection.
- **`lib/core/services/session_manager.dart`** — tracks "current game" for telemetry context.
- **`lib/core/services/location_service.dart`** — `LocationDispatcher.stream` is a single broadcast position stream all games subscribe to (avoids duplicate GPS subscriptions).

---

## Build & deploy notes

- **Android**: `flutter build apk --release` — currently signed with debug keys (line 40 of `android/app/build.gradle.kts`); replace with a release keystore before Play Store.
- **iOS**: requires `cd ios && pod install` + Xcode signing setup. Deployment target is iOS 14.0 (`mobile_scanner 7.x` requirement). Info.plist has all required permission strings (Camera, Photo Library, Face ID, Location When-In-Use / Always, Background Modes).
- **CI**: `.github/workflows/build.yml` runs unsigned iOS + signed-with-debug-keys Android build on every push to `main`. Artifacts available for 7 days.
- **Firestore**: `firestore.indexes.json` declares a composite index for the indexed-query variant of weekly quest count (currently using non-indexed fallback, kept for future scale).

---

## When you add a new feature

1. Add the screen file under `lib/features/<feature_name>/`.
2. Add path constants to `lib/core/constants/firestore_paths.dart` if introducing a new collection.
3. After any write that touches user-level fields, call `Provider.of<UserDataProvider>(context, listen: false).fetchUserData()` to refresh the dashboard.
4. Log a telemetry event via `loggingService.logEvent(...)`.
5. If the feature is a game, also add a `GameStory` entry in `lib/features/games/game_stories.dart` so it appears in the catalog grid.
