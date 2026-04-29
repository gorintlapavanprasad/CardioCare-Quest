import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
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
import '../../statistics/heart_statistics_screen.dart';
import '../../games/dash_diet_game/diet_log_screen.dart';

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
      // ─── CRITICAL FIX: Fetch user data when the dashboard first loads ───
      _ensureUserDataLoaded();
    });
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
        final name = provider.firstName;
        final points = provider.points;
        final logs = provider.totalSessions;

        // Data retention fields from Deep Sync
        final String sys = data['lastSystolic']?.toString() ?? "--";
        final String dia = data['lastDiastolic']?.toString() ?? "--";
        final String avgSys = data['averageSystolic']?.toString() ?? sys;
        final String avgDia = data['averageDiastolic']?.toString() ?? dia;
        final String avgBp = "$avgSys/$avgDia";
        final String today = DateTime.now().toIso8601String().split('T')[0];
        // Look specifically for the BP log date, not the generic one!
        final bool isTaskDone = data['lastBPLogDate'] == today;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPremiumHeader(context, name, points),
                _buildResearchStatsBar(logs, avgBp),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildSectionTitle("Health Status"),
                      _buildExpandButton(context, "Expand Player Statistics"),
                      const SizedBox(height: 16),
                      _buildLatestBPCard(context, sys, dia),
                      const SizedBox(height: 16),
                      _buildExpandButton(context, "Expand Player Vitals"),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Daily Quest"),
                      _buildDailyBPQuest(context, isTaskDone),

                      const SizedBox(height: 32),
                      _buildSectionTitle("Family Status"),
                      _buildFamilySnippet(context),

                      const SizedBox(height: 32),
                      _buildSectionTitle("Game Catalog"),
                      _buildGameMenuRow(context),
                      const SizedBox(height: 32),
                      _buildSectionTitle(
                        "Health Pillars",
                        actionText: "Statistics",
                      ),
                      _buildHealthPillarsGrid(context),
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

  // --- 🏥 HEALTH PILLARS (Aligned with Research "Decks") [cite: 245-246] ---
  Widget _buildHealthPillarsGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        _pillar(
          context,
          Icons.favorite,
          "Heart",
          AppColors.error,
          const HeartStatisticsScreen(),
        ),
        _pillar(
          context,
          Icons.directions_walk,
          "Movement",
          AppColors.primary,
          const ExerciseLogScreen(),
        ),
        _pillar(
          context,
          Icons.restaurant,
          "Plate",
          AppColors.secondary,
          const DietLogScreen(),
        ),
        _pillar(
          context,
          Icons.school,
          "Education",
          AppColors.accent,
          const HealthEducationScreen(),
        ),
        _pillar(
          context,
          Icons.medication,
          "Medicine",
          AppColors.info,
          const MedicationReminderScreen(),
        ),
        _pillar(
          context,
          Icons.people,
          "Family",
          AppColors.primary,
          const FamilyCircleScreen(),
        ),
      ],
    );
  }

  Widget _pillar(
    BuildContext context,
    IconData icon,
    String title,
    Color color,
    Widget screen,
  ) {
    return HealthPillarTile(
      icon: icon,
      title: title,
      color: color,
      level: 1,
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
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
                  color: AppColors.viridis2,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
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
            color: AppColors.viridis2,
            size: 38,
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(BuildContext context, String name, int points) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 24,
        bottom: 24,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
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
                const SizedBox(height: 6),
                const Text(
                  "Ready for today's quest?",
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: AppColors.subtitle,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SyncBadge(),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.viridis4.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  "$points pts",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.viridis0,
                  ),
                ),
              ),
            ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 720;
        final children = [
          _buildMenuCard(
            context,
            title: 'Game Catalog',
            subtitle: 'All games in one place',
            icon: Icons.grid_view,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GameCatalogScreen()),
            ),
          ),
          _buildMenuCard(
            context,
            title: 'Design Your Own Game',
            subtitle: 'Create a custom quest',
            icon: Icons.design_services,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ComingSoonScreen(featureName: 'Design Your Own Game'),
              ),
            ),
            badgeLabel: 'Coming soon',
          ),
          _buildMenuCard(
            context,
            title: 'Community Statistics',
            subtitle: 'See collective progress',
            icon: Icons.bar_chart,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ComingSoonScreen(featureName: 'Community Statistics'),
              ),
            ),
            badgeLabel: 'Coming soon',
          ),
        ];

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
            const SizedBox(width: 12),
            Expanded(child: children[2]),
          ],
        );
      },
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    String? badgeLabel,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.viridis4.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.viridis0, size: 20),
                ),
                const Spacer(),
                if (badgeLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.title,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.subtitle,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: AppColors.viridis4, height: 0),
            const SizedBox(height: 12),
            const Text(
              'Tap to explore',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.subtitle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
