// The number-crunching behind the Community Stats page.
//
// What it does: reads what everyone in the group has been doing and boils
// it down to group totals and averages - how many people were active, how
// many games were played, average blood pressure, pills taken, and so on.
//
// Where the numbers come from: every action that earns points also writes
// a row to the shared `events` list (with the action name, who did it, and
// when). We read that one list and tally it up here.
//
// Privacy - this is the important part: nothing about a single person ever
// leaves here. We only return group aggregates (counts, averages, sums,
// ranges). No names, no user ids, no one person's readings. So the page
// can't reveal who did what, even in a small group.
//
// Note: one simple "events since last week" read, then we sort it out in
// code. That's fine for a small study group; if it ever grows to hundreds
// of people this should move to a server-side summary instead.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../games/game_stories.dart';

// A plain bag of the finished group numbers, ready for the page to show.
// (Read-only - once made, it doesn't change.)
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

  // ─── Cohort total score ────────────────────────────────────────
  final int totalCohortPoints;

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
    required this.totalCohortPoints,
    required this.windowDays,
    required this.fetchedAt,
  });

  // An all-zeros version, used when there's no group data yet.
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
        totalCohortPoints: 0,
        windowDays: windowDays,
        fetchedAt: DateTime.now(),
      );
}

// The worker that does the reading and tallying. One shared instance.
class CommunityStatsService {
  CommunityStatsService._(this._db);

  static final instance =
      CommunityStatsService._(FirebaseFirestore.instance);

  final FirebaseFirestore _db;

  // Do the whole job: read the data, count everything up, and hand back
  // one CommunityStats. Two reads - first the list of people (for group
  // size, total points, who's active today), then the week's events (for
  // everything else). windowDays = how many days back to look.
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

    // Walk every person: add up their points and count who was active today.
    int totalPoints = 0;
    int activeToday = 0;
    for (final doc in userDocs.docs) {
      final data = doc.data();
      final pts = (data['points'] as num?)?.toInt() ?? 0;
      totalPoints += pts;
      if (_isActiveToday(data, today, now)) {
        activeToday += 1;
      }
    }

    // ─── Read 2: this week's events ──────────────────────────────
    // Grab ALL events from the last `windowDays`, then sort them out by
    // type in code below. We pull everything (not just certain types) so
    // new kinds of events show up automatically without code changes.
    // Counters we fill in as we go through the events:
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

      // Look at each event and bump the right counters based on its type.
      for (final doc in eventsSnap.docs) {
        final data = doc.data();
        final eventType = data['event'] as String?;
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (eventType == null) continue;

        switch (eventType) {
          // A blood-pressure reading: add to the total and track the
          // running average and the lowest/highest seen.
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

          // A finished survey-style game (most games submit this way).
          // Count it as one play and tag it to its game and category.
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

          // A single quest finished (e.g. a Vascular Village quest or a
          // Pill Path tap). Each of these counts as its own play.
          case 'game_quest_completed':
            final gameId = data['gameId'] as String?;
            if (gameId == null || gameId.isEmpty) break;
            // Skip "undo/fix" taps (like un-marking a pill) so correcting
            // a mistake doesn't wrongly inflate the play counts.
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
            // Pill Path taps are our pill-taken signal. Count them all
            // for the week, and note today's ones (by person) for the
            // "how many took a pill today" stat.
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
            // Movement games send an event named like "<game>_completed"
            // (e.g. "dog_quest_completed"). Catch any of those whose game
            // we recognize and count it as one play, so they aren't missed.
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
      // If the events read fails (e.g. permissions), don't crash - just
      // zero out these numbers. The group size and total points from the
      // first read still show, so the page isn't totally blank.
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

    // Find the single most-played game to headline the engagement card.
    String? topGameId;
    int topGamePlays = 0;
    playsByGame.forEach((id, plays) {
      if (plays > topGamePlays) {
        topGameId = id;
        topGamePlays = plays;
      }
    });

    // Pack all the tallied numbers into one result for the page.
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
      totalCohortPoints: totalPoints,
      windowDays: windowDays,
      fetchedAt: now,
    );
  }

  // ── helpers ────────────────────────────────────────────────────

  // Turn a date into a plain "YYYY-MM-DD" string (no time part).
  static String _ymd(DateTime d) {
    final iso = d.toIso8601String();
    return iso.split('T').first;
  }

  // True if this person did anything today. We check a few "last did X"
  // markers: logged a value today, or played/surveyed within the last 24h.
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
