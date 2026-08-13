import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

// WhoIsPlayingDialog - asks once after login whether the participant is using the
// device themselves or a caregiver is helping. Tags survey responses accordingly.
class WhoIsPlayingDialog extends StatelessWidget {
  // The participant's id, used when "I am the patient" is tapped.
  final String uid;

  const WhoIsPlayingDialog({super.key, required this.uid});

  // Show the prompt once per launch. Not dismissible; the player must pick one.
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
        // Full-width buttons are easier to tap for older users.
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
