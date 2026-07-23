// custom_option_button.dart - a tappable answer choice (like a radio button).
// Used in the sign-up form; it highlights itself when picked.

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// One selectable option row: a circle dot on the left, the answer text right.
class CustomOptionButton extends StatelessWidget {
  final String label; // the answer text to show
  final bool isSelected; // is this the chosen option?
  final VoidCallback onTap; // what to run when tapped

  const CustomOptionButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  // Draws the option. Colour and border animate when selected/deselected.
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.placeholder.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Custom Radio Indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.placeholder.withValues(alpha: 0.5),
                  width: 2,
                ),
                color: isSelected ? AppColors.primary : Colors.transparent,
              ),
              child: isSelected
                  ? const Center(child: Icon(Icons.circle, size: 8, color: Colors.white))
                  : null,
            ),
            const SizedBox(width: 16),
            
            // Label
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.primary : AppColors.body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
