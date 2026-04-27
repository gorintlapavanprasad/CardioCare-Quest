import 'package:flutter/material.dart';

class AppColors {
  // ─── PRIMARY PALETTE: Accessible & Calming (for elderly hypertension users) ───
  
  // Primary: Soothing Green (reduces anxiety, calming for heart health)
  static const Color primary = Color(0xFF2d7d6d); // Forest green
  static const Color primaryLight = Color(0xFFe8f5f1); // Very soft green
  static const Color primaryDark = Color(0xFF1a4d45); // Deep green
  
  // Secondary: Warm Teal (medically soothing, accessible)
  static const Color secondary = Color(0xFF1b7373); // Teal
  static const Color secondaryLight = Color(0xFFe0f5f5); // Soft teal
  static const Color secondaryDark = Color(0xFF0d4545); // Dark teal
  
  // Accent: Warm Gold (for achievement/celebration, not jarring)
  static const Color accent = Color(0xFFd4a574); // Warm gold
  static const Color accentLight = Color(0xFFf5ebe0); // Soft gold
  
  // Status Colors
  static const Color success = Color(0xFF2d7d6d); // Green
  static const Color warning = Color(0xFFd4a574); // Gold
  static const Color error = Color(0xFF8b3a3a); // Muted red
  static const Color info = Color(0xFF1b7373); // Teal
  
  // Typography & UI
  static const Color title = Color(0xFF1a2332); // Dark charcoal (HIGH contrast ✓)
  static const Color subtitle = Color(0xFF546e7a); // Muted slate
  static const Color body = Color(0xFF37474f); // Medium gray
  static const Color placeholder = Color(0xFFb0bec5); // Light gray
  
  // Backgrounds
  static const Color background = Color(0xFFF8F9FA); // Soft white (reduces eye strain)
  static const Color cardBg = Colors.white;
  static const Color cardBorder = Color.fromRGBO(45, 125, 109, 0.15); // Subtle green border
  
  // Legacy Viridis (for backward compatibility & health pillar colors)
  static const Color viridis0 = Color(0xFF1a2332); // Replaced dark purple
  static const Color viridis1 = Color(0xFF546e7a); // Slate
  static const Color viridis2 = Color(0xFF1b7373); // Teal
  static const Color viridis3 = Color(0xFF2d7d6d); // Green
  static const Color viridis4 = Color(0xFFd4a574); // Gold (softer than yellow)
  
  // Buttons & CTA
  static const Color btnBg = primary; // Green primary
  static const Color btnText = Colors.white;
  
  // Deprecated borders (kept for compatibility)
  static const Color cardOutline = Color.fromRGBO(45, 125, 109, 0.15);
  
  static const LinearGradient pageBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFe8f5f1), Color(0xFFe0f5f5)], // Soft green to teal
  );
}

// Helper function for color progression (updated for new palette)
Color getProgressColor(int step, int total) {
  final double t = step / total;
  if (t < 0.25) return AppColors.primaryDark;
  if (t < 0.50) return AppColors.primary;
  if (t < 0.75) return AppColors.secondary;
  if (t < 0.95) return AppColors.accent;
  return AppColors.success;
}

