// The names of the folders (collections) in our cloud database.
// Keeping them all here means we always spell them the same way.
class FirestorePaths {
  // Real study actions, one row each: blood pressure logged, meal logged,
  // a game finished, and so on. This is the clean data researchers look at.
  static const events = 'events';

  // Behind-the-scenes app activity (a game opened, an error popped up).
  // Kept separate from events so it doesn't clutter the research data.
  static const telemetry = 'telemetry';

  // Every GPS point from everyone's walks, used to draw the community map.
  // Stays at the top level because the map reads all users' points at once.
  static const movementPoints = 'movementPoints';

  // One person's walking sessions, kept under their own user folder.
  static const movementData = 'movementData';
  static const userData = 'userData';
  static const surveys = 'surveys';
  static const responses = 'responses';

  static const locationData = 'locationData';
  static const checkData = 'checkData';
  static const gameStates = 'gameStates';
  static const dailyLogs = 'dailyLogs';

  // Entries inside a single day's log. One doc per entry so someone can log
  // several meals or workouts in a day without overwriting the last one.
  static const exercises = 'exercises';
  static const bpReadings = 'bpReadings';
  static const meals = 'meals';

  static const baselineSurvey = 'baseline_survey';

  // The person's own "design your own game" goals.
  static const customGames = 'customGames';

  // Per-action logs from games that record progress step by step.
  static const gameLogs = 'gameLogs';

  // The person's starred games. Saved in the cloud so they follow them
  // to any device they log in on.
  static const preferences = 'preferences';
  static const favorites = 'favorites';

  // A shared play session between a participant and their caregiver.
  static const pairedSessions = 'pairedSessions';

  // Caregiver notes and "I helped here" markers within a shared session.
  static const helpMarkers = 'helpMarkers';
  static const notes = 'notes';
}
