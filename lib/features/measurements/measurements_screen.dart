import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/features/games/game_stories.dart';

/// Reachable from the "Measurements" Health Pillar tile on the dashboard.
///
/// Streams the user's `healthSnapshots` sub-collection — one doc per
/// game-end, written by [HealthHooks.logSnapshot]. Each doc carries a
/// HealthKit / Health Connect vitals snapshot (or just metadata if the
/// participant has no paired wearable).
///
/// The BP-prompt-once-per-day gate doesn't suppress writes here —
/// researchers get a row for every game completion regardless of
/// whether the user logged BP. See `project_healthkit_integration.md`.
class MeasurementsScreen extends StatelessWidget {
  const MeasurementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = Provider.of<UserDataProvider>(context).uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Measurements'),
      ),
      body: uid.isEmpty
          ? const _EmptyState()
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(FirestorePaths.userData)
                  .doc(uid)
                  .collection('healthSnapshots')
                  .orderBy('collectedAt', descending: true)
                  .limit(60)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];

                if (docs.isEmpty) {
                  return const _EmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MeasurementCard(data: data),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _MeasurementCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MeasurementCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final tsRaw = data['collectedAt'];
    DateTime? when;
    if (tsRaw is Timestamp) when = tsRaw.toDate();

    final gameId = data['gameId'] as String?;
    final game = gameId != null ? GameCatalog.getGame(gameId) : null;
    final gameTitle = game?.title ?? gameId ?? 'Game';

    final hasWearable = data['hasWearableData'] == true;

    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (game != null) ...[
                Icon(game.iconData, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  gameTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.title,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            when != null
                ? DateFormat('MMM d, yyyy • h:mm a').format(when)
                : 'Date unknown',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.subtitle,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: AppColors.cardBorder,
          ),
          const SizedBox(height: 12),
          if (hasWearable)
            _SnapshotChips(data: data)
          else
            const Text(
              'No wearable data captured at this game.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.subtitle,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

class _SnapshotChips extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SnapshotChips({required this.data});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    final hr = data['heartRate'];
    if (hr is num) {
      chips.add(_chip(Icons.favorite_outline, '${hr.round()} bpm'));
    }
    final restHr = data['restingHeartRate'];
    if (restHr is num) {
      chips.add(_chip(Icons.bedtime_outlined, '${restHr.round()} bpm rest'));
    }
    final hrv = data['heartRateVariability'];
    if (hrv is num) {
      chips.add(_chip(Icons.show_chart, '${hrv.round()} ms HRV'));
    }
    final steps = data['stepsToday'];
    if (steps is num) {
      chips.add(_chip(Icons.directions_walk, '${steps.toInt()} steps'));
    }
    final energy = data['activeEnergyToday'];
    if (energy is num) {
      chips.add(_chip(
        Icons.local_fire_department_outlined,
        '${energy.round()} kcal',
      ));
    }
    final exMin = data['exerciseMinutesToday'];
    if (exMin is num) {
      chips.add(_chip(Icons.fitness_center, '${exMin.toInt()} exercise min'));
    }
    final spo2 = data['bloodOxygen'];
    if (spo2 is num) {
      chips.add(_chip(Icons.bloodtype_outlined, '${spo2.round()}% O₂'));
    }

    if (chips.isEmpty) {
      return const Text(
        'Snapshot recorded but no readings available.',
        style: TextStyle(
          fontSize: 13,
          color: AppColors.subtitle,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.body,
            fontWeight: FontWeight.w500,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.monitor_heart_outlined,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No measurements yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.title,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Play any game to start logging your vitals. We capture a snapshot from your Apple Watch / wearable at the end of every game.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.subtitle, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
