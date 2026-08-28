# Owner App Architecture

Phase 8 extends the Phase 7 Flutter project (`mobile/`) with a role-aware owner/admin surface. It is **not** a second app: same `pubspec.yaml`, same `ApiClient`, same `SecureStorage`, same theme, same `AuthController`/session, same `GoRouter` instance. A `salon_owner`/`super_admin` session simply lands on a different set of screens than a `customer` session, decided once, client-side, from the real backend role.

## Role-aware navigation, not a security boundary

`AppRole` (`lib/features/auth/data/models/app_role.dart`) groups the backend's literal `UserResource.role` string into four navigation buckets:

```dart
enum AppRole { customer, ownerAdmin, staff, unknown }
```

`AppRole.fromBackendRole(role)` maps `customer` → `customer`, `salon_owner`/`super_admin` → `ownerAdmin`, `staff` → `staff`, and anything else → `unknown` (sent to `/login`). At the time this phase was written, `staff` still routed to a placeholder screen — Phase 9 later built the real staff app behind that same enum value (the member was renamed from Phase 8's original `staffPending` once a real destination existed; see `STAFF_APP_ARCHITECTURE.md`), with no change to this classification logic itself.

This classification decides **only** which screen `core/routing/app_router.dart`'s `redirect` callback shows. It is never treated as, or substituted for, real authorization: every single API call the owner screens make goes through the same `TenantManagementController::managedTenant()`/`viewableTenant()` checks, the same `StaffPolicy`, the same tenant-scoping (`BelongsToTenant`) that Phases 2–6 already enforce. A bug in `AppRole` classification could at worst show a user the wrong *screen*; it could never grant them a real permission the backend doesn't independently agree to. `test/widgets/owner_router_authorization_test.dart` verifies the redirect behavior end-to-end for every backend role value, including an unrecognized one.

The router's `redirect` computes a per-role home route (`ownerAdmin` → `/owner`, `customer` → `/home`, `staff` → `/staff`, `unknown` → `/login`) and guard checks per route family: an `ownerAdmin` session pushed into a customer-only route (`/home`, `/booking/*`, `/bookings/*`, `/profile/edit`) is redirected back to `/owner`, and any non-`ownerAdmin` session pushed into `/owner/*` is redirected back to its own home route (Phase 9 added the equivalent `/staff/*` guard).

## Directory layout

`lib/features/owner/` holds one subfolder per concern, each following the same `data/{models,repositories}` + `presentation/{providers,screens}` split as every Phase 7 feature: `dashboard/`, `bookings/`, `staff/`, `services/`, `customers/`, `branches/`, `salon/`, and `shell/` (the bottom-nav `OwnerShell` + a `MoreTab` for the screens that don't fit five bottom-nav slots — Services/Categories, Branches, Salon profile, Booking settings, and log out). See `FLUTTER_ARCHITECTURE.md` for the full tree.

Shared Phase 7 infrastructure is **reused, never duplicated**: the same `ApiClient`, `SecureStorage`, `AppTheme`, `PrimaryButton`/`LoadingView`/`ErrorView`/`EmptyView`, and — notably — the same `BookingRepository` and `Booking`/`BookingStatus` models as the customer app. The owner-side booking operations (`ownerBookings`, `ownerBookingDetails`, `confirmBooking`, `updateBookingStatus`, `ownerCancelBooking`, `ownerRescheduleBooking`) were added as new methods on the existing `BookingRepository` rather than a parallel `OwnerBookingRepository`, since it's the same model and envelope, only a different base path (`/bookings*` vs `/customer/bookings*`).

## Dashboard

`GET /dashboard/summary` (new in Phase 8 — see `MOBILE_API_INTEGRATION.md`) is the dashboard's only data source. Every number shown — today's booking counts by status, today's revenue, the next upcoming appointment, active/on-leave-today staff counts, total/new-this-month customers — is a real, server-computed value from `DashboardController::summary`. Nothing on this screen is a client-side estimate, a cached stale figure, or a hard-coded placeholder; where a metric wasn't derivable from an existing query cheaply, it was added to the new endpoint rather than faked (e.g. "staff on leave today" required a dedicated `StaffLeave` date-range query no list endpoint already did).

## Booking management

`OwnerBookingsListScreen` lists bookings via the shared `BookingRepository.ownerBookings()` with server-side filters (`date`, `status`, `branch_id`, `staff_id`, `customer_id`) and the same "did the last page come back full" load-more heuristic as the customer app's `MyBookingsController` (see `MOBILE_API_INTEGRATION.md`'s pagination-metadata note — it applies identically here). `OwnerBookingDetailsScreen` renders `Booking.status.nextActions` (a UI-hint transition matrix mirroring `App\Enums\BookingStatus::canTransitionTo`) as the set of action buttons to offer — confirm, check-in, in-service, complete, cancel (with a reason prompt), or no-show — and always re-fetches after a transition rather than optimistically updating local state. The backend independently re-validates every transition regardless of which buttons the client happened to show; `nextActions` only avoids offering a button that would always `409`. `OwnerRescheduleScreen` mirrors the customer app's `RescheduleScreen` (same availability-fetch-then-pick-a-slot flow, same `409`-conflict handling that refreshes availability and asks the user to pick again) against `POST /bookings/{id}/reschedule` instead of the customer path — owner/staff reschedule and cancel always bypass the customer-facing cancellation window, because they're a different, broader-access endpoint, never a client-supplied bypass flag.

## Staff management

Full CRUD (`StaffRepository`, extending the Phase 4 `/staff*` APIs) plus per-staff service assignment, working hours, breaks, and leave — one screen each, matching the four separate Phase 4 sub-resources. Staff photo upload uses `ApiClient.postMultipart()`, a shared helper (also used by service/category images) that sends Laravel's `_method=PUT` override field on a `POST`, since PHP cannot parse a multipart body on `PUT`/`PATCH` directly. `image_picker` (the one new package this phase added) supplies the gallery picker.

## Service / category management

`OwnerServiceRepository` wraps the Phase 3 `/services*` and `/service-categories*` APIs — list/filter/CRUD for both, again with `postMultipart` for the optional service/category image.

### Service media: image, description, Instagram reference

A targeted feature addition on top of Phase 3's plain CRUD, giving customers a real reason to trust a listing: `service_form_screen.dart` now also collects an optional Instagram post/reel/video URL and supports removing an existing image, not just replacing it. The image picker (tap the circle avatar) and description field already existed; what changed is that the preview now actually renders (the backend previously returned a raw storage path under `image`, which was never a loadable URL — see `API_DOCUMENTATION.md`, "Service media" — the field is now `image_url`, a real public URL), and a "Remove photo" button appears whenever there's something to remove. All of this reuses the existing multipart upload path (`postMultipart`) and the existing field-error display convention (`_fieldErrors['instagram_url']`) — no new screen, no new provider. See `FLUTTER_ARCHITECTURE.md`, "Service media", for the exact widget/repository changes.

### Master catalog: a ready-made starting service list

A new owner no longer sees an empty Services screen — their tenant's first branch is automatically provisioned with a professional starting catalog (Hair, Beard & Shaving, Facial & Skin, Threading, Waxing, Nails, Makeup, Spa — audience-organized, ~75 services) server-side, the moment `POST /branches` succeeds. No wizard, no setup step the owner has to click through; see `MASTER_CATALOG_ARCHITECTURE.md` for the full provisioning design. `service_list_screen.dart` gained an audience filter bar (All/Men/Women/Unisex/Kids — the same grouping a customer sees) and a quick ON/OFF `Switch` per service so an owner can narrow the catalog down to what they actually offer without opening the edit form for each one — tap Edit only to change a price, duration, description, image, or Instagram link. This is the entire "owner customization" step the feature promises: choose which groups you offer (turn services off), adjust price/duration where needed, add your own photo and Instagram link.

## Customer management

`OwnerCustomerRepository` wraps the Phase 5 `/customers*` APIs — CRUD, search/status/gender filtering, and owner-only notes (`/customers/{id}/notes`). `GET /customers/{id}/summary` had been a known placeholder since Phase 5 (hard-coded zeros, explicitly flagged at the time as "not yet wired to `bookings`," because the booking engine didn't exist yet). Phase 8 fixes it: `CustomerController::summary` now derives `total_visits`, `completed_appointments`, `cancelled_appointments`, `no_show_count`, `total_spent`, `last_visit_at`, and `upcoming_appointment` from the customer's real booking history. This was a required fix, not an optional cleanup — the owner app's customer-details screen needed real numbers, and showing fabricated zeros next to genuinely-derived dashboard numbers would have been an inconsistent, misleading UI.

## Branch management

`OwnerBranchRepository` wraps the Phase 2 `/branches*` APIs — CRUD, working hours, and holidays, each its own screen mirroring the shape of the Phase 2 endpoints exactly.

## Salon / settings management

`OwnerSalonRepository` wraps `GET|POST|PUT|PATCH /salon` (profile) and `GET|PUT|PATCH /salon/settings` (a flat key-value map). The settings screen edits both the Phase 2 configuration keys and the Phase 6 booking-engine keys (`slot_interval_minutes`, `min_advance_booking_minutes`, `max_advance_booking_days`, `booking_buffer_minutes`, `cancellation_window_minutes`) in one form, since the backend already stores them together under the same settings endpoint (see `BOOKING_ENGINE.md` for what each numeric setting controls).

### Salon Instagram profile (distinct from Service media above)

A small, targeted addition to the existing Salon Profile screen — not a new screen: `salon_profile_screen.dart`'s already-shared create/edit form gained one Instagram profile URL field, view/add/edit/remove, saved through the same `OwnerSalonRepository.create()`/`update()` calls every other salon field already goes through. This is the salon's *own* official Instagram page (e.g. `instagram.com/primehairstudio`) — entirely separate from a service's `instagram_url` (a specific post/reel; see "Service media" above), which stays on `service_form_screen.dart` and is unaffected by this addition. Removing the URL is just clearing the text field and saving — `update()` was changed to always send `instagram_url` (even empty), the one field on this screen that needed to support genuine removal rather than "leave unchanged if untouched". See `FLUTTER_ARCHITECTURE.md`, "Salon Instagram profile", for the exact repository/widget changes.

## Reports & analytics (Phase 13)

`lib/features/owner/reports/` — a new `data/{models,repositories}` + `presentation/{providers,screens,widgets}` feature, reached from `MoreTab` (`Reports`), never a sixth bottom-nav tab. `ReportsRepository` wraps the ten new `GET /reports/*` endpoints; every screen renders server-computed `summary`/`series`/`breakdown` data exactly as returned — no aggregation, filtering, or sorting happens client-side. A single `reportFilterProvider` (`StateProvider<ReportFilter>`) is shared across every report screen, so moving from Revenue to Bookings keeps the same date range/branch selection instead of resetting it; `ReportScaffold<T>` is the shared loading/error/pull-to-refresh shell every report screen wraps its body in. Charts use `fl_chart` (the one new dependency this phase adds) purely to draw backend-provided `{date, value}` series — see `REPORTING_ANALYTICS_ARCHITECTURE.md` for the full backend design, metric definitions, and timezone handling.

## Billing (Phase 10)

`SubscriptionRepository` wraps the Phase 10 `/subscription*` APIs. The Subscription screen shows real plan/price/status/dates for all six subscription states and is reachable from the "More" menu regardless of subscription status — a business route returning `402` doesn't redirect the owner anywhere, it's just an `ApiException` with `ApiErrorType.paymentRequired` that a screen can surface. Checkout opens a browser-based Razorpay checkout (not a native SDK — see `SAAS_BILLING_ARCHITECTURE.md`, "Flutter payment flow," for why) and only shows success once `GET /subscription` confirms `status: active` server-side; the app never marks a payment successful from a client-side gateway callback alone. Full detail, including the payment-verification/idempotency design, lives in `SAAS_BILLING_ARCHITECTURE.md`.

## Explicitly not built in Phase 8

The dedicated staff mobile app (built in Phase 9 — see `STAFF_APP_ARCHITECTURE.md`), payment gateway integration and subscriptions/billing (built in Phase 10 — see `SAAS_BILLING_ARCHITECTURE.md`), any notification channel (push/SMS/WhatsApp/email beyond what Sanctum/Laravel already send), coupons/discounts, membership programs, marketing campaigns, inventory management, advanced/exportable reporting beyond the dashboard's real-time counters (built in Phase 13 — see `REPORTING_ANALYTICS_ARCHITECTURE.md`), and any AI-driven feature. None of these had a stable, already-built dependent contract at the time Phase 8 was written — see `MODULE_ROADMAP.md`.

## Testing

`test/widgets/owner_router_authorization_test.dart` builds the real `routerProvider` for every backend role and asserts actual redirect behavior, not just the `AppRole.fromBackendRole` mapping in isolation. Model-parsing, repository-behavior (including that Dart 3.8's `'key': ?value` null-aware map syntax genuinely omits a filter rather than sending a literal `null` — the pattern used throughout every owner repository's list/filter/create/update methods), and widget tests for every owner screen live alongside the Phase 7 suite in `mobile/test/`; see `TESTING.md` for the full breakdown and current test count.

## Coupons / memberships / loyalty (Phase 12)

The owner surface gained four screens off the "More" tab — Coupons, Membership plans, Customer memberships (with a grant flow), and Loyalty (search + manual adjustment) — under `features/owner/pricing/`, all owner/super-admin only (the backend's `managedTenant()` gate, not a client-side check, is what actually enforces this). Booking detail screens (shared with the staff app) now show a subtotal/coupon/membership/loyalty breakdown line whenever a booking has a non-zero discount. See `LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md`.

## Security + performance hardening (Phase 14)

No new owner-app feature — a code audit fixed a debug-only logging gap (a plaintext password/gateway-signature could appear in a debug build's network log; now redacted) and narrowed one over-broad `ref.watch` on the dashboard tab. The backend's new general API rate limit (120/min per user, 10/min on checkout endpoints — see `SECURITY_HARDENING.md`) is generous enough that normal owner-app usage, including the Reports section's date-range/filter changes, should never hit it in practice. See `FLUTTER_ARCHITECTURE.md`, "Security + performance hardening (Phase 14)", for the exact changes.

## Owner onboarding: how someone actually becomes an owner

Everything documented above in this file assumes a `salon_owner` session already exists. Until now, nothing in Phases 1–15 actually produced one outside a seeder or `tinker` — confirmed by a dedicated investigation after real-device testing surfaced the gap (see "Owner onboarding" in `PROJECT_ARCHITECTURE.md`). `POST /api/v1/auth/register-owner` closes it: a new `RegisterOwnerScreen` (owner name/email/password + salon name) reached via a new `RegisterChoiceScreen` off `LoginScreen`'s "Register" link. On success, the caller lands in exactly this same Owner App — no new shell, no new bottom-nav tab — because the backend's `TenantMembershipRole::SALON_OWNER` membership it creates is indistinguishable, from every existing owner screen's point of view, from one a seeder created. What *does* differ is where the router sends this first session — see the next section. See `FLUTTER_ARCHITECTURE.md`, "Owner onboarding: self-service salon-owner registration", and `API_DOCUMENTATION.md`, "Owner onboarding", for the backend/client detail.

## Owner onboarding: salon setup

A freshly self-registered owner has a `Tenant` + trial subscription but no `Salon` yet — that's a separate, deliberate step (see `SALON_ARCHITECTURE.md`), and real-device testing found the app had no safe way to guide someone through it: `BranchController::store()` assumed a `Salon` already existed and threw a raw `ModelNotFoundException` the moment a new owner tried to add their first branch. Three changes close this, from least to most disruptive:

1. **Router redirect (primary path).** `AuthController.registerOwner()` sets a new `AuthState.hasSalonProfile = false` deterministically (a just-created tenant can never have a salon yet — no extra request). `app_router.dart`'s redirect resolves a `salon_owner`'s `homeFor` to `/owner/salon` instead of `/owner` whenever `hasSalonProfile == false`, so the preferred flow (`Owner Registration → "Let's set up your salon" → Salon Profile → Owner Dashboard`) actually happens. This flag is routing-only, never re-derived on session restore (an existing owner's `hasSalonProfile` stays `null`, so this never affects them), and `SalonProfileScreen` calls `AuthController.markSalonProfileComplete()` (setting it `true`) and navigates to `/owner` once the salon is actually created.
2. **Dashboard setup banner (safety net).** For an owner who navigates away before finishing setup (e.g. force-closes the app right after registering — `hasSalonProfile` is never re-checked on session restore, so redirect #1 won't catch this), `DashboardTab` independently watches `ownerSalonProvider`; a `404` there renders a "Set up your salon profile" card linking to `/owner/salon`, and any other outcome (loading, an unrelated error, or a real salon) shows nothing — this never gets in an already-set-up owner's way. The "More" menu itself is left in its existing order (Branches still appears before Salon profile) — deliberately, since backend requirement #3 below makes that ordering safe regardless.
3. **Backend `requireSalon()` (last line of defense).** `TenantManagementController::requireSalon()` replaces `BranchController::store()`'s direct `Salon::query()->firstOrFail()`. A missing Salon now returns a normal `422` (`"Please set up your salon profile before adding a branch."`), never a `500`/raw exception — see `API_DOCUMENTATION.md`, "Setup-completion gap (fixed)", for the exact response and why `/services` and `/service-categories` needed no equivalent change. `SalonProfileScreen` itself gained the ability to *create* a salon in the first place (`OwnerSalonRepository.create()`, `POST /salon`) — it previously only supported editing one that already existed; a `404` from `GET /salon` now renders that create form (with a short "Let's set up your salon" banner) instead of a generic error view, so the raw `"No query results for model [App\Models\Salon]."` string is never shown to a user under any path.

None of this touches `SalonController`'s own `GET/PATCH /salon` `firstOrFail()` calls — a `404` there is the semantically correct "this resource doesn't exist yet" response, and the client-side fix (treat it as "show create form") lives entirely in `SalonProfileScreen`, not the backend.
