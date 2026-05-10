// Community Statistics — anonymous cohort dashboard for the
// dry-run.
//
// Reference: netguage/lib/community_statistics.dart shows the same
// "all-time totals as plain text" pattern with one user's data. We
// rebuilt around that idea but for a 15-participant research cohort:
// the page now aggregates across every userData doc and the
// collection-group game/BP logs so each card surfaces a cohort
// signal (avg, count, range) rather than one user's number.
//
// Privacy: every displayed value is an aggregate. There is no
// per-user list or rank — at 15 participants, even a leaderboard
// could deanonymise. If the cohort grows past ~30 we can revisit
// adding a sorted ranking with hashed display names.
//
// Rendering strategy: one foreground fetch on screen open, plus a
// pull-to-refresh. Stats are bounded by a 7-day window for the
// time-sensitive cards (BP, plays, pills); cohort points and active-
// today are real-time.

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../games/game_stories.dart';
import 'community_stats_service.dart';

class CommunityStatsScreen extends StatefulWidget {
  const CommunityStatsScreen({super.key});

  @override
  State<CommunityStatsScreen> createState() => _CommunityStatsScreenState();
}

class _CommunityStatsScreenState extends State<CommunityStatsScreen> {
  // Future-of-stats so the build method can drive a single
  // FutureBuilder. Replaced (not awaited) on pull-to-refresh so the
  // loading spinner reappears for the duration of the new fetch.
  Future<CommunityStats>? _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = CommunityStatsService.instance.fetch();
  }

  Future<void> _refresh() async {
    setState(() {
      _statsFuture = CommunityStatsService.instance.fetch();
    });
    await _statsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.title,
        foregroundColor: Colors.white,
        // Explicit iconTheme + titleTextStyle — see the matching
        // note in health_stats_screen.dart. The global appBarTheme
        // configures dark icons / dark title for the dashboard's
        // white AppBar; on this dark AppBar we need to override
        // both back to white or the back arrow + title disappear.
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        title: const Text('Community Statistics'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: FutureBuilder<CommunityStats>(
          future: _statsFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingState();
            }
            if (snap.hasError) {
              return _ErrorState(message: snap.error.toString());
            }
            final stats = snap.data;
            if (stats == null || stats.cohortSize == 0) {
              return const _EmptyState();
            }
            return _StatsBody(stats: stats);
          },
        ),
      ),
    );
  }
}

// ───────────── States ─────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    // Single-screen-height padding so RefreshIndicator can still be
    // pulled even while the future is in-flight.
    return ListView(
      children: const [
        SizedBox(
          height: 400,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 64),
        const Icon(Icons.cloud_off_outlined,
            size: 64, color: AppColors.subtitle),
        const SizedBox(height: 16),
        const Text(
          "Couldn't load community stats",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.title,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pull down to try again. If this keeps happening, the cohort '
          'database may not have shared aggregate access enabled yet.\n\n'
          'Details: $message',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.subtitle,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // Renders before any participant has logged in to the dry-run —
    // shouldn't be reachable on the actual study day, but we still
    // need a graceful fallback for first-launch testing.
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 64),
        Icon(Icons.people_outline, size: 64, color: AppColors.subtitle),
        SizedBox(height: 16),
        Text(
          'No cohort activity yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.title,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Once participants begin logging readings and playing games, '
          'this page will summarise what the group is doing — without '
          'sharing any individual results.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.subtitle,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ───────────── Body ─────────────

class _StatsBody extends StatelessWidget {
  final CommunityStats stats;
  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // Privacy banner removed for the 2026-05-12 demo — earlier
        // it read as a defensive disclaimer ("Showing anonymous
        // totals across N participants. No individual readings or
        // names are visible here.") which felt out of place at a
        // 150-person showcase. Re-introduce as a subtle footer
        // line, or as an info-icon tooltip on the AppBar, if the
        // page lands in a research-IRB context where participants
        // benefit from explicit data-handling assurances.
        _SectionTitle('Cohort Pulse'),
        _CohortPulseCard(stats: stats),
        const SizedBox(height: 24),

        _SectionTitle('Heart Health'),
        _HeartHealthCard(stats: stats),
        const SizedBox(height: 24),

        _SectionTitle('Medication Adherence'),
        _MedicationCard(stats: stats),
        const SizedBox(height: 24),

        _SectionTitle('Game Engagement'),
        _GameEngagementCard(stats: stats),
        const SizedBox(height: 24),

        _SectionTitle('Cohort Score'),
        _CohortScoreCard(stats: stats),
        const SizedBox(height: 16),

        _Footer(fetchedAt: stats.fetchedAt, windowDays: stats.windowDays),
      ],
    );
  }
}

// ───────────── Section / Footer ─────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.title,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final DateTime fetchedAt;
  final int windowDays;
  const _Footer({required this.fetchedAt, required this.windowDays});

  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        'Updated ${_ago(fetchedAt)} • '
        'Time-bounded stats cover the last $windowDays days • '
        'Pull to refresh',
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.subtitle,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ───────────── Cards ─────────────

/// Generic stat card used for the simpler sections. Centred big
/// number with a helper line under it. Two-tone variant for the
/// pulse card uses [_TwoStatCard].
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String label;
  final String? sub;
  final Color iconColor;
  const _StatCard({
    required this.icon,
    required this.headline,
    required this.label,
    this.sub,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.subtitle,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            headline,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: AppColors.title,
              height: 1.05,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(
              sub!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.subtitle,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pulse card — two stats side by side. Active-today on the left,
/// total plays this week on the right. Visually higher-contrast than
/// the rest of the cards because it's the page's "at a glance"
/// summary.
class _CohortPulseCard extends StatelessWidget {
  final CommunityStats stats;
  const _CohortPulseCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _PulseHalf(
              big: '${stats.activeToday}',
              small: ' / ${stats.cohortSize}',
              label: 'ACTIVE TODAY',
              hint: 'Participants with activity in the last 24h',
              icon: Icons.bolt_outlined,
            ),
          ),
          Container(
            width: 1,
            height: 84,
            color: AppColors.cardBorder,
          ),
          Expanded(
            child: _PulseHalf(
              big: '${stats.playsThisWeek}',
              small: '',
              label: 'PLAYS THIS WEEK',
              hint: 'Game completions across the cohort',
              icon: Icons.sports_esports_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseHalf extends StatelessWidget {
  final String big;
  final String small;
  final String label;
  final String hint;
  final IconData icon;
  const _PulseHalf({
    required this.big,
    required this.small,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                big,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title,
                  height: 1,
                ),
              ),
              if (small.isNotEmpty)
                Text(
                  small,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.title.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.subtitle,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.subtitle,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Heart-health card — cohort BP averages with a min/max range
/// underneath. We deliberately don't show a daily trend chart here:
/// at 15 participants × 7 days the line would have wide confidence
/// intervals and could overweight a single outlier reading.
class _HeartHealthCard extends StatelessWidget {
  final CommunityStats stats;
  const _HeartHealthCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.bpReadingsThisWeek == 0 || stats.avgSystolic == null) {
      return _StatCard(
        icon: Icons.monitor_heart_outlined,
        headline: '—',
        label: 'AVG COHORT BP',
        sub: 'No readings logged in the last ${stats.windowDays} days yet.',
        iconColor: AppColors.primary,
      );
    }
    final sys = stats.avgSystolic!.round();
    final dia = stats.avgDiastolic!.round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.monitor_heart_outlined,
                  color: AppColors.primary, size: 26),
              SizedBox(width: 10),
              Text(
                'AVG COHORT BP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.subtitle,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$sys',
                style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title,
                  height: 1,
                ),
              ),
              Text(
                '/$dia',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'mmHg',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.subtitle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RangeRow(
            label: 'Systolic range',
            min: stats.sysMin,
            max: stats.sysMax,
          ),
          const SizedBox(height: 6),
          _RangeRow(
            label: 'Diastolic range',
            min: stats.diaMin,
            max: stats.diaMax,
          ),
          const SizedBox(height: 12),
          Text(
            '${stats.bpReadingsThisWeek} reading${stats.bpReadingsThisWeek == 1 ? '' : 's'} '
            'logged this week.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.subtitle,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  final String label;
  final int? min;
  final int? max;
  const _RangeRow({required this.label, required this.min, required this.max});

  @override
  Widget build(BuildContext context) {
    final value =
        (min == null || max == null) ? '—' : '$min – $max mmHg';
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.subtitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.title,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Medication adherence — pills logged this week + a percentage of
/// cohort that has taken medication today. We chose a percentage
/// rather than raw count because it stays interpretable across
/// cohort-size changes (15 today, possibly more tomorrow).
class _MedicationCard extends StatelessWidget {
  final CommunityStats stats;
  const _MedicationCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final pct = stats.cohortSize == 0
        ? 0
        : ((stats.participantsWhoTookPillToday / stats.cohortSize) * 100)
            .round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.medication_outlined,
                  color: AppColors.primary, size: 26),
              SizedBox(width: 10),
              Text(
                'PILLS LOGGED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.subtitle,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${stats.pillsLoggedThisWeek}',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: AppColors.title,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'across the cohort over the last ${stats.windowDays} days',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.subtitle,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          // Linear progress reads as "fraction of cohort that has
          // taken medication today". Capped at 1.0 — a defensive
          // div-by-zero already short-circuited above.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: stats.cohortSize == 0
                  ? 0
                  : stats.participantsWhoTookPillToday / stats.cohortSize,
              minHeight: 12,
              backgroundColor: AppColors.cardBorder,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$pct% of the cohort have taken their medication today '
            '(${stats.participantsWhoTookPillToday} of ${stats.cohortSize}).',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.title,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Engagement — horizontal bars for plays-by-category plus the
/// most-played game callout on top. The bars share a visual scale
/// (longest bar = max category) so participants can read relative
/// engagement at a glance without exact counts being legible.
class _GameEngagementCard extends StatelessWidget {
  final CommunityStats stats;
  const _GameEngagementCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.playsThisWeek == 0) {
      return _StatCard(
        icon: Icons.sports_esports_outlined,
        headline: '—',
        label: 'PLAYS THIS WEEK',
        sub: 'No game completions logged in the last ${stats.windowDays} days yet.',
      );
    }

    final topGame = stats.topGameId == null
        ? null
        : GameCatalog.games[stats.topGameId];
    final maxCount = stats.playsByCategory.values.fold<int>(
      0,
      (m, v) => v > m ? v : m,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.sports_esports_outlined,
                  color: AppColors.primary, size: 26),
              SizedBox(width: 10),
              Text(
                'GAME ENGAGEMENT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.subtitle,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (topGame != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  topGame.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topGame.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.title,
                        ),
                      ),
                      Text(
                        'Most played — ${stats.topGamePlays} '
                        '${stats.topGamePlays == 1 ? 'play' : 'plays'} this week',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.subtitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // Iterate the canonical category order from the enum so
          // the bars render in the same sequence as the catalog
          // tiles on the dashboard.
          for (final cat in GameCategory.values)
            _CategoryBar(
              category: cat,
              count: stats.playsByCategory[cat] ?? 0,
              maxCount: maxCount,
            ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final GameCategory category;
  final int count;
  final int maxCount;
  const _CategoryBar({
    required this.category,
    required this.count,
    required this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(category.icon,
                  color: _viridisStop(category), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  category.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.title,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Background track plus the filled portion. Custom-built
          // rather than LinearProgressIndicator so each category can
          // own a distinct viridis stop, matching the games' new
          // unified palette.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(
                  height: 10,
                  color: AppColors.cardBorder,
                ),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 10,
                    color: _viridisStop(category),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Map each category to a distinct viridis anchor stop. Matches
  /// the palette the games now share — gives the bars a clear
  /// "this is part of the CardioCare visual system" feel rather
  /// than a generic Material chart look.
  static Color _viridisStop(GameCategory cat) {
    switch (cat) {
      case GameCategory.exercise:
        return const Color(0xFF440154); // deep purple
      case GameCategory.diet:
        return const Color(0xFF3B528B); // blue
      case GameCategory.medication:
        return const Color(0xFF21918C); // teal
      case GameCategory.measurements:
        return const Color(0xFF5EC962); // green
      case GameCategory.education:
        return const Color(0xFFFDE725); // yellow
    }
  }
}

class _CohortScoreCard extends StatelessWidget {
  final CommunityStats stats;
  const _CohortScoreCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final perPerson = stats.cohortSize == 0
        ? 0
        : (stats.totalCohortPoints / stats.cohortSize).round();
    return _StatCard(
      icon: Icons.emoji_events_outlined,
      headline: _formatThousands(stats.totalCohortPoints),
      label: 'TOTAL COHORT POINTS',
      sub: 'About $perPerson points per participant on average. '
          'Points come from BP logs, game plays, and survey submits.',
      iconColor: AppColors.accent,
    );
  }

  static String _formatThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ───────────── Decoration helper ─────────────

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
