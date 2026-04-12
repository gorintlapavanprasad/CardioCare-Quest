import 'package:flutter/material.dart';

class AppColors {
  // Viridis Scale
  static const Color viridis0 = Color(0xFF440154);
  static const Color viridis1 = Color(0xFF3b528b);
  static const Color viridis2 = Color(0xFF21918c);
  static const Color viridis3 = Color(0xFF5ec962);
  static const Color viridis4 = Color(0xFFfde725); // Yellow button color

  // Accents & UI
  static const Color activeTeal = Color(0xFF1a7571);
  static const Color placeholder = Color(0xFF8fa0b3);
  static const Color background = Color(0xFFF7F9FC); // Soft background
  
  // Typography & Cards (Added from React CSS variables)
  static const Color title = Color(0xFF2d3a5e);
  static const Color subtitle = Color(0xFF718096);
  static const Color body = Color(0xFF4a5568);
  static const Color cardBg = Colors.white;
  static const Color cardBorder = Color.fromRGBO(33, 145, 140, 0.22);
  
  // Buttons
  static const Color btnBg = viridis4;
  static const Color btnText = viridis0;
  // ─── Re-added for backwards compatibility with older screens ───
  static const Color cardOutline = Color.fromRGBO(33, 145, 140, 0.22);
  static const LinearGradient pageBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8F5E9), Color(0xFFFFFDE7)], // Soft green to yellow
  );
}

// Helper function translated from React
Color getViridisColor(int step, int total) {
  final double t = step / total;
  if (t < 0.25) return AppColors.viridis0;
  if (t < 0.50) return AppColors.viridis1;
  if (t < 0.75) return AppColors.viridis2;
  if (t < 0.95) return AppColors.viridis3;
  return AppColors.viridis4;
}
