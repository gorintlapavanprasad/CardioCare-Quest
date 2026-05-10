import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/services/health_service.dart';
import 'package:cardio_care_quest/core/widgets/sync_badge.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/game_detail_dialog.dart';
import 'game_catalog_screen.dart';
import '../../community/community_stats_screen.dart';
import '../../health/health_stats_screen.dart';
import '../../games/custom_games/build_game_screen.dart';
import '../../games/custom_games/custom_game.dart';
import '../../games/custom_games/custom_games_repository.dart';
import '../../games/custom_games/custom_games_section.dart';
import '../../games/game_stories.dart';
import '../../games/quiet_minute.dart';
import '../../survey/post_play_survey.dart';
import '../../../core/services/favorites_service.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _dashboardLocationChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDashboardLocationPermission();
      // Best-effort: ask once for HealthKit / Health Connect permissions.
      // Used by HealthHooks.logSnapshot to capture wearable vitals after
      // every game end. Failure / denial is fine — game-end snapshots
      // still write a metadata-only doc with hasWearableData=false.
      // We log the denial as a telemetry event so researchers can
      // distinguish "no Watch" from "permission denied" in the dataset.
      _requestHealthPermissionsAndReport();
      // ─── CRITICAL FIX: Fetch user data when the dashboard first loads ───
      _ensureUserDataLoaded();
    });
  }

  Future<void> _requestHealthPermissionsAndReport() async {
    try {
      final granted = await HealthService.instance.requestPermissions();
      if (!granted) {
        final uid =
            Provider.of<UserDataProvider>(context, listen: false).uid;
        await TelemetryHooks.logEvent(
          'healthkit_permission_denied',
          parameters: const {
            'reason': 'os_dialog_denied_or_unavailable',
          },
          userId: uid.isEmpty ? null : uid,
        );
      }
    } catch (e) {
      debugPrint('HealthKit permission request error: $e');
    }
  }

  Future<void> _ensureUserDataLoaded() async {
    try {
      final provider = Provider.of<UserDataProvider>(context, listen: false);
      // Only fetch if data is not already loaded
      if (provider.userData == null) {
        await provider.fetchUserData();
      }
      // Hydrate the favourites cache for this participant. Cheap if
      // already loaded (FavoritesService.load short-circuits when the
      // id matches the cached one).
      final pid = provider.uid;
      if (pid.isNotEmpty) {
        await FavoritesService.instance.load(pid);
      }
    } catch (e) {
      debugPrint('Error ensuring user data is loaded: $e');
    }
  }

  Future<void> _checkDashboardLocationPermission() async {
    if (_dashboardLocationChecked) return;
    _dashboardLocationChecked = true;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        await _showLocationServiceDisabledDialog();
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied) {
          if (!mounted) return;
          await _showLocationRequiredDialog();
        } else if (requested == LocationPermission.deniedForever) {
          if (!mounted) return;
          await _showLocationSettingsDialog();
        }
      } else if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        await _showLocationSettingsDialog();
      }
    } catch (e) {
      debugPrint('Dashboard location permission check failed: $e');
    }
  }

  Future<void> _showLocationServiceDisabledDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Required'),
        content: const Text(
          'Location services are turned off. Please enable location services so movement quests and the game can work properly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationRequiredDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Needed'),
        content: const Text(
          'This app uses location for movement tracking and game quests. Please allow location access to proceed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Permanently Denied'),
        content: const Text(
          'Location permission is permanently denied. Please open app settings and allow location access so movement quests can complete.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserDataProvider>(
      builder: (context, provider, child) {
        if (provider.userData == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.viridis2),
            ),
          );
        }

        final data = provider.userData!;

        // ─── THE FIX: Use the Provider getters instead of raw map keys ───
        // Hardcoded for the 2026-05-02 dry-run: 15 participants log in by
        // Unique ID without ever setting a profile name. Pull from
        // provider.firstName again once participants have a real basicInfo.
        const name = 'Explorer';
        final points = provider.points;

        // Data retention fields from Deep Sync
        final String sys = data['lastSystolic']?.toString() ?? "--";
        final String dia = data['lastDiastolic']?.toString() ?? "--";

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.title,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(child: SyncBadge()),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPremiumHeader(context, name, points),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildSectionTitle("Health Status"),
                      _buildLatestBPCard(context, sys, dia),
                      const SizedBox(height: 32),
                      _buildGameMenuRow(context),
                      // "Your Goals" — participant-built custom games
                      // from the Design Your Own Game flow. Lives just
                      // under the menu row so the result of pressing
                      // "Design Your Own Game" appears right where you
                      // expect it. Hidden when the participant hasn't
                      // created any goals yet.
                      const CustomGamesSection(),
                    ],
                  ),
                ),
                // Favourites strip is intentionally outside the horizontal-20
                // padding so the horizontally-scrolling card list can extend
                // edge-to-edge. Keeps the favourite-heart corner of the
                // rightmost card from getting clipped at the viewport edge
                // and lets the next card "peek" in to signal scrollability.
                // The section title is re-aligned with siblings via internal
                // padding inside _buildFavoritesSection.
                _buildFavoritesSection(context),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Watch & Health — entry-point to the live
                      // HealthKit / Health Connect dashboard. Sits
                      // just above Feedback so the participant can
                      // see fresh vitals without scrolling all the
                      // way back up to the BP card. Only visible to
                      // the participant themself; data is
                      // userData/{uid}/healthSnapshots, not cohort-
                      // wide.
                      const SizedBox(height: 32),
                      _buildSectionTitle("Watch & Health"),
                      _buildHealthStatsCard(context),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Feedback"),
                      _buildPostPlaySurveyCard(context),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dashboard entry-point to the Health Stats screen. Same card
  /// language as the other "drilldown" tiles on the dashboard
  /// (Latest BP, Post-play survey) — icon on the left, two lines
  /// of copy in the middle, chevron on the right. Subtitle copy
  /// adapts to whether the participant is likely to have data:
  /// at the dashboard level we don't query Firestore (would slow
  /// the home render), so we just promise "live readings" and let
  /// the screen itself surface the empty state when relevant.
  Widget _buildHealthStatsCard(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const HealthStatsScreen(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.watch_outlined,
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Stats',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.title,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Live heart rate, steps, calories and more from '
                      'your Apple Watch.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.subtitle,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.subtitle),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom-of-dashboard entry point for the post-play survey
  /// (work-plan goal #9). Once-per-session feedback prompt, lives at
  /// the bottom of the dashboard below the game menu row.
  Widget _buildPostPlaySurveyCard(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PostPlaySurveyScreen(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.feedback_outlined,
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How was your experience?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.title,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Five quick questions. Earns 25 points.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.subtitle,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.subtitle),
            ],
          ),
        ),
      ),
    );
  }

  /// Favourites strip — horizontally-scrollable list of games the
  /// participant has starred via the GameDetailDialog. Listens to
  /// [FavoritesService.favorites] so adding / removing a star in the
  /// catalog dialog instantly reflects here without a manual refresh.
  /// Returns an empty box when the participant has no favourites yet
  /// so the dashboard doesn't show a stranded "Favourites" header
  /// above an empty space.
  Widget _buildFavoritesSection(BuildContext context) {
    final uid = context.select<UserDataProvider, String>((p) => p.uid);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesService.instance.favorites,
      builder: (context, favIds, _) {
        if (favIds.isEmpty) return const SizedBox.shrink();

        // Catalog favourites — resolve ids → GameStory in catalog
        // order so the strip stays consistent regardless of star order.
        final catalogFavs = GameCatalog.games.values
            .where((g) => favIds.contains(g.id))
            .toList();

        // Custom favourites — pulled from Firestore via the same
        // CustomGamesRepository stream the catalog accordion uses.
        // Wrapping the strip in a StreamBuilder keeps the custom tiles
        // live: starring/unstarring or editing a custom game on
        // another device updates this strip without a manual refresh.
        return StreamBuilder<List<CustomGame>>(
          stream: uid.isEmpty
              ? const Stream<List<CustomGame>>.empty()
              : CustomGamesRepository.instance.watch(uid),
          builder: (context, snap) {
            final allCustom = snap.data ?? const <CustomGame>[];
            final customFavs =
                allCustom.where((c) => favIds.contains(c.id)).toList();

            if (catalogFavs.isEmpty && customFavs.isEmpty) {
              return const SizedBox.shrink();
            }

            // Render catalog favourites first, then custom favourites
            // — same pattern the catalog screen uses (curated content
            // before user-authored content).
            final tiles = <Widget>[
              ...catalogFavs.map((g) => _FavoriteGameTile(game: g)),
              ...customFavs.map(
                (c) => _FavoriteCustomGameTile(game: c),
              ),
            ];

            return Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title gets its own horizontal-20 padding now that the
                  // whole favourites section sits outside the dashboard's
                  // shared content padding — keeps it visually aligned
                  // with "Health Status" / "Feedback" above and below.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSectionTitle("Favourites"),
                  ),
                  SizedBox(
                    height: 124,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // 20px on left aligns the first card with the
                      // section title and the rest of the dashboard;
                      // 20px on right keeps the last card off the screen
                      // edge so its favourite-heart corner stays visible.
                      // The strip is horizontally scrollable, so cards
                      // beyond the viewport remain reachable.
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: tiles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => tiles[index],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- 📱 UI HELPERS ---

  /// Latest blood pressure reading. Whole card is now tappable — both
  /// the body and the trailing play button launch the Blood Pressure
  /// Log (the renamed Quiet Minute Twine game), which is now the only
  /// participant-facing path to record a reading. Replaces the older
  /// `Icons.favorite_rounded` heart accent that was just decorative.
  Widget _buildLatestBPCard(BuildContext context, String sys, String dia) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openBloodPressureLog(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "LATEST READING",
                      style: TextStyle(
                        color: AppColors.subtitle,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          sys,
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            color: AppColors.title,
                          ),
                        ),
                        Text(
                          "/$dia",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.title.withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "mmHg",
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.subtitle,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Tap to record a new reading",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.subtitle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Play button — launches the Blood Pressure Log game.
              // Distinct from the rest of the card so participants who
              // are reading numbers know there's an explicit "do this
              // now" affordance.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pushes the Blood Pressure Log (the Twine BP-capture game).
  /// Single helper so both the card body's InkWell and the trailing
  /// play button hit the same route. Awaits the pop and then
  /// refetches userData so the dashboard's "Latest reading" card
  /// reflects the freshly-logged BP without a manual refresh —
  /// previously the participant logged a reading and came back to
  /// see the OLD value still on the card until the next app launch.
  Future<void> _openBloodPressureLog(BuildContext context) async {
    final provider =
        Provider.of<UserDataProvider>(context, listen: false);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuietMinuteGame()),
    );
    if (!mounted) return;
    if (provider.uid.isNotEmpty) {
      // Fire-and-forget — the optimistic local bump from PointsHooks
      // inside the host has already updated the provider; this
      // reconciles against the server-resolved values once the
      // OfflineQueue has drained.
      unawaited(provider.fetchUserData());
    }
  }

  Widget _buildPremiumHeader(BuildContext context, String name, int points) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hello, $name!",
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3A5E),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Total Points Collected: $points",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.title,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameMenuRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildMenuCard(
            context,
            title: 'Game Catalog',
            icon: Icons.grid_view,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GameCatalogScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMenuCard(
            context,
            title: 'Design Your Own Game',
            icon: Icons.add_circle_outline,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BuildGameScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMenuCard(
            context,
            title: 'Community Statistics',
            icon: Icons.bar_chart,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CommunityStatsScreen(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 0.9,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.title,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? actionText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.title,
            ),
          ),
          if (actionText != null)
            Text(
              actionText,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.subtitle,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

}

/// Compact card used in the dashboard's Favourites strip. Square-ish,
/// shows the game's mono icon + title + a tiny heart in the corner so
/// the participant can confirm at a glance "yes, this is a favourite."
/// Tapping opens the same [GameDetailDialog] the catalog uses — Play
/// button to launch, heart toggle to unstar without going through the
/// catalog. Per-tile-direct-launch was tried earlier but participants
/// wanted a way to remove a star from the dashboard, and reusing the
/// dialog keeps the play UX consistent across both entry points.
class _FavoriteGameTile extends StatelessWidget {
  final GameStory game;

  const _FavoriteGameTile({required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => showGameDetailDialog(context, game),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 96,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 4),
                  Icon(game.iconData, color: AppColors.primary, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    game.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.title,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              const Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  Icons.favorite,
                  size: 14,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact tile for a starred custom game on the dashboard's
/// Favourites strip. Same visual size as `_FavoriteGameTile` but pulls
/// data from a `CustomGame`. Tapping opens the custom variant of the
/// [GameDetailDialog] so participants can preview, launch, or unstar
/// the goal without navigating into the catalog.
class _FavoriteCustomGameTile extends StatelessWidget {
  final CustomGame game;

  const _FavoriteCustomGameTile({required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => showCustomGameDetailDialog(context, game),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 96,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 4),
                  Icon(game.iconData, color: AppColors.primary, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    game.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.title,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              const Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  Icons.favorite,
                  size: 14,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
