import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/services/health_service.dart';
import 'package:cardio_care_quest/core/widgets/sync_badge.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/daily_task_card.dart';
import '../widgets/health_pillar_tile.dart';
import '../widgets/celebration_modal.dart';
import 'coming_soon_screen.dart';
import 'game_catalog_screen.dart';
import '../../blood_pressure/bp_log_screen.dart';
import '../../education/health_education_screen.dart';
import '../../exercise_log/exercise_log_screen.dart';
import '../../medication_reminder/medication_reminder_screen.dart';
import '../../family_circle/family_circle_screen.dart';
import '../../measurements/measurements_screen.dart';
import '../../statistics/heart_statistics_screen.dart';
import '../../games/dash_diet_game/diet_log_screen.dart';
import '../../survey/post_play_survey.dart';

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
                      const SizedBox(height: 32),
                      _buildSectionTitle("Health Pillars"),
                      _buildHealthPillarsGrid(context),

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

  /// Bottom-of-dashboard entry point for the post-play survey
  /// (work-plan goal #9). Lives below the Health Pillars grid because
  /// it's a once-per-session feedback prompt, not a daily quest.
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

  // --- 🏥 HEALTH PILLARS (Aligned with Research "Decks") [cite: 245-246] ---
  Widget _buildHealthPillarsGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _pillar(context, Icons.favorite, "Heart", const HeartStatisticsScreen()),
        _pillar(context, Icons.directions_walk, "Movement", const ExerciseLogScreen()),
        _pillar(context, Icons.restaurant, "Plate", const DietLogScreen()),
        _pillar(context, Icons.school, "Education", const HealthEducationScreen()),
        _pillar(context, Icons.medication, "Medicine", const MedicationReminderScreen()),
        _pillar(
          context,
          Icons.monitor_heart_outlined,
          "Measurements",
          const MeasurementsScreen(),
        ),
      ],
    );
  }

  Widget _pillar(
    BuildContext context,
    IconData icon,
    String title,
    Widget screen,
  ) {
    return HealthPillarTile(
      icon: icon,
      title: title,
      onTap: () async {
        final dynamic result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        );
        if (result is int && context.mounted) {
          showCelebrationModal(context, message: "Goal Met!", pointsGained: result);
        } else if (result == true && context.mounted) {
          showCelebrationModal(context, message: "Goal Met!", pointsGained: 25);
        }
      },
    );
  }

  // --- 📱 UI HELPERS ---

  Widget _buildFamilySnippet(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.userData)
          .snapshots(),
      builder: (context, snapshot) {
        int totalSteps = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            totalSteps += (data['totalSteps'] as num?)?.toInt() ?? 0;
          }
        }

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FamilyCircleScreen()),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.group, color: AppColors.accent, size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Shared Quest",
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$totalSteps / 10,000 steps together",
                        style: const TextStyle(
                          color: AppColors.subtitle,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.accent.withValues(alpha: 0.5),
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLatestBPCard(BuildContext context, String sys, String dia) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
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
            ],
          ),
          const Icon(
            Icons.favorite_rounded,
            color: AppColors.primary,
            size: 36,
          ),
        ],
      ),
    );
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

  Widget _buildResearchStatsBar(int logs, String avgBp) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.viridis4.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: _buildStatItem("Logs", "$logs")),
          _buildStatDivider(),
          Expanded(child: _buildStatItem("Avg BP", avgBp)),
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
              MaterialPageRoute(
                builder: (_) =>
                    const ComingSoonScreen(featureName: 'Design Your Own Game'),
              ),
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
                builder: (_) =>
                    const ComingSoonScreen(featureName: 'Community Statistics'),
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

  Widget _buildDailyBPQuest(BuildContext context, bool completed) {
    return DailyTaskCard(
      task: "Log your blood pressure",
      completed: completed,
      onToggle: () async {
        final dynamic result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BPLogScreen()),
        );
        if (!context.mounted) return;
        if (result is int) {
          showCelebrationModal(context, message: "Goal Met!", pointsGained: result);
        } else if (result == true) {
          showCelebrationModal(context, message: "Goal Met!", pointsGained: 50);
        }
      },
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

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: AppColors.subtitle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.title,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 30,
      width: 1,
      color: AppColors.viridis4.withValues(alpha: 0.2),
    );
  }

  Widget _buildExpandButton(BuildContext context, String title) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: Colors.white,
        side: BorderSide(color: AppColors.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        foregroundColor: AppColors.title,
      ),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title coming soon'),
            duration: const Duration(milliseconds: 900),
          ),
        );
      },
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}
