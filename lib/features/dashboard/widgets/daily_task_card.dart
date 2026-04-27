import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class DailyTaskCard extends StatelessWidget {
  final String task;
  final bool completed;
  final VoidCallback onToggle;

  const DailyTaskCard({
    super.key,
    required this.task,
    required this.completed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: completed ? AppColors.viridis3.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: completed ? AppColors.viridis3.withValues(alpha: 0.4) : AppColors.cardBorder,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: completed ? AppColors.viridis3.withValues(alpha: 0.1) : AppColors.viridis1.withValues(alpha: 0.05),
              blurRadius: 18, offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: completed
                  ? const Icon(Icons.check_circle, color: AppColors.viridis3, size: 32, key: ValueKey('check'))
                  : Icon(Icons.radio_button_unchecked, color: AppColors.viridis1.withValues(alpha: 0.3), size: 32, key: const ValueKey('empty')),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                task,
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold,
                  color: completed ? const Color(0xFF1a6b1a) : AppColors.title,
                ),
              ),
            ),
            if (!completed)
              const Icon(Icons.arrow_forward, size: 20, color: AppColors.placeholder)
          ],
        ),
      ),
    );
  }
}
