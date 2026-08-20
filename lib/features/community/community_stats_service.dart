// Number-crunching for the Community Stats page.
// Reads everyone's events and returns group totals/averages only.
// No individual names or readings ever leave this service.
// Fine for a small study group; move to server-side if the cohort grows a lot.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../games/game_stories.dart';

// Finished group numbers, ready for the page to show. Read-only.
class CommunityStats {
  /// Number of participant `userData/{uid}` docs the service saw.
  final int cohortSize;

  /// Distinct participants with any activity recorded today.
  final int activeToday;

  /// Game completions across the cohort over [windowDays].
  /// Counts both `survey_response_submitted` (whole-game submits)
  /// and `game_quest_completed` events with `countAsCompletion: true`.
  final int playsThisWeek;

  // ─── Heart health ──────────────────────────────────────────────
  final int bpReadingsThisWeek;
  final double? avgSystolic;
  final double? avgDiastolic;
  final int? sysMin;
  final int? sysMax;
  final int? diaMin;
  final int? diaMax;

  // ─── Medication adherence ──────────────────────────────────────
  /// Pill Path "pill_taken" events over [windowDays].
  final int pillsLoggedThisWeek;
  /// Distinct participants who logged a pill today.
  final int participantsWhoTookPillToday;

  // ─── Game engagement ───────────────────────────────────────────
  final Map<GameCategory, int> playsByCategory;
  final Map<String, int> playsByGame;
  final String? topGameId;
  final int topGamePlays;

  final int windowDays;
  final DateTime fetchedAt;

  const CommunityStats({
    required this.cohortSize,
    required this.activeToday,
    required this.playsThisWeek,
    required this.bpReadingsThisWeek,
    required this.avgSystolic,
    required this.avgDiastolic,
    required this.sysMin,
    required this.sysMax,
    required this.diaMin,
    required this.diaMax,
    required this.pillsLoggedThisWeek,
    required this.participantsWhoTookPillToday,
    required this.playsByCategory,
    required this.playsByGame,
    required this.topGameId,
    required this.topGamePlays,
    required this.windowDays,
    required this.fetchedAt,
  });

  // All-zeros placeholder used before any data exists.
  factory CommunityStats.empty(int windowDays) => CommunityStats(
        cohortSize: 0,
        activeToday: 0,
        playsThisWeek: 0,
        bpReadingsThisWeek: 0,
        avgSystolic: null,
        avgDiastolic: null,
        sysMin: null,
        sysMax: null,
        diaMin: null,
        diaMax: null,
        pillsLoggedThisWeek: 0,
        participantsWhoTookPillToday: 0,
        playsByCategory: const {},
        playsByGame: const {},
        topGameId: null,
        topGamePlays: 0,
        windowDays: windowDays,
        fetchedAt: DateTime.now(),
      );
}

// Reads and tallies the group data. One shared instance.
class CommunityStatsService {
  CommunityStatsService._(this._db);

  static final instance =
      CommunityStatsService._(FirebaseFirestore.instance);

  final FirebaseFirestore _db;

  // Two Firestore reads: user list (size, active today) then
  // this week's events (games, BP, pills). windowDays = how far back to look.
  Future<CommunityStats> fetch({int windowDays = 7}) async {
    final now = DateTime.now();
    final windowStart = now.subtract(Duration(days: windowDays));
    final todayStart = DateTime(now.year, now.month, now.day);
    final today = _ymd(now);

    // ─── Read 1: userData collection ─────────────────────────────
    final userDocs = await _db.collection(FirestorePaths.userData).get();
    final cohortSize = userDocs.docs.length;
    if (cohortSize == 0) {
      return CommunityStats.empty(windowDays);
    }

    // Count who was active today.
    int activeToday = 0;
    for (final doc in userDocs.docs) {
      final data = doc.data();
      if (_isActiveToday(data, today, now)) {
        activeToday += 1;
      }
    }

    // ─── Read 2: this week's events ──────────────────────────────
    // Pull all events from the last windowDays, then tally by type below.
    int bpCount = 0;
    int sysSum = 0, diaSum = 0;
    int? sysMin, sysMax, diaMin, diaMax;
    int playsThisWeek = 0;
    int pillsLoggedThisWeek = 0;
    final pillUsersToday = <String>{};
    final playsByGame = <String, int>{};
    final playsByCategory = <GameCategory, int>{};

    try {
      final eventsSnap = await _db
          .collection(FirestorePaths.events)
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
          .get();

      for (final doc in eventsSnap.docs) {
        final data = doc.data();
        final eventType = data['event'] as String?;
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (eventType == null) continue;

        switch (eventType) {
          // BP reading: update running totals and min/max.
          case 'bp_reading_logged':
            final sys = (data['systolic'] as num?)?.toInt();
            final dia = (data['diastolic'] as num?)?.toInt();
            if (sys == null || dia == null) break;
            bpCount += 1;
            sysSum += sys;
            diaSum += dia;
            sysMin = (sysMin == null || sys < sysMin) ? sys : sysMin;
            sysMax = (sysMax == null || sys > sysMax) ? sys : sysMax;
            diaMin = (diaMin == null || dia < diaMin) ? dia : diaMin;
            diaMax = (diaMax == null || dia > diaMax) ? dia : diaMax;
            break;

          // Finished survey-style game: count as one play.
          case 'survey_response_submitted':
            final countAsCompletion =
                data['countAsCompletion'] as bool? ?? true;
            if (!countAsCompletion) break;
            final surveyId = data['surveyId'] as String?;
            if (surveyId == null || surveyId.isEmpty) break;
            playsThisWeek += 1;
            playsByGame[surveyId] = (playsByGame[surveyId] ?? 0) + 1;
            final story = GameCatalog.games[surveyId];
            if (story != null) {
              playsByCategory[story.category] =
                  (playsByCategory[story.category] ?? 0) + 1;
            }
            break;

          // Single quest finished (e.g. Pill Path tap, Vascular Village quest).
          case 'game_quest_completed':
            final gameId = data['gameId'] as String?;
            if (gameId == null || gameId.isEmpty) break;
            // Skip undo/correction taps so they don't inflate play counts.
            final questId = data['questId'] as String?;
            final innerData = data['data'] as Map<String, dynamic>?;
            final isCorrection = questId == 'pill_undone' ||
                (innerData?['correction'] == true);
            if (isCorrection) break;
            playsThisWeek += 1;
            playsByGame[gameId] = (playsByGame[gameId] ?? 0) + 1;
            final story = GameCatalog.games[gameId];
            if (story != null) {
              playsByCategory[story.category] =
                  (playsByCategory[story.category] ?? 0) + 1;
            }
            // Pill Path: count for the week and note who took one today.
            if (gameId == 'pill_path') {
              pillsLoggedThisWeek += 1;
              if (ts != null && !ts.isBefore(todayStart)) {
                final uid = data['userId'] as String?;
                if (uid != null && uid.isNotEmpty) {
                  pillUsersToday.add(uid);
                }
              }
            }
            break;

          default:
            // Catch movement game events like "dog_quest_completed" and count them.
            if (eventType.endsWith('_completed') &&
                eventType != 'game_quest_completed' &&
                eventType != 'trivia_completed') {
              final movementGameId =
                  eventType.substring(0, eventType.length - '_completed'.length);
              if (GameCatalog.games[movementGameId] != null) {
                playsThisWeek += 1;
                playsByGame[movementGameId] =
                    (playsByGame[movementGameId] ?? 0) + 1;
                final story = GameCatalog.games[movementGameId]!;
                playsByCategory[story.category] =
                    (playsByCategory[story.category] ?? 0) + 1;
              }
            }
            break;
        }
      }
    } catch (_) {
      // Events read failed (e.g. permissions). Zero these out but keep the
      // group size from read 1 so the page isn't totally blank.
      bpCount = 0;
      sysSum = 0;
      diaSum = 0;
      sysMin = sysMax = diaMin = diaMax = null;
      playsByGame.clear();
      playsByCategory.clear();
      playsThisWeek = 0;
      pillsLoggedThisWeek = 0;
      pillUsersToday.clear();
    }

    // Find the most-played game to show at the top of the engagement card.
    String? topGameId;
    int topGamePlays = 0;
    playsByGame.forEach((id, plays) {
      if (plays > topGamePlays) {
        topGameId = id;
        topGamePlays = plays;
      }
    });

    return CommunityStats(
      cohortSize: cohortSize,
      activeToday: activeToday,
      playsThisWeek: playsThisWeek,
      bpReadingsThisWeek: bpCount,
      avgSystolic: bpCount > 0 ? sysSum / bpCount : null,
      avgDiastolic: bpCount > 0 ? diaSum / bpCount : null,
      sysMin: sysMin,
      sysMax: sysMax,
      diaMin: diaMin,
      diaMax: diaMax,
      pillsLoggedThisWeek: pillsLoggedThisWeek,
      participantsWhoTookPillToday: pillUsersToday.length,
      playsByCategory: playsByCategory,
      playsByGame: playsByGame,
      topGameId: topGameId,
      topGamePlays: topGamePlays,
      windowDays: windowDays,
      fetchedAt: now,
    );
  }

  // ── helpers ────────────────────────────────────────────────────

  // Returns "YYYY-MM-DD".
  static String _ymd(DateTime d) {
    final iso = d.toIso8601String();
    return iso.split('T').first;
  }

  // True if this person logged anything today or played within the last 24h.
  static bool _isActiveToday(
    Map<String, dynamic> userData,
    String today,
    DateTime now,
  ) {
    if ((userData['lastLogDate'] as String?) == today) return true;
    if ((userData['lastBPLogDate'] as String?) == today) return true;

    final lastPlayed = userData['lastPlayedAt'];
    if (lastPlayed is Timestamp) {
      final diff = now.difference(lastPlayed.toDate());
      if (!diff.isNegative && diff.inHours < 24) return true;
    }
    final lastSurvey = userData['lastSurveyAt'];
    if (lastSurvey is Timestamp) {
      final diff = now.difference(lastSurvey.toDate());
      if (!diff.isNegative && diff.inHours < 24) return true;
    }
    return false;
  }
}
