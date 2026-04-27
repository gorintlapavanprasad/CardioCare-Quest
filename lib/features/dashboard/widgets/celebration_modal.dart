import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

void showCelebrationModal(BuildContext context, {required String message, required int xpGained}) {
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
            content: _CelebrationModalContent(message: message, xpGained: xpGained),
          ),
        ),
      );
    },
  );
}

class _CelebrationModalContent extends StatefulWidget {
  final String message;
  final int xpGained;

  const _CelebrationModalContent({required this.message, required this.xpGained});
  @override
  State<_CelebrationModalContent> createState() => _CelebrationModalContentState();
}

class _CelebrationModalContentState extends State<_CelebrationModalContent> with SingleTickerProviderStateMixin {
  late AnimationController _spinController;

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
        // Matching your dashboard card border style
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
          // Close Button - Cleaned up
       Positioned(
            top: 4, // Moved inside the container
            right: 4, 
            child: IconButton(
              // Changed to dark grey for visibility
              icon: const Icon(Icons.close_rounded, color: AppColors.placeholder, size: 24),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── NEW: SUCCESS ICON WITH DASHBOARD GRADIENT ───
              RotationTransition(
                turns: _spinController,
                child: Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Switched to Viridis 2/3 (Teal/Green) for a "Success" feel
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
              const SizedBox(height: 32),
              
              // ─── NEW: XP PILL (Clean & High Contrast) ───
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_task_rounded, color: AppColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      "${widget.xpGained} XP GAINED", 
                      style: const TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w900, 
                        color: AppColors.primary,
                        letterSpacing: 1.1,
                      )
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
