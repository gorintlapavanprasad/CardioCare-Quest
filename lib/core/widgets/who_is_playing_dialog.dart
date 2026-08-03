import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

// WhoIsPlayingDialog - a small popup shown once after login that asks whether
// the participant themselves is playing, or a caregiver is helping them on the
// same device.
//
// The choice is stored in UserDataProvider.respondent (in memory, per launch)
// and used to tag every survey response (SurveyHooks.submitResponse
// `respondent`) so researchers can tell participant-entered answers apart from
// caregiver-entered ones, without changing the signed-in account.
class WhoIsPlayingDialog extends StatelessWidget {
  /// The signed-in participant's id. Chosen when "I'm the patient" is tapped
  /// so responses stay attributed to the participant.
  final String uid;

  const WhoIsPlayingDialog({super.key, required this.uid});

  /// Show the prompt once. No-ops (returns immediately) if a choice was
  /// already made this launch, so it never nags between screens. Not
  /// dismissible by tapping outside - the participant must pick one.
  static Future<void> show({
    required BuildContext context,
    required String uid,
  }) async {
    final provider = Provider.of<UserDataProvider>(context, listen: false);
    // Already answered this launch? Don't ask again.
    if (provider.respondent != null) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WhoIsPlayingDialog(uid: uid),
    );
  }

  // Record the choice on the provider and close.
  void _choose(BuildContext context, String respondent) {
    Provider.of<UserDataProvider>(context, listen: false).respondent =
        respondent;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: const Text(
        'Who is playing?',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
      ),
      content: const Text(
        'This helps us know whose answers we are saving. You can pick either '
        'one - it does not change your account.',
        style: TextStyle(color: AppColors.subtitle, fontSize: 16),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        // Full-width stacked buttons for easy tapping (audience skews older).
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _choose(context, uid),
            icon: const Icon(Icons.person),
            label: const Text('I am the patient'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 52),
              textStyle: const TextStyle(fontSize: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _choose(context, 'caregiver'),
            icon: const Icon(Icons.volunteer_activism),
            label: const Text('I am helping (caregiver)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              minimumSize: const Size(0, 52),
              textStyle: const TextStyle(fontSize: 17),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
