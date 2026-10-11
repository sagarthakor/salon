# Branded App Architecture

This document covers the "Nil Hair Port Unisex" branded customer app — an additive, single-tenant Android build of the existing Phase 7 Flutter customer app (`mobile/`), plus the small backend surface it needed. It reuses **100%** of the existing multi-tenant SaaS: no booking, pricing, availability, tenant-isolation, or authentication logic was duplicated or forked. Everything below cross-references `MULTI_TENANCY.md`, `BOOKING_ENGINE.md`, `CUSTOMER_ARCHITECTURE.md`, and `FLUTTER_ARCHITECTURE.md` rather than repeating them.

## 1. Purpose

Nil Hair Port Unisex (owner: Nilesh Valand, tenant `01m16303p8xgzejrr9ezvtvwfv`) wanted its own customer-facing Android app — its own name, icon, and Play Store listing — rather than sending customers to the shared multi-tenant discovery app where it's one of many salons. The requirement was a **separate installable app**, not a re-skin toggle inside the existing app, while changing nothing about how the salon is actually managed (Nilesh keeps using the existing owner app) or how bookings/pricing/availability work server-side.

## 2. Existing multi-tenant SaaS architecture (unchanged)

One Laravel backend, shared database, row-level tenancy (`MULTI_TENANCY.md`). One Flutter codebase already served three roles from the same `pubspec.yaml`/`ApiClient`/`AuthController`/`GoRouter` instance, distinguished only by the authenticated user's backend role (`OWNER_APP_ARCHITECTURE.md`, `STAFF_APP_ARCHITECTURE.md`): the default "Salon Booking" customer app lets a customer discover any active salon (`CustomerSalonController::discover()`), pick a branch, and book. This branded app is a fourth variant of that same idea — not a fourth codebase.

## 3. Separate Nil Hair Port branded app architecture

The branded app is the **same Flutter project, same Dart source tree**, compiled from a different entrypoint (`lib/main_nil_hair_port.dart`) into a different Android product flavor (`nilHairPort`). A single process-wide value, `BrandConfig.current` (`mobile/lib/core/brand/brand_config.dart`), is set once before `runApp()` and read by the router, theme, API client, and home screen to decide "am I the multi-tenant app or a locked single-salon app?" Nothing else in the app — auth, booking, availability, cart, membership, loyalty, notifications, profile — has any brand-conditional code at all; those features are shared verbatim.

```dart
class BrandConfig {
  final String appName;
  final bool singleSalon;      // true => no discovery, no owner/staff UI
  final String? tenantId;      // '01m16303p8xgzejrr9ezvtvwfv' for nilHairPort
  final Color primaryColor;
  final String? logoAssetPath; // null => falls back to the salon's network logo
  final String? brandHeaderValue; // sent as X-App-Brand; null for the default app
}
```

`BrandConfig.standard` (the default multi-tenant app) has `singleSalon: false`, `tenantId: null`, `brandHeaderValue: null` — every conditional in the app keys off these, so the default app's behavior is provably unchanged (`mobile/test/brand/brand_config_test.dart` asserts this directly).

## 4. Android product flavor

`mobile/android/app/build.gradle.kts` declares one flavor dimension, `"brand"`, with two flavors:

- **`standard`** — inherits `applicationId`/`app_name` from `defaultConfig` unchanged (`com.hairsaloon.salon_customer`, `salon_customer`). Byte-for-byte today's app.
- **`nilHairPort`** — `applicationId = com.hairsaloon.salon_customer.nilhairport`, `app_name = "Nil Hair Port Unisex"` (via a Gradle `resValue`, referenced from `AndroidManifest.xml` as `android:label="@string/app_name"` instead of a literal string). It also carries its own launcher icons at `mobile/android/app/src/nilHairPort/res/mipmap-*/ic_launcher.png` (all five densities), which Gradle's source-set overlay merges over the default flavor's icons automatically — no manifest wiring needed for that part.

Adding a future branded salon app is one more `create("...")` block here (a new `applicationId` + `app_name` + optional icon overlay) plus one more `BrandConfig` value (§16) — never a change to `standard`'s.

## 5. Separate Flutter entrypoint

```dart
// lib/main_nil_hair_port.dart
void main() {
  BrandConfig.current = BrandConfig.nilHairPort;
  runApp(const ProviderScope(child: SalonCustomerApp()));
}
```

This is the entire entrypoint. It sets the one static field and boots the exact same `SalonCustomerApp` widget tree `lib/main.dart` does — same `MaterialApp.router`, same `AppTheme`, same `routerProvider`. Building the flavor without also pointing Flutter at this entrypoint (`-t lib/main_nil_hair_port.dart`) would compile the multi-tenant app under the Nil Hair Port `applicationId`, so both must be specified together (§17).

## 6. App routing

`core/routing/app_router.dart`'s single `GoRouter` instance branches on `BrandConfig.current.singleSalon` in three places:

- **Auth screens**: a single-salon app has no owner/customer choice, so `register-choice` is skipped straight to `register`.
- **Post-login redirect**: a non-`customer` role (owner/admin or staff) is sent to `/branded-blocked` instead of `/owner` or `/staff` — those routes don't exist in this build at all (see below), so there is nothing to redirect to.
- **Route list**: every `/owner/*` and `/staff/*` `GoRoute` is wrapped in `if (!BrandConfig.current.singleSalon) [...]`. In a `nilHairPort` build, those routes are not merely hidden by a guard — they are absent from the compiled route table, so no direct/deep-link navigation can ever reach them.

`/home`'s single tab-0 widget is swapped: `BrandedHomeTab` (fixed salon, no discovery) replaces `HomeTab` (search/list) when `singleSalon` is true; `MyBookingsScreen` and `ProfileScreen` (tabs 1–2) are identical in both builds. `mobile/test/brand/branded_router_test.dart` exercises this end-to-end — real widget pumps of the real router, for a customer, an owner, and a staff session — not just a unit test of the boolean.

## 7. Backend tenant guard

`app/Support/BrandAppGuard.php` is a small, opt-in, additive check — it exists specifically so tenant-locking isn't a client-side-only UI convention. A branded app sends `X-App-Brand: nil_hair_port` on every request (added once, in `ApiClient`'s request interceptor, from `BrandConfig.current.brandHeaderValue`). Any controller that resolves a tenant from a client-supplied branch/salon/booking ID calls:

```php
app(BrandAppGuard::class)->assertTenant($request, $resolvedTenantId);
```

immediately after resolving that ID (`AvailabilityController::index`, `CustomerBookingController::store/pricePreview/ownedBooking`, `CustomerMembershipController::plans`, `CustomerServiceController::index`). The guard:

- No-ops if `X-App-Brand` is absent — every existing caller (the default customer app, owner app, staff app) sends no such header and is completely unaffected.
- 403s with "Unknown app brand" if the header names a slug not in `config/brand_apps.php`.
- 403s with "This app is not available for the requested salon" if the resolved tenant doesn't match the one tenant that brand is locked to.

`config/brand_apps.php` is the single source of truth mapping brand slug → tenant ID:

```php
return ['nil_hair_port' => '01m16303p8xgzejrr9ezvtvwfv'];
```

One new endpoint, `GET /api/v1/customer/brand/{tenant}` (`CustomerSalonController::byTenant`), resolves the one active `Salon` for a tenant ID — the same public/cross-tenant read pattern `discover()` already established (see `MULTI_TENANCY.md`, "Customer salon discovery"), just keyed by tenant instead of returning every active salon. This is how the app turns "tenant ID baked into the build" into a `salon_id`, without ever hard-coding a salon or branch ID — if Nil Hair Port's branch or salon record ever changes, the branded app needs no rebuild.

## 8. Tenant isolation

The guard is a second, independent layer on top of every tenant-isolation guarantee `MULTI_TENANCY.md` already documents — it never replaces or weakens them. Concretely: `assertTenant()` runs *after* a controller has already resolved `$branchModel`/`$booking`/etc. through the existing `withoutGlobalScope('tenant')->findOrFail()` pattern those endpoints used before this feature; a cross-tenant ID still 404s or resolves to the wrong tenant exactly as before, and the guard then additionally 403s if that tenant isn't the branded app's own. `tests/Feature/BrandedSalonApiTest.php` (8 tests) proves both properties: cross-tenant access is denied under the brand header, and — critically — the *absence* of the header reproduces every existing behavior unchanged (the regression proof that the default multi-tenant app was not touched).

## 9. Customer authentication

Unchanged. Sanctum token auth, the same `POST /register` / `POST /login` / `GET /me` endpoints, the same `AuthController` and `authControllerProvider` on the Flutter side. A branded app is not a separate user pool or a separate login flow — a Nil Hair Port customer is an ordinary `role: customer` user row, indistinguishable in the `users` table from a customer of any other tenant. What's new is only that `ApiClient` additionally attaches `X-App-Brand` alongside the existing bearer token on every request.

## 10. Service catalog flow

Unmodified. `CustomerServiceController::index` (`GET /branches/{branch}/services`) is the same audience-filterable (`Male`/`Female`/`Unisex`/`Kids`) service-catalog endpoint every customer app build calls, now with one added line — `BrandAppGuard::assertTenant()` — after the branch is resolved. The Flutter side's `BookingServiceSelectionScreen`, service cards, images, and Instagram links are entirely shared code; nothing about how a service is rendered or filtered differs between the standard and branded builds.

## 11. Cart flow

Unmodified. `BookingCartScreen` and the underlying cart state (`booking_providers.dart`) are shared, brand-agnostic code — a branded build never touches this layer.

## 12. Booking flow

Unmodified booking creation/read path, with the same guard addition as the catalog: `CustomerBookingController::store()` and `pricePreview()` call `assertTenant()` right after resolving `$branch`, and `ownedBooking()` (used by every "read my own booking" action) calls it right after resolving `$booking`. The booking-creation logic itself — slot validation, pricing, coupon/membership/loyalty application, snapshotting (`BOOKING_ENGINE.md`) — is untouched.

## 13. Availability

Unmodified `AvailabilityService`/`AvailabilityController::index` (`GET /branches/{branch}/availability`), with the same one-line guard addition after `$branchModel` is resolved.

## 14. Pricing authority

Server-side only, as everywhere else in this codebase: `BookingPricingService` computes the authoritative price (subtotal, coupon, membership, loyalty redemption) from the current `Service` rows and the branch's own tenant context — the branded app's Flutter side never computes or displays a price it derived itself, and a booking's stored price is never influenced by which app (branded or standard) created it. The `X-App-Brand` header changes *which tenants a request may target*; it has no effect on how any tenant's prices are computed.

## 15. Owner/customer separation

A branded app is customer-only by design (§3, §6): the `nilHairPort` build's compiled route table contains no `/owner/*` or `/staff/*` routes at all. If an owner or staff account (e.g. Nilesh's own login) is used inside the branded app, the router sends it to `BrandedRoleBlockedScreen` — a plain "this app is for customers only, use the main Salon Booking app to manage this salon" explainer with a log-out button, never a crash or a blank screen. Nilesh continues managing Nil Hair Port entirely through the existing, unmodified multi-tenant owner app; the branded app was never intended to replace it.

## 16. Supporting future branded salon apps

Every piece above was built as a pattern, not a one-off:

1. Backend: add one line to `config/brand_apps.php` (`'new_slug' => '<tenant-id>'`). No controller changes — every guarded endpoint already checks against whatever brands exist in config.
2. Flutter: add one `BrandConfig` value in `brand_config.dart` (name, tenant ID, color, optional logo asset), one `main_<slug>.dart` entrypoint (copy `main_nil_hair_port.dart`, change one line).
3. Android: one more `create("<slug>")` flavor block in `build.gradle.kts` (`applicationId` + `app_name`), optionally an icon overlay directory.
4. Zero changes to booking/availability/auth/profile/notification/cart code — that code has never had, and should never need, brand-conditional logic.

## 17. Build instructions

**Run against local dev** (unchanged default, matches `FLUTTER_SETUP.md`):
```
flutter run -t lib/main_nil_hair_port.dart --flavor nilHairPort
```

**Build a debug APK against a specific API base URL** — the API URL is never hard-coded; it's a `--dart-define` (see `mobile/lib/core/config/app_config.dart`, `MOBILE_API_INTEGRATION.md`):
```
flutter build apk --debug \
  --flavor nilHairPort \
  -t lib/main_nil_hair_port.dart \
  --dart-define=API_BASE_URL=https://salon.primecodesystems.in/api/v1
```
Output: `build/app/outputs/flutter-apk/app-nilHairPort-debug.apk`, signed with the Flutter debug keystore (`signingConfigs.debug`, unchanged from the default app — no release keystore exists or is needed for a debug build).

**Do not** omit `--flavor nilHairPort` or `-t lib/main_nil_hair_port.dart` — building `flutter build apk --debug` alone compiles the `standard` flavor (today's multi-tenant app) with `com.hairsaloon.salon_customer`, not Nil Hair Port.

## 18. Current Firebase/FCM status

**Not configured, for either app build.** This predates the branded-app work entirely: `mobile/lib/features/notifications/data/repositories/device_token_repository.dart` documents that `firebase_messaging`/`firebase_core` were deliberately not added without a real Firebase project's `google-services.json`/`GoogleService-Info.plist` (see `NOTIFICATION_ARCHITECTURE.md`, "What Phase 11 does NOT claim"). There is no `google-services.json` anywhere in this repository for the `standard` or `nilHairPort` flavor, and the Gradle files apply no Google Services plugin. The backend's push-provider abstraction (`App\Services\Notifications\Providers\FcmHttpV1Provider`) exists and is ready to send once real Firebase credentials are supplied, but no client-side token is ever generated or registered today for any build. Adding real push notifications for Nil Hair Port (or any app) requires a real Firebase project and its credential files — out of scope for this feature and not fabricated here.

## Explicitly not built in this phase

A real Nil Hair Port logo asset (the app currently falls back to the salon's `logo` URL from its `Salon` record, via `BrandConfig.nilHairPort.logoAssetPath: null` — see `BrandedHomeTab`'s `_SalonHeaderCard`), iOS support (no Xcode scheme/target exists for any flavor — Android only, see below), Firebase/FCM (§18), a Play Store listing, and a release/signed build (this phase produces a debug APK only; a release build needs its own signing keystore, deliberately not created here).

### iOS

Out of scope for this phase. The branded-flavor mechanism (`BrandConfig` + a dedicated entrypoint) is platform-agnostic and would extend to iOS via Xcode build configurations/schemes the same way Android product flavors were used, but no iOS scheme, bundle identifier, or entitlement was created. Build iOS support only if/when explicitly requested.

## Testing

Backend: `tests/Feature/BrandedSalonApiTest.php` — 8 tests covering brand resolution, the guard's allow/deny/unknown-brand paths, and the no-header regression proof. Flutter: `mobile/test/brand/brand_config_test.dart` (`BrandConfig` value assertions) and `mobile/test/brand/branded_router_test.dart` (real router/widget pumps for customer/owner/staff sessions in a `nilHairPort`-configured app). See `TESTING.md` for the full suite's current totals.
