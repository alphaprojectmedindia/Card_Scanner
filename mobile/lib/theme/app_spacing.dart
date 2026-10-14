import 'package:flutter/material.dart';

/// Centralized spacing, padding, and border radius tokens.
class AppSpacing {
  AppSpacing._();

  // Spacing values
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;

  // Insets
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets dialogPadding = EdgeInsets.all(24.0);

  // Border Radii
  static const double radiusSmValue = 8.0;
  static const double radiusMdValue = 12.0;
  static const double radiusLgValue = 16.0;
  static const double radiusXlValue = 24.0;

  static final BorderRadius radiusSm = BorderRadius.circular(radiusSmValue);
  static final BorderRadius radiusMd = BorderRadius.circular(radiusMdValue);
  static final BorderRadius radiusLg = BorderRadius.circular(radiusLgValue);
  static final BorderRadius radiusXl = BorderRadius.circular(radiusXlValue);
  static final BorderRadius radiusFull = BorderRadius.circular(999.0);
}
