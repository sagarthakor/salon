import 'package:flutter/material.dart';

/// Single source of truth for every color used in the app. No widget should
/// hard-code a `Color(0x...)` literal outside this file — reach for a
/// [Theme.of(context).colorScheme] role or one of these constants instead.
class AppColors {
  const AppColors._();

  /// Deep plum — a warm, professional salon-brand seed color used to derive
  /// the full Material 3 color scheme (light and dark) in [AppTheme].
  static const Color seed = Color(0xFF6B2E4B);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB26A00);
  static const Color danger = Color(0xFFC62828);
}
