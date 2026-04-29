import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

/// Hook helpers for the four daily research-grade log types: blood pressure,
/// exercise, meal, and medication. Plus trivia (game-style quiz) since it
/// also produces a points + event payload.
///
/// Why these exist as hooks: any future Twine game can choose to also log a
/// BP reading or exercise minute count via the same path the dashboard's
/// dedicated screens use. This guarantees identical Firestore shape across
/// entry points.
///
/// Storage shape per log type:
///   userData/{uid}/dailyLogs/{date}                — summary doc (last X)
///   userData/{uid}/dailyLogs/{date}/bpReadings/{auto}
///   userData/{uid}/dailyLogs/{date}/exercises/{auto}
///   userData/{uid}/dailyLogs/{date}/meals/{auto}
///   userData/{uid}                                 — lifetime counters
///   events/{eventUuid}                             — immutable event row
///
/// All writes batch atomically through OfflineQueue.
///
/// JS-bridge equivalent: not exposed via the standard Twine bridge yet — if
/// future games need to log a BP reading from inside the game, add a
/// `LOG_BP` message handler in `TwineGameHost` that calls [logBP].
abstract class DailyLogHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  /// Today's date in `YYYY-MM-DD` format (device-local).
  static String _today() => DateTime.now().toIso8601String().split('T')[0];

  /// Log a blood-pressure reading. Awards 50 points. Increments
  /// `userData/{uid}.points`, `totalSessions`, `measurementsTaken`. Updates
  /// `lastSystolic` / `lastDiastolic` summary fields.
  static Future<void> logBP({
    required String uid,
    required int systolic,
    required int diastolic,
    required int mood,
  }) {
    if (uid.isEmpty) return Future.value();
    final today = _today();
    final eventId = _uuid.v4();
    final readingId = _uuid.v4();

    return _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today/'
        '${FirestorePaths.bpReadings}/$readingId',
        {
          'id': readingId,
          'systolic': systolic,
          'diastolic': diastolic,
          'mood': mood,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'date': today,
        },
      ),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today',
        {
          'date': today,
          'lastSystolic': systolic,
          'lastDiastolic': diastolic,
          'lastMood': mood,
          'lastBPTimestamp': OfflineFieldValue.nowTimestamp(),
          'dailyBPCount': OfflineFieldValue.increment(1),
        },
        merge: true,
      ),
      PendingOp.update('${FirestorePaths.userData}/$uid', {
        'points': OfflineFieldValue.increment(50),
        'totalSessions': OfflineFieldValue.increment(1),
        'measurementsTaken': OfflineFieldValue.increment(1),
        'lastSystolic': systolic,
        'lastDiastolic': diastolic,
        'lastLogDate': today,
        'lastBPLogDate': today,
      }),
      PendingOp.set(
        '${FirestorePaths.events}/$eventId',
        {
          'id': eventId,
          'userId': uid,
          'event': 'bp_reading_logged',
          'systolic': systolic,
          'diastolic': diastolic,
          'mood': mood,
          'bpReadingId': readingId,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }

  /// Log an exercise activity. Awards 50 points.
  static Future<void> logExercise({
    required String uid,
    required String activity,
    required int minutes,
  }) {
    if (uid.isEmpty) return Future.value();
    final today = _today();
    final eventId = _uuid.v4();
    final exerciseEntryId = _uuid.v4();

    return _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today/'
        '${FirestorePaths.exercises}/$exerciseEntryId',
        {
          'id': exerciseEntryId,
          'activity': activity,
          'minutes': minutes,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'date': today,
        },
      ),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today',
        {
          'date': today,
          'lastExerciseActivity': activity,
          'lastExerciseMinutes': minutes,
          'lastExerciseTimestamp': OfflineFieldValue.nowTimestamp(),
          'dailyExerciseMinutes': OfflineFieldValue.increment(minutes),
          'dailyExerciseCount': OfflineFieldValue.increment(1),
        },
        merge: true,
      ),
      PendingOp.update('${FirestorePaths.userData}/$uid', {
        'points': OfflineFieldValue.increment(50),
        'exercisesLogged': OfflineFieldValue.increment(1),
        'totalExerciseMinutes': OfflineFieldValue.increment(minutes),
        'lastLogDate': today,
      }),
      PendingOp.set(
        '${FirestorePaths.events}/$eventId',
        {
          'id': eventId,
          'userId': uid,
          'event': 'exercise_logged',
          'activity': activity,
          'durationMinutes': minutes,
          'exerciseEntryId': exerciseEntryId,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }

  /// Log a meal entry. Awards 25 points.
  static Future<void> logMeal({
    required String uid,
    required String mealNotes,
    required int mealRating,
    required bool hasMealPhoto,
  }) {
    if (uid.isEmpty) return Future.value();
    final today = _today();
    final eventId = _uuid.v4();
    final mealEntryId = _uuid.v4();

    return _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today/'
        '${FirestorePaths.meals}/$mealEntryId',
        {
          'id': mealEntryId,
          'mealNotes': mealNotes,
          'mealRating': mealRating,
          'hasMealPhoto': hasMealPhoto,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'date': today,
        },
      ),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today',
        {
          'date': today,
          'lastMealNotes': mealNotes,
          'lastMealRating': mealRating,
          'lastMealHasPhoto': hasMealPhoto,
          'lastMealTimestamp': OfflineFieldValue.nowTimestamp(),
          'dailyMealCount': OfflineFieldValue.increment(1),
        },
        merge: true,
      ),
      PendingOp.update('${FirestorePaths.userData}/$uid', {
        'points': OfflineFieldValue.increment(25),
        'mealsLogged': OfflineFieldValue.increment(1),
        'lastLogDate': today,
      }),
      PendingOp.set(
        '${FirestorePaths.events}/$eventId',
        {
          'id': eventId,
          'userId': uid,
          'event': 'meal_logged',
          'mealRating': mealRating,
          'mealEntryId': mealEntryId,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }

  /// Log a medication check-in. Awards 20 points if `taken`, 5 otherwise.
  /// Pass the participant's CURRENT streak (the hook computes the new one).
  static Future<void> logMedication({
    required String uid,
    required bool taken,
    required int currentStreak,
  }) {
    if (uid.isEmpty) return Future.value();
    final today = _today();
    final newStreak = taken ? currentStreak + 1 : 0;
    final eventId = _uuid.v4();

    return _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today',
        {
          'medicationTaken': taken,
          'medicationTimestamp': OfflineFieldValue.nowTimestamp(),
          'date': today,
        },
        merge: true,
      ),
      PendingOp.update('${FirestorePaths.userData}/$uid', {
        'points': OfflineFieldValue.increment(taken ? 20 : 5),
        'medicationStreak': newStreak,
        'lastLogDate': today,
      }),
      PendingOp.set(
        '${FirestorePaths.events}/$eventId',
        {
          'id': eventId,
          'userId': uid,
          'event': 'medication_logged',
          'taken': taken,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }

  /// Log a trivia / mini-game completion. Awards arbitrary points.
  static Future<void> logTrivia({
    required String uid,
    required int score,
    required int totalQuestions,
    required int pointsEarned,
  }) {
    if (uid.isEmpty) return Future.value();
    final eventId = _uuid.v4();

    return _queue.enqueueBatch([
      PendingOp.update('${FirestorePaths.userData}/$uid', {
        'points': OfflineFieldValue.increment(pointsEarned),
      }),
      PendingOp.set(
        '${FirestorePaths.events}/$eventId',
        {
          'id': eventId,
          'userId': uid,
          'event': 'trivia_completed',
          'score': score,
          'totalQuestions': totalQuestions,
          'pointsEarned': pointsEarned,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }
}
