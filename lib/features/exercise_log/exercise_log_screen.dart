import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

class ExerciseLogScreen extends StatefulWidget {
  const ExerciseLogScreen({super.key});

  @override
  State<ExerciseLogScreen> createState() => _ExerciseLogScreenState();
}

class _ExerciseLogScreenState extends State<ExerciseLogScreen> {
  String? _selectedActivity;
  final TextEditingController _timeController = TextEditingController();
  bool _isSaved = false;

  final List<Map<String, dynamic>> _activities = [
    {'name': 'Walking', 'icon': Icons.directions_walk},
    {'name': 'Housework', 'icon': Icons.cleaning_services},
    {'name': 'Yard Work', 'icon': Icons.yard},
    {'name': 'Running', 'icon': Icons.directions_run},
    {'name': 'Cycling', 'icon': Icons.directions_bike},
    {'name': 'Other', 'icon': Icons.accessibility_new},
  ];

  @override
  void initState() {
    super.initState();
    _timeController.addListener(_onTimeChanged);
  }

  @override
  void dispose() {
    _timeController.removeListener(_onTimeChanged);
    _timeController.dispose();
    super.dispose();
  }

  void _onTimeChanged() {
    setState(() {});
  }

  Future<void> _saveExercise() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return;
    if (_selectedActivity == null || _timeController.text.isEmpty) return;

    setState(() => _isSaved = true);

    try {
      final int minutes = int.parse(_timeController.text);
      String today = DateTime.now().toIso8601String().split('T')[0];

      final eventId = const Uuid().v4();
      await GetIt.instance<OfflineQueue>().enqueueBatch([
        PendingOp.set(
          '${FirestorePaths.userData}/$uid/${FirestorePaths.dailyLogs}/$today',
          {
            'exerciseActivity': _selectedActivity,
            'exerciseMinutes': minutes,
            'exerciseTimestamp': OfflineFieldValue.nowTimestamp(),
            'date': today,
          },
          merge: true,
        ),
        PendingOp.update('${FirestorePaths.userData}/$uid', {
          'points': OfflineFieldValue.increment(50),
          'exercisesLogged': OfflineFieldValue.increment(1),
          'totalExerciseMinutes': OfflineFieldValue.increment(minutes),
          'lastLogDate': today,
        }),
        PendingOp.set(
          '${FirestorePaths.events}/$eventId',
          {
            'id': eventId,
            'userId': uid,
            'event': 'exercise_logged',
            'activity': _selectedActivity,
            'durationMinutes': minutes,
            'timestamp': OfflineFieldValue.nowTimestamp(),
            'syncedAt': OfflineFieldValue.nowTimestamp(),
          },
        ),
      ]);

      if (mounted) {
        await Provider.of<UserDataProvider>(context, listen: false).fetchUserData();
        if (mounted) Navigator.of(context).pop(50);
      }
    } catch (e) {
      debugPrint('SAVE ERROR: $e');
      if (mounted) setState(() => _isSaved = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Movement Log'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildLogView(),
    );
  }

  Widget _buildLogView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What kind of movement did you do today?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.title),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.3,
            ),
            itemCount: _activities.length,
            itemBuilder: (context, index) {
              final activity = _activities[index];
              final isSelected = _selectedActivity == activity['name'];
              return GestureDetector(
                onTap: () => setState(() => _selectedActivity = activity['name']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.cardBorder,
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        activity['icon'],
                        size: 40,
                        color: isSelected ? Colors.white : AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        activity['name'],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppColors.title,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'For about how long? (minutes)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.title),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _timeController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'e.g., 20',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.favorite, color: AppColors.secondary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Every minute of movement helps keep your blood vessels flexible and your heart strong.',
                    style: TextStyle(color: AppColors.secondaryDark, fontSize: 14, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _selectedActivity != null && _timeController.text.isNotEmpty && !_isSaved
                  ? _saveExercise
                  : null,
              child: _isSaved ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Movement'),
            ),
          ),
        ],
      ),
    );
  }
}

