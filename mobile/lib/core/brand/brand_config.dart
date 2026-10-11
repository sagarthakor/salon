import 'package:flutter/material.dart';

/// A single branded-app identity: app name, the one salon (by tenant id) it
/// is locked to, and its color scheme. `BrandConfig.current` is set once —
/// before `runApp` — by whichever `main*.dart` entrypoint is compiled, so
/// every screen and the router can ask "am I the multi-tenant app or a
/// branded single-salon app?" without threading a parameter through the
/// whole widget tree.
///
/// Adding another branded salon app later is one more `BrandConfig` value
/// here plus one more Android product flavor + entrypoint — no change to
/// any booking/availability/auth/profile/notification code, all of which
/// stays entirely brand-agnostic.
class BrandConfig {
  const BrandConfig({
    required this.appName,
    required this.singleSalon,
    this.salonName,
    this.tenantId,
    this.primaryColor = _defaultSeed,
    this.secondaryColor,
    this.logoAssetPath,
    this.brandHeaderValue,
  });

  static const Color _defaultSeed = Color(0xFF6B2E4B);

  /// Shown as the app's display title and in the login/splash chrome.
  final String appName;

  /// When true, the app is locked to exactly one salon: no discovery/search/
  /// selection UI, no owner or staff routes, and the home screen goes
  /// straight into that salon's booking flow.
  final bool singleSalon;

  /// Display-only fallback name for the fixed salon, shown before the real
  /// `Salon` (name/address/logo/contact) has loaded from
  /// `GET /customer/brand/{tenantId}`.
  final String? salonName;

  /// The tenant this app is locked to. Resolved into a `salon_id` at runtime
  /// via `SalonRepository.salonForTenant` — never a hardcoded salon/branch
  /// id, so it keeps working even if the salon's branches change.
  final String? tenantId;

  /// Seed color for [ColorScheme.fromSeed] — see `core/theme/app_theme.dart`.
  /// Defaults to the existing multi-tenant app's seed so the default brand
  /// is visually unchanged.
  final Color primaryColor;

  /// Optional accent color, reserved for brand-specific highlights.
  final Color? secondaryColor;

  /// Bundled logo asset (e.g. `assets/brand/nil_hair_port/logo.png`), if any.
  /// `null` falls back to the salon's network `logo` URL, then a placeholder.
  final String? logoAssetPath;

  /// Sent as the `X-App-Brand` request header (see `ApiClient`) so the
  /// backend's opt-in `BrandAppGuard` can enforce this app never reaches
  /// another tenant's data server-side, not just in the UI. `null` for the
  /// default multi-tenant app, which sends no header and is therefore
  /// unaffected by that guard.
  final String? brandHeaderValue;

  /// The default, unbranded multi-tenant app — today's behavior, unchanged.
  static const BrandConfig standard = BrandConfig(appName: 'Salon Booking', singleSalon: false);

  /// Nil Hair Port Unisex — locked to tenant
  /// `01m16303p8xgzejrr9ezvtvwfv` (verified against production, not the
  /// local dev database — see BRANDED_APP_ARCHITECTURE.md).
  static const BrandConfig nilHairPort = BrandConfig(
    appName: 'Nil Hair Port Unisex',
    singleSalon: true,
    salonName: 'Nil Hair Port Unisex',
    tenantId: '01m16303p8xgzejrr9ezvtvwfv',
    primaryColor: Color(0xFF6B2E4B),
    logoAssetPath: 'assets/brand/nil_hair_port/logo.png',
    brandHeaderValue: 'nil_hair_port',
  );

  /// Set exactly once, before `runApp`, by the compiled entrypoint
  /// (`main.dart` leaves this at [standard]; `main_nil_hair_port.dart` sets
  /// it to [nilHairPort]).
  static BrandConfig current = standard;
}
