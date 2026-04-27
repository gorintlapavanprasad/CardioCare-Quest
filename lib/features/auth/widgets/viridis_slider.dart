import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class ViridisSlider extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String minLabel;
  final String maxLabel;
  final ValueChanged<int> onChanged;

  const ViridisSlider({
    super.key,
    required this.value,
    this.min = 1,
    this.max = 7,
    required this.minLabel,
    required this.maxLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Floating Number Bubble ───
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: Container(
            key: ValueKey<int>(value),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.viridis4, AppColors.viridis3],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.viridis4.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              value.toString(),
              style: const TextStyle(
                fontFamily: 'PlayfairDisplay', // Falls back gracefully if not loaded yet
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF3b0a52), // Dark purple text
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ─── Custom Slider Track ───
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.primary.withValues(alpha: 0.2),
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.1),
            trackHeight: 6,
            tickMarkShape: SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (val) => onChanged(val.toInt()),
          ),
        ),

        // ─── Min / Max Labels ───
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(minLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.placeholder)),
              Text(maxLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.placeholder)),
            ],
          ),
        ),
      ],
    );
  }
}
