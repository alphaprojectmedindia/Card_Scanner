import 'package:flutter/material.dart';

/// Centralized color palette for Digital Share.
class AppColors {
  AppColors._();

  // Brand / Primary
  static const Color primary = Color(0xFF2563EB); // Royal Blue
  static const Color primaryDark = Color(0xFF3B82F6);
  static const Color primaryContainerLight = Color(0xFFDBEAFE);
  static const Color primaryContainerDark = Color(0xFF1E3A8A);

  // Secondary
  static const Color secondary = Color(0xFF0F766E); // Teal
  static const Color secondaryDark = Color(0xFF14B8A6);
  static const Color secondaryContainerLight = Color(0xFFCCFBF1);
  static const Color secondaryContainerDark = Color(0xFF134E4A);

  // Light Surfaces
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceContainerLowLight = Color(0xFFF1F5F9);
  static const Color surfaceContainerLight = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Light Text
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textTertiaryLight = Color(0xFF94A3B8);

  // Dark Surfaces
  static const Color backgroundDark = Color(0xFF0B0F19);
  static const Color surfaceDark = Color(0xFF151D2A);
  static const Color surfaceContainerLowDark = Color(0xFF1E293B);
  static const Color surfaceContainerDark = Color(0xFF243044);
  static const Color borderDark = Color(0xFF2A374A);

  // Dark Text
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark = Color(0xFF64748B);

  // Semantic Status Colors
  static const Color success = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF22C55E);
  static const Color error = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFEF4444);
  static const Color warning = Color(0xFFD97706);
  static const Color warningDark = Color(0xFFF59E0B);
  static const Color info = Color(0xFF0284C7);
  static const Color infoDark = Color(0xFF38BDF8);

  // Neutral Accents
  static const Color neutral100 = Color(0xFFF1F5F9);
  static const Color neutral800 = Color(0xFF1E293B);
  static const Color neutral900 = Color(0xFF0F172A);
}
