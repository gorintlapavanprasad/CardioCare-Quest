// Home dashboard. Top to bottom: greeting, latest BP, game menu, favourites,
// health stats, caregiver card, feedback link. Most cards tap to a bigger screen.

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

// Stateful because it does one-time setup on open (permissions, data load).
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // So we only ask for location once per screen visit.
  bool _dashboardLocationChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkDashboardLocationPermission();
      // Ask for HealthKit/Health Connect. Denial is fine but gets logged so
      // researchers can tell "no Watch" apart from "permission denied".
      _requestHealthPermissionsAndReport();
      // Await so the who's-playing prompt has a real uid to work with.
      await _ensureUserDataLoaded();
      if (mounted) _promptWhoIsPlaying();
    });
  }

  // Shows the one-time "who is playing?" popup. Dialog guards against repeat calls.
  void _promptWhoIsPlaying() {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return; // no participant yet - skip, ask on next load.
    WhoIsPlayingDialog.show(context: context, uid: uid);
  }

  // Requests health data access. Logs denial for research tracking.
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

  // Loads the user's profile and favourites. Skips if already loaded.
  Future<void> _ensureUserDataLoaded() async {
    try {
      final provider = Provider.of<UserDataProvider>(context, listen: false);
      if (provider.userData == null) {
        await provider.fetchUserData();
      }
      final pid = provider.uid;
      if (pid.isNotEmpty) {
        await FavoritesService.instance.load(pid);
      }
    } catch (e) {
      debugPrint('Error ensuring user data is loaded: $e');
    }
  }

  // Asks for location permission once. Pops a dialog if off or blocked.
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

  // Location services are off on the device.
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

  // User declined location this session (can still allow it).
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

  // Location blocked permanently - direct them to Settings.
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
        // Show a spinner until data is ready.
        if (provider.userData == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.viridis2),
            ),
          );
        }

        final data = provider.userData!;

        // "Explorer" until users set a profile name.
        const name = 'Explorer';

        // Most recent BP; "--" if never logged.
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
                      const SizedBox(height: 24),
                      _buildSectionTitle("Health Status"),
                      _buildLatestBPCard(context, sys, dia),
                      const SizedBox(height: 32),
                      _buildGameMenuRow(context),
                      // Hidden until the user has made at least one custom game.
                      const CustomGamesSection(),
                    ],
                  ),
                ),
                // Favourites sits outside side padding so cards run edge-to-edge.
                _buildFavoritesSection(context),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      _buildSectionTitle("Watch & Health"),
                      _buildHealthStatsCard(context),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Caregiver"),
                      _buildCaregiverCard(context),
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

  // "Play with a caregiver" card. Opens setup if no session, else goes straight to the caregiver view.
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
                      'Set text size and pace together, then track help and '
                      'notes during play.',
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

  // Taps through to the live watch/health screen (heart rate, steps, etc.).
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

  // Taps through to the 5-question feedback survey.
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

  // Sideways-scrolling strip of starred games. Updates live. Hidden when empty.
  Widget _buildFavoritesSection(BuildContext context) {
    final uid = context.select<UserDataProvider, String>((p) => p.uid);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesService.instance.favorites,
      builder: (context, favIds, _) {
        if (favIds.isEmpty) return const SizedBox.shrink();

        // Built-in starred games, kept in catalog order so the strip doesn't jump.
        final catalogFavs = GameCatalog.games.values
            .where((g) => favIds.contains(g.id))
            .toList();

        // Custom starred games, live from Firestore.
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

            // Built-in games first, then custom ones.
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSectionTitle("Favourites"),
                  ),
                  SizedBox(
                    height: 124,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
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

  // The latest BP card. Tap anywhere to open the BP-logging game.
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

  // Opens the BP-logging game. Refreshes user data afterwards so the card updates.
  Future<void> _openBloodPressureLog(BuildContext context) async {
    final provider =
        Provider.of<UserDataProvider>(context, listen: false);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuietMinuteGame()),
    );
    if (!mounted) return;
    if (provider.uid.isNotEmpty) {
      unawaited(provider.fetchUserData());
    }
  }

  // Top banner with a "Hello, <name>!" greeting.
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
          const Text(
            "CardioCare Quest",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
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

  // Row of three menu buttons: Game Catalog, Design Your Own Game, Community Stats.
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

  // One square menu button with icon + label.
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

  // Section heading with an optional grey label on the right.
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

// Favourites strip card for a built-in game. Tap to open the preview popup.
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

// Same as _FavoriteGameTile but for a home-made game.
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
