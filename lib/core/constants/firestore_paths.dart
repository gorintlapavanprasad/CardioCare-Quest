// FirestorePaths - the names of our cloud database folders (collections).
//
// Firestore stores data in named "collections". We keep every name here as a
// constant so we spell them the same way everywhere and can't make typos.
class FirestorePaths {
  /// Research events only - one immutable row per real study action
  /// (bp_reading_logged, exercise_logged, meal_logged, medication_logged,
  /// trivia_completed, survey_response_submitted, game_quest_completed).
  /// App/operational telemetry lives in [telemetry] instead, so this
  /// collection stays a clean, researcher-facing record.
  static const events = 'events';

  /// App/operational telemetry (game_opened, game_closed, webview_error,
  /// permission_denied, etc.). Kept OUT of [events] so researchers analysing
  /// study outcomes aren't wading through UI noise. Written only by
  /// LoggingService (TelemetryHooks); nothing in-app reads it.
  static const telemetry = 'telemetry';

  /// Cross-user geo heatmap points, one per GPS ping. Stays a TOP-LEVEL
  /// collection (not nested under a participant) because it's read by a
  /// GeoCollectionReference radius query that aggregates every participant's
  /// points for the community map. Each doc carries `userId` for attribution.
  static const movementPoints = 'movementPoints';

  /// Per-participant walking sessions. Nested under the participant
  /// (`userData/{uid}/movementData/{sessionId}`) so all of one person's data
  /// lives in one place and deleting a participant removes their walks too.
  static const movementData = 'movementData';
  static const userData = 'userData';
  static const surveys = 'surveys';
  static const responses = 'responses';

  static const locationData = 'locationData';
  static const checkData = 'checkData';
  static const gameStates = 'gameStates';
  static const dailyLogs = 'dailyLogs';

  /// Sub-collections of an individual `dailyLogs/{date}` doc. One doc per
  /// entry so participants can log multiple in a single day without
  /// overwriting prior ones. The daily-log doc itself only carries summary
  /// fields (last reading, daily totals).
  static const exercises = 'exercises';
  static const bpReadings = 'bpReadings';
  static const meals = 'meals';

  static const baselineSurvey = 'baseline_survey';

  /// Sub-collection on `userData/{uid}/` holding the participant's
  /// "Design Your Own Game" creations. Each doc is a custom personal
  /// goal (title, category, points reward) that the participant taps
  /// to complete; completions go through PointsHooks + TelemetryHooks
  /// the same as catalog games.
  static const customGames = 'customGames';

  /// Sub-collection on `userData/{uid}/` holding per-action game
  /// activity logs from hub-and-spoke games (Vascular Village's
  /// per-quest credits, etc.). Distinct from `surveys/` which is
  /// reserved for actual questionnaire submissions - putting game
  /// data under surveys conflates two research artefacts. Each doc:
  /// `{gameId, questId, pointsEarned, sessionId?, data?, createdAt}`.
  static const gameLogs = 'gameLogs';

  /// Single doc on `userData/{uid}/preferences/favorites` holding the
  /// participant's starred game IDs as an array. Stored on Firestore
  /// (not SharedPreferences) so favourites follow the participant
  /// across devices when they log in with the same Unique ID.
  static const preferences = 'preferences';
  static const favorites = 'favorites';

  /// Root collection grouping a co-play session (participant + caregiver).
  /// `pairedSessions/{pairedSessionId}` carries session metadata + joint
  /// settings; every write made during the session (events, movement,
  /// surveys) also carries a `pairedSessionId` correlation field so the
  /// whole session can be reconstructed. A thin mirror lives at
  /// `userData/{uid}/pairedSessions/{id}` for per-participant queries.
  static const pairedSessions = 'pairedSessions';

  /// Sub-collections of `pairedSessions/{id}` for the caregiver view:
  /// `helpMarkers` - one doc each time the caregiver marks that help was
  /// given (with the game/step context); `notes` - free-text caregiver
  /// observations, one doc per entry (never overwritten).
  static const helpMarkers = 'helpMarkers';
  static const notes = 'notes';
}

