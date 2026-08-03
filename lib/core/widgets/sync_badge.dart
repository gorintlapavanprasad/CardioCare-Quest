import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/services/activity_logs.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

// SyncBadge - a little pill in the corner that shows if data is saved to the cloud.
//
// Green = everything synced. Amber with a number = that many items still waiting
// (usually because there's no internet). Tap it for details, long-press to force
// a sync. Handy for a researcher to know it's safe to take the device offline.

/// Badge surfacing the combined offline-queue state to the researcher running
/// the workshop station. It aggregates two queues:
///
///  * [LoggingService] - telemetry events (Hive box `event_queue`).
///  * [OfflineQueue]   - research-grade Firestore writes (BP, exercise, meal,
///                       medication, quest completions, surveys, etc.).
///
/// Visual states:
///  * Idle, queue empty            → green pill with "Synced".
///  * Sync in progress             → green pill with spinner + "Syncing N".
///  * Offline / queue has entries  → amber pill with cloud_off + count.
///
/// Tap opens a SnackBar summary. Long-press forces a sync attempt on both
/// queues.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  // The two things that hold unsent data: telemetry events and Firestore writes.
  LoggingService get _logger => GetIt.instance<LoggingService>();
  OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  // Watches both queues' counts and "is syncing" flags, and rebuilds the badge
  // whenever any of them changes, so the number is always up to date.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _logger.pendingCount,
      builder: (context, eventCount, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _queue.pendingCount,
          builder: (context, writeCount, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _logger.isSyncing,
              builder: (context, eventSyncing, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _queue.isSyncing,
                  builder: (context, writeSyncing, _) {
                    return _buildContent(
                      context,
                      total: eventCount + writeCount,
                      events: eventCount,
                      writes: writeCount,
                      syncing: eventSyncing || writeSyncing,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // Draws the actual pill: picks the icon + color for the current state, then
  // shows a spinner (while syncing) or an icon, plus the pending count.
  Widget _buildContent(
    BuildContext context, {
    required int total,
    required int events,
    required int writes,
    required bool syncing,
  }) {
    final IconData icon;
    final Color color;

    // Choose look by state: syncing -> spinner, all-clear -> green, else amber.
    if (syncing) {
      icon = Icons.sync;
      color = AppColors.viridis2;
    } else if (total == 0) {
      icon = Icons.cloud_done_outlined;
      color = AppColors.viridis2;
    } else {
      icon = Icons.cloud_off_outlined;
      color = AppColors.accent;
    }

    return Semantics(
      label: syncing
          ? 'Syncing $total items'
          : total == 0
              ? 'All data synced'
              : '$total items pending sync',
      button: true,
      child: GestureDetector(
        onTap: () => _showStatus(
          context,
          total: total,
          events: events,
          writes: writes,
          syncing: syncing,
        ),
        onLongPress: () => _triggerManualSync(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (syncing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(icon, color: color, size: 18),
              if (total > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Tap handler: pops up a short message explaining the current sync status.
  void _showStatus(
    BuildContext context, {
    required int total,
    required int events,
    required int writes,
    required bool syncing,
  }) {
    final String message;
    if (syncing) {
      message = 'Syncing $total item(s) to Firebase ($writes writes, '
          '$events events)...';
    } else if (total == 0) {
      message = 'Everything is synced. Safe to take device offline.';
    } else {
      message = '$total item(s) waiting to sync ($writes writes, $events '
          'events). Long-press to retry now, or wait for the network.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Long-press handler: tells both queues to try sending everything right now.
  Future<void> _triggerManualSync(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Forcing sync on both queues...'),
        duration: Duration(seconds: 2),
      ),
    );
    await Future.wait([
      _logger.syncToFirestore(),
      _queue.syncToFirestore(),
    ]);
  }
}
