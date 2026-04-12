import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class BPCard extends StatelessWidget {
  final int systolic;
  final int diastolic;
  final String trend;
  final String timestamp;

  const BPCard({
    super.key,
    required this.systolic,
    required this.diastolic,
    this.trend = 'stable',
    required this.timestamp,
  });

  Map<String, dynamic> _getBPStatus() {
    if (systolic < 120 && diastolic < 80) {
      return {'label': 'Normal', 'accent': const Color(0xFF5ec962), 'bg': const Color(0xFF5ec962).withValues(alpha: 0.10)};
    }
    if (systolic <= 129 && diastolic < 80) {
      return {'label': 'Elevated', 'accent': const Color(0xFF21918c), 'bg': const Color(0xFF21918c).withValues(alpha: 0.10)};
    }
    if (systolic <= 139 || (diastolic >= 80 && diastolic <= 89)) {
      return {'label': 'Stage 1', 'accent': const Color(0xFF3b528b), 'bg': const Color(0xFF3b528b).withValues(alpha: 0.10)};
    }
    return {'label': 'Stage 2', 'accent': const Color(0xFF440154), 'bg': const Color(0xFF440154).withValues(alpha: 0.10)};
  }

  @override
  Widget build(BuildContext context) {
    final status = _getBPStatus();
    final Color accent = status['accent'];
    final Color bg = status['bg'];
    
    IconData trendIcon = trend == 'up' ? Icons.trending_up : trend == 'down' ? Icons.trending_down : Icons.remove;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.3)),
          right: BorderSide(color: accent.withValues(alpha: 0.3)),
          bottom: BorderSide(color: accent.withValues(alpha: 0.3)),
          left: BorderSide(color: accent, width: 6), 
        ),
        boxShadow: [BoxShadow(color: bg, blurRadius: 28, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.favorite, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text("BLOOD PRESSURE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: accent.withValues(alpha: 0.3))),
                child: Text(status['label'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent)),
              )
            ],
          ),
          const SizedBox(height: 16),
          // FIX: Removed Baseline dependency so it renders safely on all devices
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("$systolic", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 48, color: accent, height: 1.0)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0, left: 4, right: 4),
                child: Text(" / ", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: AppColors.placeholder)),
              ),
              Text("$diastolic", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 48, color: accent, height: 1.0)),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Text("mmHg", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.placeholder)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(trendIcon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(timestamp, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.placeholder)),
            ],
          )
        ],
      ),
    );
  }
}