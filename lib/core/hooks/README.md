# CardioCare Quest — Hooks Library

A documented, testable surface that any feature screen or Twine HTML game
can call to read/write user data without re-implementing offline plumbing,
optimistic UI, or Firestore schema details.

```
import 'package:cardio_care_quest/core/hooks/hooks.dart';
```

Every hook:
- Writes through [`OfflineQueue`](../services/offline_queue.dart), so it's
  durable to Hive first and replays to Firestore on reconnect (survives
  airplane mode + app kill).
- Uses `OfflineFieldValue.nowTimestamp()` for event-time timestamps
  (resolved at queue time, not server time on sync).
- Returns `Future<void>` that resolves once the write is queued — does NOT
  wait for Firestore confirmation. Safe to fire-and-forget.
- Is a pure top-level abstract class with static methods. No instances.

## Modules

### `TelemetryHooks` — analytics events
```dart
TelemetryHooks.logEvent(
  'salt_sludge_quest_started',
  parameters: {'difficulty': 'medium'},
  phone: userData.phone,
);
```
Wraps `LoggingService`. Events queue to Hive `event_queue` and sync as
`events/{eventUuid}` docs. Drives the dashboard sync badge.

### `PointsHooks` — optimistic UI updates
```dart
PointsHooks.applyIncrements(context, {'points': 50, 'totalSessions': 1});
PointsHooks.applySets(context, {'lastSystolic': 120, 'lastDiastolic': 80});
```
Mutates the in-memory `UserDataProvider` map and notifies listeners so the
dashboard reflects the change before Firestore sync. Pair with the durable
`MovementHooks`/`DailyLogHooks` write — never use alone.

### `ProfileHooks` — user-profile field updates
```dart
await ProfileHooks.updateBuddyName(uid, 'Rex');
await ProfileHooks.setFields(uid, {'heightCm': 170, 'weightKg': 65});
```
Targets `userData/{uid}`. Standard `SET_DOG_NAME` bridge messages from a
Twine page route into `updateBuddyName` automatically.

### `MovementHooks` — GPS quests (used by `TwineGameHost`)
| Hook | Purpose |
|---|---|
| `generateSessionId(gameId)` | Mint a stable session ID. |
| `pushPing(...)` | Periodic GPS write (4 docs in one batch). |
| `endSession(...)` | Quest completed; increment stats, write CheckData, clear ongoing fields. |
| `saveOngoingState(...)` | Player exited mid-walk; persist progress so resume works. |
| `saveGameStateJson(...)` | Persist Twine's serialized state JSON. |
| `fetchOngoingState(uid, gameId)` | Read `gameStates/{gameId}` for resume decision. |
| `fetchWeeklyQuestCount(uid, gameId)` | Count completed quests this ISO week. |

You don't normally call these directly — `TwineGameHost` orchestrates them.
Call them yourself only if you're building a game-flow that doesn't fit
the host pattern.

### `DailyLogHooks` — research-grade health logs
```dart
await DailyLogHooks.logBP(uid: '...', systolic: 120, diastolic: 80, mood: 3);
await DailyLogHooks.logExercise(uid: '...', activity: 'Walking', minutes: 30);
await DailyLogHooks.logMeal(
  uid: '...', mealNotes: 'Salad', mealRating: 4, hasMealPhoto: false);
await DailyLogHooks.logMedication(uid: '...', taken: true, currentStreak: 3);
await DailyLogHooks.logTrivia(
  uid: '...', score: 4, totalQuestions: 5, pointsEarned: 40);
```

Each hook writes to a sub-collection of `userData/{uid}/dailyLogs/{date}`
so multiple entries per day don't overwrite. The daily-log doc itself
keeps `last*` summary fields + `daily*Count` counters. Lifetime user stats
(`points`, `totalSessions`, etc.) increment on `userData/{uid}`. An
immutable `events/{uuid}` row records each entry.

The dedicated dashboard screens (BP log, Exercise log, etc.) currently
inline this logic; future refactors can swap them to use these hooks for
identical behavior.

## Twine ↔ Flutter bridge

Drop-in JS shim: `assets/game/ccq_bridge.js`. Include in your Twine HTML:

```html
<script src="ccq_bridge.js"></script>
```

(The Flutter WebView resolves relative paths against the loaded asset's
directory, so this works as long as `ccq_bridge.js` is in `assets/game/`.)

### Calls FROM Twine TO Flutter (via the shim)

| JS call | Bridge message | Host action |
|---|---|---|
| `CCQ.startTracking(distance)` | `START_TRACKING` | Begin GPS tracking; resume if matches existing session. |
| `CCQ.setBuddyName(name)` | `SET_DOG_NAME` | Persist via `ProfileHooks.updateBuddyName`. |
| `CCQ.saveState(stateJson)` | `SAVE_STATE` | Persist via `MovementHooks.saveGameStateJson`. |
| `CCQ.finishQuest()` | `FINISH_QUEST_DATA` | Run end-game flow. |
| `CCQ.goHome()` | `GO_HOME` | Pop back to dashboard. |
| `CCQ.telemetry(name, params)` | `TELEMETRY` | Custom event — needs a `onCustomBridgeMessage` handler in your `TwineGameHost` that routes to `TelemetryHooks.logEvent`. |

### Calls FROM Flutter TO Twine (the host expects these globals)

Define these in your HTML — they're called by `TwineGameHost`:

| Function | Purpose |
|---|---|
| `setBuddyName(name)` | Restore the saved companion name on launch. |
| `setWeeklyQuestCount(count)` | Update a "X quests completed this week" UI. |
| `updateGameProgress(walked, target)` | Drive the progress bar mid-walk. |
| `resumeWalk(walked, target)` | Switch to the active-walk page on resume. |
| `onQuestFinished(pointsGained)` | Show your completion scene. |
| `hydrateState(jsonString)` | Restore your Twine state on launch. |

All are optional — the host calls each only if `typeof X === 'function'`.

## Adding a new Twine game

1. Author your `.html` (Twine compile or hand-rolled). Include the bridge
   shim and any of the global functions above that you want to support.
2. Add the file to `pubspec.yaml`:
   ```yaml
   assets:
     - assets/game/your_game.html
   ```
3. Wrap it in `TwineGameHost`:
   ```dart
   class YourGame extends StatelessWidget {
     const YourGame({super.key});
     @override
     Widget build(BuildContext context) {
       return TwineGameHost(
         gameId: 'your_game',
         gameTitle: 'Your Game',
         htmlAsset: 'assets/game/your_game.html',
         targetDistance: 500,
       );
     }
   }
   ```
4. Hook it into the game catalog (`lib/features/games/game_stories.dart`)
   and route to it from the catalog screen.

That's it. Offline persistence, watchdog Timer, resume logic, race-safe
end-game, telemetry — all handled.

## Adding a custom bridge message

If your game needs a message type beyond the standard set:

```dart
TwineGameHost(
  gameId: 'trivia_x',
  ...,
  onCustomBridgeMessage: (data, host) async {
    if (data['type'] == 'SUBMIT_ANSWER') {
      await DailyLogHooks.logTrivia(
        uid: yourUid,
        score: data['score'],
        totalQuestions: data['totalQuestions'],
        pointsEarned: data['pointsEarned'],
      );
      return true; // claim the message — don't fall through
    }
    return false; // let the host's default switch handle it (or ignore)
  },
);
```

## Testing offline behavior

See `OFFLINE_TEST_PLAN.md` at the repo root for the full test plan. Short
version: airplane mode ON, run a quest end-to-end, watch the sync badge
climb, airplane mode OFF, confirm the badge drains and Firestore reflects
all writes.
