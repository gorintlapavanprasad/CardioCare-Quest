import 'package:cardio_care_quest/features/dashboard/screens/quest_choice_screen.dart';
import 'package:cardio_care_quest/features/games/location_game.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import
import '../../../core/theme/app_colors.dart';
import '../widgets/daily_task_card.dart';
import '../widgets/health_pillar_tile.dart';
import '../widgets/celebration_modal.dart';
import 'bp_log_screen.dart';

// ─── MOCK DATA ───
final List<Map<String, dynamic>> familyMembers = [
  {"name": "Dad", "initials": "DL", "systolic": 118, "diastolic": 76},
  {"name": "Mom", "initials": "ML", "systolic": 132, "diastolic": 84},
  {"name": "Grams", "initials": "GR", "systolic": 145, "diastolic": 92},
];

final List<Map<String, dynamic>> healthPillars = [
  {"icon": Icons.favorite, "title": "Heart", "progress": 75, "color": const Color(0xFF440154), "level": 3},
  {"icon": Icons.restaurant, "title": "Plate", "progress": 60, "color": const Color(0xFF3b528b), "level": 2},
  {"icon": Icons.directions_walk, "title": "Movement", "progress": 45, "color": const Color(0xFF21918c), "level": 2},
  {"icon": Icons.people, "title": "Family", "progress": 80, "color": const Color(0xFF1a5c1a), "level": 4},
  {"icon": Icons.medication, "title": "Medicine", "progress": 90, "color": const Color(0xFF1a7571), "level": 5},
  {"icon": Icons.sports_esports, "title": "Games", "progress": 50, "color": const Color(0xFF355e3b), "level": 1},
];

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _taskCompleted = false;
  String _firstName = "Explorer";
  int _xp = 0;
  bool _isLoading = true;
  Map<String, dynamic>? _latestBP;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

// Update this inside _HomeTabState in home_tab.dart

int _totalLogs = 0;
String _avgBP = "--/--";

Future<void> _loadUserData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    String? participantId = prefs.getString('participant_id');



    if (mounted) {
    setState(() {
      // ─── FIX: Default to 'Explorer' immediately so the ID never shows ───
      _firstName = "Explorer"; 
    });
  }

    // ─── CONSOLE LOG FOR DEBUGGING ───
    debugPrint("🏠 Home Loading: Participant ID found in storage: '$participantId'");

    if (participantId != null) {
      // Fetch User Profile
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(participantId) // NOTE: Document IDs are case-sensitive!
          .get();
      
      debugPrint("📄 Firestore Doc Exists: ${userDoc.exists}");

      // Fetch BP Logs
      QuerySnapshot allLogs = await FirebaseFirestore.instance
          .collection('users').doc(participantId)
          .collection('dailyLogs')
          .orderBy('timestamp', descending: true).get();

      if (mounted) {
        final userData = userDoc.data() as Map<String, dynamic>?;

          // Replace the _firstName assignment in _loadUserData with this:
String displayName = "Explorer";

if (userData != null && userData['basicInfo'] != null) {
  var firstName = userData['basicInfo']['firstName'];
  
  if (firstName != null && firstName.toString().isNotEmpty) {
    // If the name is a long Guest ID, we force it to 'Explorer'
    if (firstName.toString().startsWith("Guest") || firstName.toString().startsWith("G")) {
      displayName = "Explorer";
    } else {
      displayName = firstName.toString();
    }
  }
}

        
        setState(() {
_firstName = displayName;
          // Pull XP from the root field seen in your screenshot
          _xp = userData?['xp'] ?? 0; 
          _totalLogs = allLogs.docs.length;

          if (allLogs.docs.isNotEmpty) {
            _latestBP = allLogs.docs.first.data() as Map<String, dynamic>;
            
            int sumSys = 0;
            int sumDia = 0;
            for (var doc in allLogs.docs) {
              final data = doc.data() as Map<String, dynamic>;
              sumSys += (data['systolic'] as int? ?? 0);
              sumDia += (data['diastolic'] as int? ?? 0);
            }
            _avgBP = "${(sumSys / _totalLogs).round()}/${(sumDia / _totalLogs).round()}";

            String today = DateTime.now().toIso8601String().split('T')[0];
            _taskCompleted = allLogs.docs.first.id == today;
          }
          _isLoading = false;
        });
        debugPrint("✅ Dashboard stats updated for: $_firstName (XP: $_xp)");
      }
    } else {
      debugPrint("⚠️ Warning: No participant_id found in local storage.");
      if (mounted) setState(() => _isLoading = false);
    }
  } catch (e) {
    debugPrint("💥 Firestore Fetch Error: $e");
    if (mounted) setState(() => _isLoading = false);
  }
} 
  void _navToComingSoon(String name) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ComingSoonScreen(featureName: name)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.viridis2))
        : SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                _buildResearchStatsBar(), // ─── NEW STATS BAR ───

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildSectionTitle("Latest Heart Rate"),
                      _buildDynamicBPCard(),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Today's Quest"),
                      _buildDailyTaskCard(),
                      const SizedBox(height: 16),
                      _buildGameCard(),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Family Circle", actionText: "View All"),
                      InkWell(
                        onTap: () => _navToComingSoon("Family Circle"),
                        borderRadius: BorderRadius.circular(24),
                        child: _buildFamilyStrip(),
                      ),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Health Pillars", actionText: "Statistics"),
                      InkWell(
                        onTap: () => _navToComingSoon("Health Pillars"),
                        borderRadius: BorderRadius.circular(24),
                        child: _buildHealthPillarsGrid(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  
  Widget _buildResearchStatsBar() {
  return Container(
    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.viridis4.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.viridis4.withOpacity(0.2)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem("Total Points", "$_xp"),
        _buildStatDivider(),
        _buildStatItem("Logs", "$_totalLogs"),
        _buildStatDivider(),
        _buildStatItem("Avg BP", _avgBP),
      ],
    ),
  );
}

Widget _buildStatItem(String label, String value) {
  return Column(
    children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.subtitle, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.title)),
    ],
  );
}

Widget _buildStatDivider() {
  return Container(height: 30, width: 1, color: AppColors.viridis4.withOpacity(0.2));
}


Widget _buildDynamicBPCard() {
    final String sys = _latestBP != null ? "${_latestBP!['systolic']}" : "--";
    final String dia = _latestBP != null ? "${_latestBP!['diastolic']}" : "--";
    final String time = _latestBP != null 
        ? "Last logged: ${_latestBP!['timestamp']?.toDate().toString().split(' ')[0] ?? 'Recently'}" 
        : "No logs recorded yet";

    return InkWell(
      onTap: () => _navToComingSoon("Heart Health Logs"),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_latestBP == null ? "READY TO START" : "LATEST READING", 
                  style: const TextStyle(color: AppColors.viridis2, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(sys, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 44, color: AppColors.title)),
                    Text("/$dia", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.title.withOpacity(0.3))),
                    const SizedBox(width: 8),
                    const Text("mmHg", style: TextStyle(fontSize: 14, color: AppColors.subtitle, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(time, style: const TextStyle(fontSize: 11, color: AppColors.placeholder)),
              ],
            ),
            Icon(Icons.favorite_rounded, 
              color: _latestBP == null ? AppColors.placeholder.withOpacity(0.3) : AppColors.viridis2, 
              size: 38
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyTaskCard() {
    return DailyTaskCard(
      task: "Log your blood pressure",
      completed: _taskCompleted,
    // Inside _buildDailyTaskCard in home_tab.dart
onToggle: () async {
        // 1. Wait for the user to return from the log screen
        final bool? wasSaved = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BPLogScreen()),
        );

        if (wasSaved == true && mounted) {
          // 2. Get the ID immediately from local storage
          final prefs = await SharedPreferences.getInstance();
          String? participantId = prefs.getString('participant_id');

          if (participantId != null) {
            // 3. SNAPPY UI: Update XP and status locally so the user sees it immediately
            setState(() {
              _taskCompleted = true;
              _xp += 50; 
            });

            // 4. CELEBRATE NOW: Show the modal without waiting for the network
            showCelebrationModal(context, message: "Daily Goal Met!", xpGained: 50);

            // 5. BACKGROUND SYNC: Update Firebase and refresh the BP card numbers
            // We don't 'await' these so the UI doesn't freeze
            FirebaseFirestore.instance.collection('users').doc(participantId).update({
              'xp': FieldValue.increment(50),
            }).then((_) {
              _loadUserData(); // Refresh the latest BP numbers from the cloud
            });
          }
        }
      },
    );
  }
// Inside _buildGameCard in home_tab.dart
Widget _buildGameCard() {
  return InkWell(
   onTap: () async {
      // ─── THE REFRESH TRIGGER ───
      // We await the navigation. When the user comes back, the code resumes.
      await Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => const QuestChoiceScreen())
      );
      
      // Re-fetch everything (XP, Logs, Name) the moment they return
      if (mounted) {
        debugPrint("🏠 Returned to Home: Re-fetching telemetry data...");
        _loadUserData(); 
      }
   },
    borderRadius: BorderRadius.circular(24),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.viridis3, AppColors.viridis2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.viridis2.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          const Icon(Icons.pets, color: Colors.white, size: 32), // Changed to 'pets' icon
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Dog Walking Quest", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text("Choose your daily distance goal", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
        ],
      ),
    ),
  );
}
 
 
// Inside _buildHeader in home_tab.dart
// Update _buildHeader in home_tab.dart
Widget _buildHeader(BuildContext context) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 24, bottom: 24, left: 24, right: 24),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.94),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      border: const Border(bottom: BorderSide(color: AppColors.cardBorder)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ─── FIX 1: Wrap in Expanded to prevent the ID from pushing the XP off-screen ───
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Hello, $_firstName!",
                maxLines: 1, // Keep to one line
                overflow: TextOverflow.ellipsis, // Adds '...' if the ID is too long
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)
              ),
              const Text("Ready for today's quest?", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: AppColors.subtitle)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ─── XP BADGE ───
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.viridis4.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
          child: Text("$_xp XP", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.viridis0)),
        )
      ],
    ),
  );
}
  
  Widget _buildFamilyStrip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.cardBorder)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: familyMembers.map((m) {
          Color bpColor = _getFamilyBPColor(m['systolic'], m['diastolic']);
          return Column(children: [
            CircleAvatar(backgroundColor: bpColor.withOpacity(0.1), child: Text(m['initials'], style: TextStyle(color: bpColor, fontWeight: FontWeight.bold))),
            const SizedBox(height: 8),
            Text(m['name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text("${m['systolic']}/${m['diastolic']}", style: TextStyle(fontSize: 11, color: bpColor, fontWeight: FontWeight.w600)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildHealthPillarsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16),
      itemCount: healthPillars.length,
      itemBuilder: (context, index) {
        final p = healthPillars[index];
        return HealthPillarTile(icon: p['icon'], title: p['title'], progress: p['progress'], color: p['color'], level: p['level']);
      },
    );
  }

  Widget _buildSectionTitle(String title, {String? actionText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.title)),
          if (actionText != null) Text(actionText, style: const TextStyle(fontSize: 12, color: AppColors.subtitle, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Color _getFamilyBPColor(int sys, int dia) {
    if (sys < 120 && dia < 80) return const Color(0xFF1a5c1a);
    if (sys <= 129 && dia < 80) return AppColors.viridis2;
    if (sys <= 139 || dia <= 89) return AppColors.viridis1;
    return AppColors.viridis0;
  }
}

// ─── BUILT-IN PLACEHOLDER CLASS (FIXED) ───
class ComingSoonScreen extends StatelessWidget {
  final String featureName;
  const ComingSoonScreen({super.key, required this.featureName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        iconTheme: const IconThemeData(color: AppColors.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: AppColors.viridis2.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome_rounded, size: 64, color: AppColors.viridis2),
              ),
              const SizedBox(height: 24),
              Text("$featureName is coming soon", textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.title)),
              const SizedBox(height: 12),
              const Text("Stay tuned!", style: TextStyle(color: AppColors.subtitle, fontSize: 16, letterSpacing: 1.1)),
            ],
          ),
        ),
      ),
    );
  }
}