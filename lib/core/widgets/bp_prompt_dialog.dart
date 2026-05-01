import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

/// Modal prompt that asks for a quick BP reading after a game ends.
///
/// Replaces the old manual-BP-log flow on the dashboard. Now that there's
/// no "Log your blood pressure" daily-task card, this dialog is the only
/// participant-facing BP entry point — fired by both [TwineGameHost] and
/// [TwineQuestionnaireHost] when a game ends naturally.
///
/// Save → writes via [DailyLogHooks.logBP] (mood defaulted to neutral) and
/// applies optimistic dashboard updates via [PointsHooks].
/// Skip → dismisses without recording.
///
/// Either way the host pops back to the dashboard afterwards.
class BpPromptDialog extends StatefulWidget {
  final String uid;

  const BpPromptDialog({super.key, required this.uid});

  /// Show the prompt and await its result. Returns `true` if the user
  /// saved a reading, `false` on Skip OR if the once-per-day gate
  /// suppressed the prompt. Caller decides what to do next (typically:
  /// pop the game route regardless).
  ///
  /// **Once-per-day gate:** if `userData.lastBPLogDate == today`, the
  /// prompt is suppressed and `false` is returned without showing UI.
  /// `DailyLogHooks.logBP` (called on Save) updates `lastBPLogDate` to
  /// today, so subsequent game completions on the same day skip the
  /// prompt. Skip does NOT update the gate — if the participant skips
  /// the first prompt of the day, they'll still be asked after their
  /// next game (so research data isn't lost to one accidental tap).
  static Future<bool> show({
    required BuildContext context,
    required String uid,
  }) async {
    if (uid.isEmpty) return false;

    final today = DateTime.now().toIso8601String().split('T')[0];
    final userData =
        Provider.of<UserDataProvider>(context, listen: false).userData;
    if (userData?['lastBPLogDate'] == today) {
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BpPromptDialog(uid: uid),
    );
    return result ?? false;
  }

  @override
  State<BpPromptDialog> createState() => _BpPromptDialogState();
}

class _BpPromptDialogState extends State<BpPromptDialog> {
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _systolic.dispose();
    _diastolic.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final sys = int.tryParse(_systolic.text.trim());
    final dia = int.tryParse(_diastolic.text.trim());
    if (sys == null || sys <= 0 || dia == null || dia <= 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter both numbers, or tap Skip.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // mood=2 (neutral) — the post-game prompt intentionally skips mood
      // capture to keep the interaction short. Full mood logging is
      // available elsewhere if a researcher needs it.
      //
      // HealthKit / Health Connect snapshots are NOT captured here.
      // They're written by `HealthHooks.logSnapshot` from the Twine
      // hosts on every game end — independent of the BP prompt's
      // once-per-day gate so research data parity is preserved.
      await DailyLogHooks.logBP(
        uid: widget.uid,
        systolic: sys,
        diastolic: dia,
        mood: 2,
      );

      if (!mounted) return;
      // Optimistic dashboard updates so the points pill / latest reading
      // refreshes immediately instead of waiting on the offline-queue
      // replay round-trip.
      PointsHooks.applyIncrements(context, const {
        'points': 50,
        'totalSessions': 1,
        'measurementsTaken': 1,
      });
      PointsHooks.applySets(context, {
        'lastSystolic': sys,
        'lastDiastolic': dia,
        'lastBPLogDate': DateTime.now().toIso8601String().split('T')[0],
      });

      navigator.pop(true);
    } catch (e) {
      debugPrint('BP prompt save error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: const Text(
        'Quick BP check',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Enter your blood pressure if you have it handy. Tap Skip if you don't.",
            style: TextStyle(color: AppColors.subtitle, fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _systolic,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Systolic (top number)',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _diastolic,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Diastolic (bottom number)',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.subtitle,
            minimumSize: const Size(100, 48),
          ),
          child: const Text('Skip'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(100, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
