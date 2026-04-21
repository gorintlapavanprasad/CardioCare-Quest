import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardio_care_quest/user_data_manager.dart';
import 'package:cardio_care_quest/features/games/dog_walking.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/daily_task_card.dart';
import '../widgets/health_pillar_tile.dart';
import '../widgets/celebration_modal.dart';
import '../widgets/coming_soon_screen.dart';
import 'bp_log_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserDataProvider>(
      builder: (context, provider, child) {
        if (provider.userData == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.viridis2)),
          );
        }

      final data = provider.userData!;
        
        // ─── THE FIX: Use the Provider getters instead of raw map keys ───
        final name = provider.firstName; 
        final xp = provider.xp; 
        final distance = provider.distanceTraveled; 
        final logs = provider.totalSessions; 
        
        // Data retention fields from Deep Sync
        final String sys = data['lastSystolic']?.toString() ?? "--";
        final String dia = data['lastDiastolic']?.toString() ?? "--";
        final String today = DateTime.now().toIso8601String().split('T')[0];
        final bool isTaskDone = data['lastLogDate'] == today;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPremiumHeader(context, name, xp),
                _buildResearchStatsBar(xp, logs, distance),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildSectionTitle("Health Status"),
                      _buildLatestBPCard(context, sys, dia),
                      
                      const SizedBox(height: 32),
                      _buildSectionTitle("Daily Quest"),
                      _buildDailyBPQuest(context, isTaskDone),
                      
                      const SizedBox(height: 32),
                      _buildSectionTitle("Active Quests"),
                      // 🏃 ACTIVE: Dog Walking [cite: 20, 302]
                      _buildDogWalkingCard(context),
                      
                      const SizedBox(height: 16),
                      // ⏳ COMING SOON: Full Research Catalog 
                      _buildComingSoonGame(context, "Salt Sludge", Icons.science_rounded, AppColors.viridis0),
                      const SizedBox(height: 16),
                      _buildComingSoonGame(context, "Diet Game", Icons.restaurant_menu_rounded, AppColors.viridis3),
                      const SizedBox(height: 16),
                      _buildComingSoonGame(context, "Vascular Village", Icons.location_city_rounded, AppColors.viridis1),
                      const SizedBox(height: 16),
                      _buildComingSoonGame(context, "Bingo Bash", Icons.grid_on_rounded, AppColors.viridis4),
                      
                      const SizedBox(height: 32),
                      _buildSectionTitle("Health Pillars", actionText: "Statistics"),
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
        _pillar(context, Icons.favorite, "Heart", const Color(0xFF440154), "Heart Statistics"),
        _pillar(context, Icons.directions_walk, "Movement", const Color(0xFF21918c), "Movement Quest"),
        _pillar(context, Icons.restaurant, "Plate", const Color(0xFF3b528b), "Diet Quest"),
        _pillar(context, Icons.school, "Education", const Color(0xFF5ec962), "Health Education"),
        _pillar(context, Icons.medication, "Medicine", const Color(0xFF1a7571), "Medication Tracker"),
        _pillar(context, Icons.people, "Family", const Color(0xFF1a5c1a), "Family Circle"),
      ],
    );
  }

  Widget _pillar(BuildContext context, IconData icon, String title, Color color, String routeName) {
    return HealthPillarTile(
      icon: icon,
      title: title,
      color: color,
      level: 1,
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ComingSoonScreen(featureName: routeName)
      )),
    );
  }

  // --- 📱 UI HELPERS ---

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
              const Text("LATEST READING", style: TextStyle(color: AppColors.viridis2, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline, // ─── FIXED TYPO HERE
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(sys, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: AppColors.title)),
                  Text("/$dia", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.title.withOpacity(0.3))),
                  const SizedBox(width: 8),
                  const Text("mmHg", style: TextStyle(fontSize: 14, color: AppColors.subtitle, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const Icon(Icons.favorite_rounded, color: AppColors.viridis2, size: 38),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(BuildContext context, String name, int xp) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 24, bottom: 24, left: 24, right: 24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Hello, $name!", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2D3A5E))),
            const Text("Ready for today's quest?", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: AppColors.subtitle)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.viridis4.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
            child: Text("$xp XP", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.viridis0)),
          )
        ],
      ),
    );
  }

  Widget _buildResearchStatsBar(int xp, int logs, dynamic distance) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.viridis4.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem("XP", "$xp"),
          _buildStatDivider(),
          _buildStatItem("Logs", "$logs"),
          _buildStatDivider(),
          _buildStatItem("Distance", "${distance}m"),
        ],
      ),
    );
  }

  Widget _buildDogWalkingCard(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LocationGame(targetDistance: 500))),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.viridis3, AppColors.viridis2]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: AppColors.viridis2.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: const Row(
          children: [
            Icon(Icons.pets, color: Colors.white, size: 32), 
            SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Dog Walking Quest", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              Text("Convert your steps to research data", style: TextStyle(color: Colors.white70, fontSize: 13)),
            ])),
            Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoonGame(BuildContext context, String title, IconData icon, Color color) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ComingSoonScreen(featureName: title))),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.cardBorder)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: AppColors.title, fontSize: 18, fontWeight: FontWeight.bold)),
              const Text("Quest arriving soon", style: TextStyle(color: AppColors.subtitle, fontSize: 12)),
            ])),
            const Icon(Icons.lock_clock_rounded, color: AppColors.placeholder, size: 24),
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
        final bool? wasSaved = await Navigator.push(context, MaterialPageRoute(builder: (_) => const BPLogScreen()));
        if (wasSaved == true) { showCelebrationModal(context, message: "Goal Met!", xpGained: 50); }
      },
    );
  }

  Widget _buildSectionTitle(String title, {String? actionText}) {
    return Padding(padding: const EdgeInsets.only(bottom: 12.0), child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.title)),
        if (actionText != null) Text(actionText, style: const TextStyle(fontSize: 12, color: AppColors.subtitle, fontStyle: FontStyle.italic)),
      ],
    ));
  }

  Widget _buildStatItem(String label, String value) {
    return Column(children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.subtitle)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.title)),
    ]);
  }

  Widget _buildStatDivider() { return Container(height: 30, width: 1, color: AppColors.viridis4.withOpacity(0.2)); }
}