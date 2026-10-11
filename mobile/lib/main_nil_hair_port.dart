import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/brand/brand_config.dart';
import 'main.dart';

/// Entrypoint for the "Nil Hair Port Unisex" branded app (Android product
/// flavor `nilHairPort`, see `android/app/build.gradle.kts`). Sets the one
/// process-wide [BrandConfig] before anything else runs, then boots the
/// exact same [SalonCustomerApp] the default app uses — every screen,
/// provider, and repository is shared; only [BrandConfig.current] differs.
void main() {
  BrandConfig.current = BrandConfig.nilHairPort;
  runApp(const ProviderScope(child: SalonCustomerApp()));
}
