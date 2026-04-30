import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';

class MedicationReminderScreen extends StatefulWidget {
  const MedicationReminderScreen({super.key});

  @override
  State<MedicationReminderScreen> createState() => _MedicationReminderScreenState();
}

class _MedicationReminderScreenState extends State<MedicationReminderScreen> {
  int _streak = 0;
  bool _takenToday = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return;
    
    try {
      final doc = await FirebaseFirestore.instance.collection(FirestorePaths.userData).doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _streak = data['medicationStreak'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading streak: $e');
    }
  }

  Future<void> _saveMedicationStatus(bool taken) async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final String today = DateTime.now().toIso8601String().split('T')[0];
      final int newStreak = taken ? _streak + 1 : 0;

      await DailyLogHooks.logMedication(
        uid: uid,
        taken: taken,
        currentStreak: _streak,
      );

      if (mounted) {
        // Optimistic local update — see bp_log_screen for rationale.
        PointsHooks.applyIncrements(context, {'points': taken ? 20 : 5});
        PointsHooks.applySets(context, {
          'medicationStreak': newStreak,
          'lastLogDate': today,
        });
        setState(() {
          _streak = newStreak;
          _takenToday = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('SAVE ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _takeMedication() {
    _saveMedicationStatus(true);
  }

  void _missMedication() {
    _saveMedicationStatus(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication Reminder'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Did you take your medication today?',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.title, height: 1.3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 64),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (!_takenToday)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _takeMedication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('Yes', style: TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _missMedication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.background,
                        foregroundColor: AppColors.title,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: AppColors.cardBorder, width: 2),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('No', style: TextStyle(fontSize: 24)),
                    ),
                  ),
                ],
              )
            else
              _buildStreakCounter(),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakCounter() {
    return Column(
      children: [
        if (_streak > 0)
          Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: const Icon(Icons.local_fire_department, color: AppColors.accent, size: 120),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                '$_streak Day Streak!',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Excellent! Protecting your streak protects your heart.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.subtitle, fontSize: 16),
              )
            ],
          )
        else
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 48),
                SizedBox(height: 16),
                Text(
                  "That is okay.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                ),
                SizedBox(height: 12),
                Text(
                  "It happens to the best of us. Setting an alarm on your phone or keeping your pills by your toothbrush can help you remember tomorrow.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: AppColors.primary, height: 1.5),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

