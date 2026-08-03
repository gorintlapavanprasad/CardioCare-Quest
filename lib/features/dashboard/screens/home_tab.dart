// Home / dashboard - the main screen the participant sees, and the hub
// everything hangs off. Top to bottom: a greeting, the latest
// blood-pressure reading, a game menu, the person's own goals, favourite
// games, health stats, a caregiver card, and a feedback link. Most cards
// just tap through to a bigger screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/services/health_service.dart';
import 'package:cardio_care_quest/core/widgets/sync_badge.dart';
import 'package:cardio_care_quest/core/widgets/who_is_playing_dialog.dart';
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
import '../../../core/services/session_manager.dart';
import '../../pairing/joint_setup_screen.dart';
import '../../caregiver/caregiver_screen.dart';

// The dashboard screen. Stateful because it does one-time setup on open
// (permissions, loading the user's data).
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // So we only ask for location once per screen visit.
  bool _dashboardLocationChecked = false;

  // Runs once when the screen opens. After the first frame, do the setup:
  // ask for location + health permissions, and load the user's data.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkDashboardLocationPermission();
      // Best-effort: ask once for HealthKit / Health Connect permissions.
      // Used by HealthHooks.logSnapshot to capture wearable vitals after
      // every game end. Failure / denial is fine - game-end snapshots
      // still write a metadata-only doc with hasWearableData=false.
      // We log the denial as a telemetry event so researchers can
      // distinguish "no Watch" from "permission denied" in the dataset.
      _requestHealthPermissionsAndReport();
      // ─── CRITICAL FIX: Fetch user data when the dashboard first loads ───
      // Await so the who's-playing prompt below has a real uid to attribute
      // the "I am the patient" choice to.
      await _ensureUserDataLoaded();
      // Ask once per launch whether the participant or a caregiver is
      // playing, so survey responses can be tagged correctly.
      if (mounted) _promptWhoIsPlaying();
    });
  }

  // Show the one-time "who is playing?" popup (participant vs caregiver).
  // No-ops if a choice was already made this launch (guarded inside the
  // dialog's show()), so it only appears on the first dashboard load.
  void _promptWhoIsPlaying() {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return; // no participant yet - skip, ask on next load.
    WhoIsPlayingDialog.show(context: context, uid: uid);
  }

  // Ask once for access to watch/phone health data (heart rate, steps...).
  // If the user says no, we quietly record that, so researchers can tell
  // "said no" apart from "has no watch". Not getting it is fine either way.
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

  // Make sure the user's profile + points are loaded, and their list of
  // favourite games too. Skips work that's already done.
  Future<void> _ensureUserDataLoaded() async {
    try {
      final provider = Provider.of<UserDataProvider>(context, listen: false);
      // Only fetch if data is not already loaded
      if (provider.userData == null) {
        await provider.fetchUserData();
      }
      // Load this person's favourites. Cheap if already loaded - it skips
      // the work when the id matches what's already cached.
      final pid = provider.uid;
      if (pid.isNotEmpty) {
        await FavoritesService.instance.load(pid);
      }
    } catch (e) {
      debugPrint('Error ensuring user data is loaded: $e');
    }
  }

  // Ask for location permission (the walking/movement games need it).
  // Pops a friendly dialog if location is switched off or was blocked.
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

  // Dialog: phone's location is turned off entirely.
  Future<void> _showLocationServiceDisabledDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location is turned off'),
        content: const Text(
          'Location is turned off on your phone. Please turn it on so the walking games can work.',
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

  // Dialog: the user declined location this time (can still allow it).
  Future<void> _showLocationRequiredDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow location?'),
        content: const Text(
          'The walking games need to know where you are. Please tap Allow when your phone asks.',
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

  // Dialog: location was blocked for good - tells them to fix it in Settings.
  Future<void> _showLocationSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location is blocked'),
        content: const Text(
          'The walking games are blocked. Please open your phone Settings, find this app, and turn on location.',
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

  // Build the whole dashboard. Shows a loading spinner until the user's
  // data is ready, then stacks all the sections in one scrolling column.
  @override
  Widget build(BuildContext context) {
    return Consumer<UserDataProvider>(
      builder: (context, provider, child) {
        // Still loading? Show a spinner instead of a half-empty screen.
        if (provider.userData == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.viridis2),
            ),
          );
        }

        final data = provider.userData!;

        // Everyone is greeted as "Explorer" for now. During the dry-run
        // participants log in by ID and have no profile name, so we skip
        // the real name until they actually set one.
        const name = 'Explorer';

        // Their most recent BP numbers; "--" if they've never logged one.
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
                // ---- HEADER (greeting) ----
                _buildPremiumHeader(context, name),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---- LATEST BP (tap to log a new reading) ----
                      const SizedBox(height: 24),
                      _buildSectionTitle("Health Status"),
                      _buildLatestBPCard(context, sys, dia),
                      // ---- GAME MENU + YOUR GOALS ----
                      const SizedBox(height: 32),
                      _buildGameMenuRow(context),
                      // "Your Goals" - the games the person built with
                      // "Design Your Own Game". Sits right under the menu
                      // row so the result shows up where you'd expect.
                      // Hidden until they've made at least one.
                      const CustomGamesSection(),
                    ],
                  ),
                ),
                // ---- FAVOURITES (sideways-scrolling strip) ----
                // Sits OUTSIDE the usual side padding so the cards can run
                // edge-to-edge. This stops the last card's heart getting
                // clipped and lets the next card "peek" in, hinting you can
                // scroll. Its title gets its own padding to line up again.
                _buildFavoritesSection(context),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---- WATCH & HEALTH (live vitals) ----
                      // Opens the live watch/health dashboard. Placed near
                      // the bottom so fresh vitals are handy without
                      // scrolling back up. Only this person sees their data.
                      const SizedBox(height: 32),
                      _buildSectionTitle("Your Watch"),
                      _buildHealthStatsCard(context),
                      // ---- CAREGIVER (play together) ----
                      const SizedBox(height: 32),
                      _buildSectionTitle("Caregiver"),
                      _buildCaregiverCard(context),
                      // ---- FEEDBACK (post-play survey) ----
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

  // The "Play with a caregiver" card. Tap it: if no shared session is
  // going yet, it opens the setup screen (caregiver name, text size, pace);
  // if one's already running, it jumps straight to the caregiver view.
  Widget _buildCaregiverCard(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (SessionManager.isPaired) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CaregiverScreen()),
            );
            return;
          }
          final started = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const JointSetupScreen()),
          );
          if (started == true && context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CaregiverScreen()),
            );
          }
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
          child: const Row(
            children: [
              Icon(Icons.groups_outlined, color: AppColors.primary, size: 32),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Play with a caregiver',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.title,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Choose the text size and speed together, then play '
                      'and take notes.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.subtitle,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.subtitle),
            ],
          ),
        ),
      ),
    );
  }

  // The "Health Stats" card - taps through to the live watch/health
  // screen (heart rate, steps, calories, etc.).
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

  // The "How was your experience?" card near the bottom - taps through
  // to a short 5-question feedback survey.
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
                      'Five quick questions.',
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

  // The Favourites strip - a sideways-scrolling row of games the person
  // has starred. It updates live, so starring/unstarring elsewhere shows
  // here right away. Shows nothing at all when there are no favourites,
  // so we don't leave a lonely "Favourites" header over empty space.
  Widget _buildFavoritesSection(BuildContext context) {
    final uid = context.select<UserDataProvider, String>((p) => p.uid);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesService.instance.favorites,
      builder: (context, favIds, _) {
        // No favourites yet? Draw nothing.
        if (favIds.isEmpty) return const SizedBox.shrink();

        // Starred built-in games, kept in catalog order (not star order)
        // so the strip doesn't jump around.
        final catalogFavs = GameCatalog.games.values
            .where((g) => favIds.contains(g.id))
            .toList();

        // Starred home-made games, read live from the cloud so edits or
        // stars from another device show up here on their own.
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

            // Built-in games first, then home-made ones (same order the
            // catalog uses).
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
                  // Give just the title side padding so it lines up with
                  // the other section titles (the strip itself runs wider).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSectionTitle("Favourites"),
                  ),
                  SizedBox(
                    height: 124,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // Pad both ends by 20: lines the first card up with
                      // the title, and keeps the last card's heart from
                      // touching the screen edge. You can scroll for more.
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

  // --- UI HELPERS (the pieces that build each card) ---

  // The "Latest reading" blood-pressure card. The whole thing is tappable
  // - body or the round play button - and both open the BP-logging game,
  // which is the only way to record a new reading.
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
              // The round play button. Stands out from the numbers so it's
              // an obvious "tap here to log now".
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

  // Opens the BP-logging game. One helper so the card body and the play
  // button both go to the same place. After the game closes, it reloads
  // the user's data so the card shows the number you just logged instead
  // of the old one.
  Future<void> _openBloodPressureLog(BuildContext context) async {
    final provider =
        Provider.of<UserDataProvider>(context, listen: false);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuietMinuteGame()),
    );
    if (!mounted) return;
    if (provider.uid.isNotEmpty) {
      // Refresh in the background. The screen already shows a quick local
      // guess; this just syncs it with the real saved values.
      unawaited(provider.fetchUserData());
    }
  }

  // The top banner: a simple "Hello, <name>!" greeting.
  Widget _buildPremiumHeader(BuildContext context, String name) {
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
        ],
      ),
    );
  }

  // The row of three menu buttons: Game Catalog, Design Your Own Game,
  // and Community Statistics.
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
              MaterialPageRoute(
                builder: (_) => const GameCatalogScreen(),
              ),
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

  // One square menu button - icon + label - used by the row above.
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

  // A section heading (e.g. "Health Status"), with an optional grey
  // action label on the right.
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

// A small card in the Favourites strip for a built-in game. Shows the
// icon, title, and a tiny heart in the corner. Tapping opens the same
// preview popup the catalog uses, so you can play it or unstar it right
// from the dashboard.
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
                  Icons.star_rounded,
                  size: 16,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Same little Favourites card, but for a home-made game. Looks identical
// to _FavoriteGameTile; it just opens the custom-game version of the
// preview popup.
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
                  Icons.star_rounded,
                  size: 16,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
