// The "well done!" popup shown after finishing something. A spinning
// sparkle badge and a message. It pops in with a little bounce + fade
// to feel rewarding.

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// Show the celebration popup. Pass the message to show.
void showCelebrationModal(BuildContext context, {required String message}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: AppColors.title.withValues(alpha: 0.6), // Darker overlay for better focus
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (context, animation1, animation2) => const SizedBox(),
    transitionBuilder: (context, a1, a2, widget) {
      return ScaleTransition(
        scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
        child: FadeTransition(
          opacity: a1,
          child: AlertDialog(
            backgroundColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            elevation: 0,
            content: _CelebrationModalContent(message: message),
          ),
        ),
      );
    },
  );
}

// Stateful only so the spinning badge can animate.
class _CelebrationModalContent extends StatefulWidget {
  final String message;

  const _CelebrationModalContent({required this.message});
  @override
  State<_CelebrationModalContent> createState() => _CelebrationModalContentState();
}

class _CelebrationModalContentState extends State<_CelebrationModalContent> with SingleTickerProviderStateMixin {
  late AnimationController _spinController;

  // Start the badge spinning (loops forever) when the popup appears.
  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32), // Improved padding
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.viridis2.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.viridis2.withValues(alpha: 0.15), 
            blurRadius: 40, 
            offset: const Offset(0, 20)
          )
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
       Positioned(
            top: 4, // Moved inside the container
            right: 4, 
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.placeholder, size: 24),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _spinController,
                child: Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.viridis3, AppColors.viridis2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.viridis2.withValues(alpha: 0.4), 
                        blurRadius: 20, 
                        offset: const Offset(0, 8)
                      )
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 42),
                ),
              ),
              const SizedBox(height: 28),
              
              Text(
                widget.message, 
                textAlign: TextAlign.center, 
                style: const TextStyle(
                  fontSize: 28, 
                  fontWeight: FontWeight.w900, 
                  color: AppColors.title,
                  letterSpacing: -0.5,
                )
              ),
              const SizedBox(height: 12),
              const Text(
                "You're making great progress!",
                style: TextStyle(color: AppColors.subtitle, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
