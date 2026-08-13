import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

// BpPromptDialog - asks for a BP reading after a game ends.
// The only BP entry point now; shown at most once per day. Always skippable.
class BpPromptDialog extends StatefulWidget {
  final String uid;

  const BpPromptDialog({super.key, required this.uid});

  // Show the prompt. Returns true if the user saved a reading, false on Skip or
  // if they already logged BP today. Skipping does NOT close the daily gate,
  // so they'll be asked again after the next game.
  static Future<bool> show({
    required BuildContext context,
    required String uid,
  }) async {
    if (uid.isEmpty) return false;

    // Today's date as plain text like "2026-07-21".
    final today = DateTime.now().toIso8601String().split('T')[0];
    final userData =
        Provider.of<UserDataProvider>(context, listen: false).userData;
    // Already logged today? Skip quietly.
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
  // Text boxes for the two BP numbers.
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  bool _saving = false; // true while the save is running (disables buttons).

  @override
  void dispose() {
    _systolic.dispose();
    _diastolic.dispose();
    super.dispose();
  }

  // Validate the numbers, save BP, update the dashboard, then close.
  Future<void> _save() async {
    // Grab context references now, before any awaits.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Turn the typed text into numbers. Both must be valid and positive.
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

    setState(() => _saving = true); // show the spinner, block double-taps.
    try {
      // mood=2 (neutral) keeps the interaction short. HealthKit snapshots are
      // handled separately by the game host, not here.
      await DailyLogHooks.logBP(
        uid: widget.uid,
        systolic: sys,
        diastolic: dia,
        mood: 2,
      );

      if (!mounted) return; // popup already closed? stop here.
      // Update points and the latest reading in-memory so the dashboard refreshes now.
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

      navigator.pop(true); // close popup, tell caller we saved.
    } catch (e) {
      // Save failed; let them try again.
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
