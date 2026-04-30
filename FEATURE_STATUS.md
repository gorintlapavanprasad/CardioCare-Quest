# CardioCare Quest — Feature Status

A quick reference for developers picking up the project. Lists only **shipping features** — pages that render real UI and persist data. "Coming soon" stubs are intentionally excluded to keep this clean (see `lib/features/dashboard/screens/coming_soon_screen.dart` for the placeholder).

---

## Authentication

| Feature | File | Saves to |
|---|---|---|
| QR / Barcode login (offline-friendly) | `lib/features/auth/login_screen.dart` | reads `userData/{uid}`; caches `participantId` in `flutter_secure_storage` |
| Splash + Face ID re-entry | `lib/features/splash/splash_screen.dart` | local only |
| Auth state provider | `lib/features/auth/auth_provider.dart` | session glue; baseline-survey writes go through `OfflineQueue` |

Each demo user gets a unique UID, encoded as a QR code, and scanned at login. After first login, biometrics (Face ID / fingerprint) gate re-entry locally. The cached `participantId` lets a participant re-enter the app while offline (login screen falls back to the cached id when `firebase_auth` cannot reach the server).

The previous PIN creation, onboarding, and quest-complete onboarding screens have been removed.

---

## Dashboard (Home Tab)

`lib/features/dashboard/screens/home_tab.dart`

Reads `userData/{uid}` via `UserDataProvider` for:

- Header (name, **points**)
- Latest BP reading + average
- Daily BP quest completion check
- Family snippet (aggregated steps)
- Game catalog row + Health Pillar grid
- **Sync badge** (`lib/core/widgets/sync_badge.dart`) — combines `LoggingService` and `OfflineQueue` pending counts into one indicator. Three states: green `cloud_done` (synced), green spinner (syncing), amber `cloud_off` (pending). Long-press triggers a manual sync.

No writes from this screen — it's the orchestrator.

---

## Hooks library (`lib/core/hooks/`)

All persistent writes from feature screens and Twine games go through the
hooks library. See `lib/core/hooks/README.md` for the full API.

| Module | Purpose |
|---|---|
| `DailyLogHooks` | BP / exercise / meal / medication / trivia day-logs (used by all 5 dashboard logging screens). |
| `MovementHooks` | GPS-quest writes (used by `TwineGameHost`). |
| `SurveyHooks` | Questionnaire / survey response writes (used by `TwineQuestionnaireHost`). |
| `ProfileHooks` | User-profile field updates. |
| `PointsHooks` | Optimistic in-memory updates on `UserDataProvider`. |
| `TelemetryHooks` | `events/{uuid}` event rows via `LoggingService`. |

Every write is enqueued through `OfflineQueue` first (Hive-backed) and replayed to Firestore when online — the app is fully usable offline.

---

## Daily logging screens

All five screens use `DailyLogHooks` directly (1-line write call) plus `PointsHooks.applyIncrements / applySets` for optimistic UI.

| Screen | File | Hook | Sub-collection |
|---|---|---|---|
| BP | `lib/features/blood_pressure/bp_log_screen.dart` | `DailyLogHooks.logBP` | `userData/{uid}/dailyLogs/{date}/bpReadings/{auto}` |
| Exercise | `lib/features/exercise_log/exercise_log_screen.dart` | `DailyLogHooks.logExercise` | `userData/{uid}/dailyLogs/{date}/exercises/{auto}` |
| Meal | `lib/features/games/dash_diet_game/diet_log_screen.dart` | `DailyLogHooks.logMeal` | `userData/{uid}/dailyLogs/{date}/meals/{auto}` |
| Medication | `lib/features/medication_reminder/medication_reminder_screen.dart` | `DailyLogHooks.logMedication` | (summary fields on `dailyLogs/{date}` doc; lifetime streak on `userData/{uid}`) |
| BP Trivia | `lib/features/games/bingo_bash/bp_trivia_screen.dart` | `DailyLogHooks.logTrivia` | (event-only; awards points) |

Each hook fans out to: per-entry sub-doc, daily-log summary doc, lifetime counters on `userData/{uid}`, and an immutable `events/{uuid}` row — all in a single atomic batch through `OfflineQueue`. Multiple entries per day no longer overwrite (sub-collection pattern).

---

## Games

### Game Catalog
`lib/features/dashboard/screens/game_catalog_screen.dart`

2-column grid of game tiles. Pulls catalog metadata from `lib/features/games/game_stories.dart`. Routes to:

- `dog_quest` → `DogQuestGame`
- `salt_sludge` → `SaltSludgeGame`
- `control_daily_checkin` → `ControlGame`
- everything else → `ComingSoonScreen`

### Generic Twine hosts (`lib/core/widgets/`)

| Host | File | Purpose |
|---|---|---|
| `TwineGameHost` | `twine_game_host.dart` | Movement-style Twine games. Handles WebView, GPS stream, accuracy filter, periodic `pushPing`, watchdog Timer, race-safe end-game with two-layer tombstone defense, resume validation, exit-confirm dialog, lifecycle telemetry. |
| `TwineQuestionnaireHost` | `twine_questionnaire_host.dart` | Non-movement Twine pages (control game, surveys, education). Same `FlutterBridge` JS channel and `ccq_bridge.js` shim, but no GPS / no movement writes. Submissions land in `surveys/{surveyId}/responses/{auto}` via `SurveyHooks`. |

The Twine ↔ Flutter bridge shim is `assets/game/ccq_bridge.js` (exposes `window.CCQ.startTracking / setBuddyName / saveState / finishQuest / goHome / telemetry / submitResponse`).

### Active games

| Game | Wrapper | HTML | Host | Persists to |
|---|---|---|---|---|
| Dog Walking | `lib/features/games/dog_quest.dart` | `assets/game/dog_quest.html` | `TwineGameHost` | `Movement Data`, `data_points`, `userData/{uid}/gameStates/dog_quest` |
| Salt Sludge | `lib/features/games/salt_sludge.dart` | `assets/game/salt_sludge.html` | `TwineGameHost` | `Movement Data`, `data_points`, `userData/{uid}/gameStates/salt_sludge` |
| Daily Check-In *(control)* | `lib/features/games/control_game.dart` | `assets/game/control_game.html` | `TwineQuestionnaireHost` | `surveys/control_daily_checkin/responses/{auto}`, `events/{auto}` |

Movement games share a single per-walk Firestore footprint (4 docs per periodic write, 4 docs per end-game batch) — see `MovementHooks.pushPing` / `endSession` for the full schema.

The Daily Check-In is the **control condition** for the comparison arm of the study (work-plan goal #8). Intentionally minimalist — no animation, no gamification, no GPS.

---

## Health Pillars (the 6-tile grid on home)

All six tiles route to live screens.

| # | Tile | File | Writes |
|---|---|---|---|
| 1 | Heart | `lib/features/statistics/heart_statistics_screen.dart` | none (chart streams `userData/{uid}/dailyLogs`) |
| 2 | Movement | `lib/features/exercise_log/exercise_log_screen.dart` | `DailyLogHooks.logExercise` |
| 3 | Plate | `lib/features/games/dash_diet_game/diet_log_screen.dart` | `DailyLogHooks.logMeal` |
| 4 | Education | `lib/features/education/health_education_screen.dart` | none (static content) |
| 5 | Medicine | `lib/features/medication_reminder/medication_reminder_screen.dart` | `DailyLogHooks.logMedication` |
| 6 | Family | `lib/features/family_circle/family_circle_screen.dart` | none (read-only stream) |

> ⚠️ Despite living in the `dash_diet_game/` folder, the Plate screen is the **working DASH-style meal logger** — NOT the coming-soon "DASH Diet Game" listed in the catalog. Don't confuse them.

---

## Firestore Schema (used in production code)

Mirrors the `netguage_firebase_structure.txt` reference architecture.

| Collection | Path | Purpose |
|---|---|---|
| `userData` | `/userData/{uid}` | Profile + lifetime aggregates (`points`, `totalSessions`, `measurementsTaken`, last-readings, `medicationStreak`) |
| `userData/{uid}/dailyLogs` | sub | Per-day summary doc with `last*` fields + `daily*Count` counters |
| `userData/{uid}/dailyLogs/{date}/bpReadings` | sub-sub | One doc per BP reading |
| `userData/{uid}/dailyLogs/{date}/exercises` | sub-sub | One doc per exercise entry |
| `userData/{uid}/dailyLogs/{date}/meals` | sub-sub | One doc per meal entry |
| `userData/{uid}/gameStates` | sub | Per-game resume state + `lastCompletedSessionId` tombstone |
| `Movement Data` | `/Movement Data/{sessionId}` | Per-session walk metadata |
| `Movement Data/{sessionId}/LocationData` | sub | GPS points |
| `Movement Data/{sessionId}/CheckData` | sub | Completion event checkpoints |
| `data_points` | `/data_points/{auto}` | Global geospatial heatmap feed |
| `events` | `/events/{auto}` | Telemetry / analytics events for every meaningful user action |
| `surveys/{surveyId}/responses` | sub | One doc per questionnaire submission |

Path constants live in `lib/core/constants/firestore_paths.dart`. Every screen uses these constants — never hardcode strings.

---

## Cross-cutting infrastructure

- **`lib/core/services/offline_queue.dart`** — generic Hive-backed write queue. `PendingOp.{set, update, delete}` with `OfflineFieldValue.{nowTimestamp, increment, delete, geopoint}`. 15s safety-net retry timer. All hooks write through this.
- **`lib/core/services/activity_logs.dart`** — `LoggingService`. Hive `event_queue` box for `events/{uuid}` rows. `pendingCount` + `isSyncing` `ValueNotifier`s drive the dashboard sync badge.
- **`lib/core/widgets/sync_badge.dart`** — dashboard sync indicator (combines both queue counts).
- **`lib/core/providers/user_data_manager.dart`** — `UserDataProvider`. Adds `applyLocalIncrements` / `applyLocalSets` for optimistic UI (avoids a 10s Firestore-cache fallback wait when offline).
- **`lib/core/services/session_manager.dart`** — tracks "current game" for telemetry context.
- **`lib/core/services/location_service.dart`** — `LocationDispatcher.stream`, a single broadcast position stream.
- **Firestore offline persistence** — `lib/main.dart` enables `CACHE_SIZE_UNLIMITED`. Combined with `OfflineQueue`, the app survives airplane mode + cold start without losing writes.

---

## Build & deploy notes

- **Android**: `flutter build apk --release` — currently signed with debug keys (`android/app/build.gradle.kts`); replace with a release keystore before Play Store.
- **iOS**: requires `cd ios && pod install` + Xcode signing. Deployment target is iOS 14.0. Info.plist has all required permission strings (Camera, Photo Library, Face ID, Location When-In-Use / Always, Background Modes).
- **CI**: `.github/workflows/build.yml` runs unsigned iOS + debug-keys Android build on every push to `main`. Artifacts available for 7 days.
- **Firestore**: `firestore.indexes.json` declares a composite index for the indexed-query variant of weekly quest count (the production code uses a non-indexed single-equality fallback).

---

## When you add a new feature

1. Add the screen file under `lib/features/<feature_name>/`.
2. **Use the hooks library** — `DailyLogHooks` for log entries, `SurveyHooks` for questionnaires, `MovementHooks` only if your screen orchestrates a movement quest outside `TwineGameHost`. Never enqueue raw `PendingOp`s if a hook covers your case.
3. Pair every durable write with `PointsHooks.applyIncrements / applySets` for optimistic UI — do **not** `await fetchUserData()` (it blocks ~10s offline).
4. Log a telemetry event via `TelemetryHooks.logEvent(...)`.
5. If the feature is a game, also add a `GameStory` entry in `lib/features/games/game_stories.dart` and route it from `game_catalog_screen.dart`.
6. New collections → add a constant to `lib/core/constants/firestore_paths.dart`.

## When you add a new Twine game

See `lib/core/hooks/README.md` § "Adding a new Twine game". Short version: drop an `.html` into `assets/game/`, register the asset in `pubspec.yaml`, and write a 30-line wrapper around `TwineGameHost` (movement) or `TwineQuestionnaireHost` (questionnaire). Everything else — offline persistence, watchdog, resume, race-safe end-game, telemetry — is handled.
