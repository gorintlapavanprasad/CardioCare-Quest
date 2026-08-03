// A simple placeholder page for features that aren't built yet.
// Shows a sparkle icon and "<feature> is coming soon". Reused for any
// spot that needs a friendly "not ready yet" screen.

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// The placeholder screen. Pass in the name of the feature to show.
class ComingSoonScreen extends StatelessWidget {
  final String featureName;
  const ComingSoonScreen({super.key, required this.featureName});

  // Center a sparkle icon, the "<feature> is coming soon" line, and a note.
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
              const Icon(
                Icons.auto_awesome_rounded,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                "$featureName is coming soon", 
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26, 
                  fontWeight: FontWeight.bold, 
                  color: AppColors.title
                )
              ),
              const SizedBox(height: 12),
              const Text(
                "Stay tuned!", 
                style: TextStyle(
                  color: AppColors.subtitle, 
                  fontSize: 16, 
                  letterSpacing: 1.1
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
}
