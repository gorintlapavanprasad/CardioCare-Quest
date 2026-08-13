import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// DailyLogHooks - saves everyday health logs: BP, exercise, meals, meds, trivia.
//
// Games and dashboard screens both save through here so the data always has
// the same shape. Each log writes to several docs in one batch (detail, daily
// summary, user counters, permanent events row). All goes through OfflineQueue
// so it works offline.
abstract class DailyLogHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Today's date as "YYYY-MM-DD" in local time, used to group logs by day.
  static String _today() => DateTime.now().toIso8601String().split('T')[0];

  // Save a blood-pressure reading. Gives 50 points.
  // Watch/phone vitals go through HealthHooks.logSnapshot instead,
  // so the "ask for BP once a day" limit doesn't block vitals collection.
  static Future<void> logBP({
    required String uid,
    required int systolic,
    required int diastolic,
    required int mood,
    String? sessionId,
    String? gameId,
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
          if (sessionId != null) 'sessionId': sessionId,
          if (gameId != null) 'gameId': gameId,
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
          if (sessionId != null) 'sessionId': sessionId,
          if (gameId != null) 'gameId': gameId,
        },
      ),
    ]);
  }

  // Save an exercise entry (activity + minutes). Gives 50 points.
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

  // Save a meal entry (notes, rating, photo flag). Gives 25 points.
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

  // Save a medication check-in. 20 points if taken, 5 if not.
  // Pass the current streak; the new streak is calculated here.
  static Future<void> logMedication({
    required String uid,
    required bool taken,
    required int currentStreak,
  }) {
    if (uid.isEmpty) return Future.value();
    final today = _today();
    // Taken: streak +1. Missed: reset to 0.
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

  // Save a trivia result. Points added = pointsEarned.
  // "answers" is optional: per-question breakdown for researchers.
  static Future<void> logTrivia({
    required String uid,
    required int score,
    required int totalQuestions,
    required int pointsEarned,
    List<Map<String, dynamic>>? answers,
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
          if (answers != null) 'answers': answers,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }
}
