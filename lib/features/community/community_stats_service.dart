// Aggregates anonymous cohort signals for the Community Statistics
// page.
//
// **Data-source contract** — see /FIRESTORE_ARCHITECTURE.md for the
// full schema. Briefly: every meaningful action that earns a
// participant points ALSO writes a row to the top-level `events`
// collection with `event`, `userId`, `timestamp`, plus event-
// specific fields. That's the canonical timeline.
//
// Earlier versions of this service queried `collectionGroup('gameLogs')`,
// which only catches Vascular Village quest credits and Pill Path
// taps — every other game (Bingo Bash, DASH Diet, Salt Sludge, Daily
// Check-In, Quiet Minute, Quiet Landscape) submits via SurveyHooks
// and never lands in gameLogs. The result was a Community Stats page
// that read all zeros even when participants had finished games.
// Rewritten to query `events` directly so all completions are
// captured.
//
// Why one query instead of three (one per metric):
//   * Top-level `events` is cheap to query by `timestamp >= window`.
//   * 7 days × 150 participants × ~10 events/day ≈ 10.5k docs worst
//     case — still fine to filter client-side. If the cohort grows
//     past ~500 participants this should be moved into a Cloud
//     Function aggregating into a single `community_stats/today` doc
//     read by the screen.
//   * Single query = single round-trip = single error path.
//
// Privacy: this is a 15-to-150-participant research dry-run, so
// individual data could deanonymise. Every value returned here is
// an aggregate (count / avg / sum / range). The page never receives
// individual userIds, names, or readings.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../games/game_stories.dart';

/// Immutable snapshot of cohort-wide signals at a point in time.
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

class CommunityStatsService {
  CommunityStatsService._(this._db);

  static final instance =
      CommunityStatsService._(FirebaseFirestore.instance);

  final FirebaseFirestore _db;

  /// Fetch a fresh aggregate snapshot.
  ///
  /// Two reads:
  ///   1. `userData` collection — cohort size + sum of `points` +
  ///      per-user "last active" markers for the active-today calc.
  ///   2. `events` collection where `timestamp >= now - windowDays` —
  ///      every metric on the page derives from this single query,
  ///      filtered client-side by `event` discriminator.
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

    // ─── Read 2: events collection over the window ───────────────
    // We don't add a `where('event', whereIn: [...])` server-side
    // because it'd lock us out of any future event types we add
    // (every new event type would require code change AND maybe an
    // index). Instead we filter client-side after a simple
    // timestamp range query — at 150 participants × ~10 events/day
    // × 7 days = 10.5k docs at worst, well within Firestore's
    // single-query budget. Move to a Cloud Function aggregator if
    // the cohort grows past ~500.
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

          case 'survey_response_submitted':
            // Whole-game submits — Bingo Bash, DASH Diet, Salt
            // Sludge, Daily Check-In, Quiet Minute, Quiet
            // Landscape, post-play survey. The `surveyId` field
            // IS the catalog game id (except `post_play_v1` which
            // is the post-play survey, intentionally not in the
            // catalog).
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

          case 'game_quest_completed':
            // Per-quest credits — Vascular Village quests, Pill
            // Path daily taps. We DON'T filter on
            // countAsCompletion here because for these games each
            // quest IS a meaningful play — the flag just controls
            // whether the user-level surveysCompleted counter
            // bumps, not whether the play "happened".
            final gameId = data['gameId'] as String?;
            if (gameId == null || gameId.isEmpty) break;
            // Skip Pill Path correction events for the engagement
            // tally — re-tapping self/helper or hitting "I haven't
            // taken it" via the Edit Today flow shouldn't inflate
            // "plays this week" or "most-played game". A correction
            // is identified by either questId='pill_undone' or by
            // data.correction === true on a re-tap. The original
            // pill_taken event for the day is kept; only the
            // correction trail is filtered out.
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
            // Pill Path is the canonical medication tracker. Each
            // tap is one pill-taken signal; filter to today for
            // the "% cohort took pill today" stat.
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
            // Movement-quest completion events use a dynamic name
            // shape `${gameId}_completed` (e.g. `dog_quest_completed`).
            // Without this branch, Dog Quest plays would be invisible
            // to the cohort engagement bars even though MovementHooks
            // writes the event row faithfully. We treat any
            // *_completed event with a known gameId as a play of that
            // game.
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
      // Firestore index missing or permissions error. The page
      // surfaces "no data yet" rather than a stack trace — the
      // userData reads above still went through, so at least the
      // cohort size + total points sections render.
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

    // Top-played game for the engagement headline.
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
      totalCohortPoints: totalPoints,
      windowDays: windowDays,
      fetchedAt: now,
    );
  }

  // ── helpers ────────────────────────────────────────────────────

  static String _ymd(DateTime d) {
    final iso = d.toIso8601String();
    return iso.split('T').first;
  }

  /// True when any of the user's last-touched markers indicates an
  /// activity today. See FIRESTORE_ARCHITECTURE.md for which hook
  /// sets which marker.
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
