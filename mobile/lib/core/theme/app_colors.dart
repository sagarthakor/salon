import 'package:flutter/material.dart';

import '../brand/brand_config.dart';

/// Single source of truth for every color used in the app. No widget should
/// hard-code a `Color(0x...)` literal outside this file — reach for a
/// [Theme.of(context).colorScheme] role or one of these constants instead.
class AppColors {
  const AppColors._();

  /// The active brand's seed color, used to derive the full Material 3 color
  /// scheme (light and dark) in [AppTheme]. Defaults to deep plum — a warm,
  /// professional salon-brand color — for the standard multi-tenant app;
  /// a branded app (see [BrandConfig]) supplies its own.
  static Color get seed => BrandConfig.current.primaryColor;

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB26A00);
  static const Color danger = Color(0xFFC62828);
}
