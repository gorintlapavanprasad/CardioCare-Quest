import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class HealthPillarTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int progress;
  final Color color;
  final int level;

  const HealthPillarTile({
    super.key,
    required this.icon,
    required this.title,
    required this.progress,
    required this.color,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Top Accent Bar
            Positioned(top: 0, left: 0, right: 0, child: Container(height: 4, color: color)),
            
            // Level Badge
            Positioned(
              top: 12, left: 12,
              child: Text("LVL $level", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color.withValues(alpha: 0.7))),
            ),

            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 56, height: 56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progress / 100,
                          strokeWidth: 5,
                          backgroundColor: color.withValues(alpha: 0.15),
                          color: color,
                          strokeCap: StrokeCap.round,
                        ),
                        Icon(icon, color: color, size: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.title)),
                  const SizedBox(height: 4),
                  Text("$progress%", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 22, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}