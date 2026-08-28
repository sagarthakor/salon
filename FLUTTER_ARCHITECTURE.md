# Flutter Architecture

Phase 7 adds the **customer** mobile app (`mobile/`), built with Flutter 3.47.1 (stable) / Dart 3.13.1, targeting Android and iOS from one codebase. Phase 8 extends the same project — never a second app — with a role-aware **owner/admin** surface. Phase 9 extends it a third time with a real **staff** surface. Phase 10 adds a **billing** feature to the owner surface — subscription status, plan selection, a server-authoritative payment flow, and payment/invoice history. See `MODULE_ROADMAP.md`, `OWNER_APP_ARCHITECTURE.md`, `STAFF_APP_ARCHITECTURE.md`, and `SAAS_BILLING_ARCHITECTURE.md`.

## Project location

```
hair-saloon/
  (Laravel backend, unchanged at the repo root)
  mobile/                 ← one Flutter app, customer + owner/admin + staff
    lib/
    android/
    ios/
    test/
```

The backend was **not** moved into a `backend/` subdirectory. It was already the repository root with an established git history and no version control at all until Phase 4 introduced it; relocating hundreds of existing files purely for a directory-naming convention would violate "do not move/delete the existing Laravel application unnecessarily" for no functional benefit. `mobile/` sits as a sibling directory instead — the backend is untouched.

## Directory structure

```
lib/
  core/            # cross-cutting infrastructure, no feature knowledge
    config/        # AppConfig — dart-define environment values
    network/       # ApiClient (Dio), ApiException/ApiExceptionMapper
    storage/       # SecureStorage (flutter_secure_storage wrapper)
    routing/       # go_router + auth-based redirects
    theme/         # AppTheme, AppColors, AppSpacing
    utils/         # date/time formatting helpers
  shared/
    widgets/       # LoadingView/ErrorView/EmptyView, PrimaryButton
  features/
    auth/          # login, register, splash, session state
    salon/         # customer's salons + branch selection
    services/      # branch service catalog
    booking/        # availability, booking flow, my bookings, details, reschedule
                    #   — BookingRepository and BookingStatus are shared by both
                    #     the customer and owner surfaces (extended in place in
                    #     Phase 8, never duplicated)
    profile/       # customer's own profile (view/edit)
    home/          # customer bottom-nav shell + home tab
    owner/         # Phase 8 — owner/admin surface, one subfolder per concern:
      dashboard/    #   GET /dashboard/summary
      bookings/     #   owner booking list/filter/details/status actions/reschedule
      staff/        #   staff CRUD + services + working hours + breaks + leave
      services/     #   service + category CRUD
      customers/    #   customer CRUD + notes + summary
      branches/     #   branch CRUD + working hours + holidays
      salon/        #   salon profile + booking-engine settings
      shell/        #   owner bottom-nav shell (OwnerShell) + "More" menu
      billing/      # Phase 10 — subscription/plans/checkout/payment+invoice history
        data/models/         #   Plan, Subscription, Payment, Invoice, CheckoutOrder
        data/repositories/   #   SubscriptionRepository
        presentation/
          providers/         #   subscriptionProvider, plan/payment/invoice controllers
          screens/           #   Subscription, PlanSelection, PaymentCheckout, history
          gateway_checkout_launcher.dart  # the one gateway-specific integration point
    staff/          # Phase 9 — staff surface, deliberately smaller:
      data/          #   staff_working_status.dart — pure Today-tab derivation
      presentation/
        providers/   #   staffMeProvider, staff-scoped booking providers
        screens/     #   StaffShell + Today/Appointments/Schedule/Services/Profile
```

Each feature follows `data/{models,repositories}` + `presentation/{providers,screens}`, `owner/*` and `staff/*` included. There is no `features/customer/` folder — the suggested layout's "customer" concern *is* this app's whole raison d'être and lives in `profile/` (self-service profile) plus the customer-facing parts of `booking/`; `owner/customers/` is the distinct, owner-side customer-*management* concern from Phase 5 (CRUD, notes, summary), not to be confused with the customer app's own profile screens. `features/staff/` has no `data/models/` or `data/repositories/` of its own — see `STAFF_APP_ARCHITECTURE.md` for why every model and repository it needs already existed from Phase 7/8.

## State management: Riverpod

`flutter_riverpod` (classic `Provider`/`StateNotifierProvider`/`FutureProvider`, no code generation — `riverpod_generator` was deliberately skipped to avoid a `build_runner` dependency for this phase's scope). One approach only, used consistently:

- **`Provider`** for repositories and other stateless services (`authRepositoryProvider`, `bookingRepositoryProvider`, …, and Phase 8's `dashboardRepositoryProvider`, `staffRepositoryProvider`, `ownerCustomerRepositoryProvider`, `ownerServiceRepositoryProvider`, `ownerBranchRepositoryProvider`, `ownerSalonRepositoryProvider`, plus Phase 10's `subscriptionRepositoryProvider`).
- **`FutureProvider`** / **`FutureProvider.family`** for simple one-shot fetches (`mySalonsProvider`, `branchServicesProvider(branchId)`, `bookingDetailsProvider(id)`, `customerProfileProvider`, and Phase 8's `dashboardSummaryProvider`, `staffDetailsProvider(id)`, `ownerCustomerDetailsProvider(id)`/`ownerCustomerSummaryProvider(id)`, `serviceDetailsProvider(id)`, `ownerBranchDetailsProvider(id)`, `ownerSalonProvider`/`ownerSalonSettingsProvider`, and Phase 10's `subscriptionProvider`/`subscriptionPlansProvider`).
- **`StateNotifierProvider`** for anything with multi-step mutation logic: `authControllerProvider` (session), `bookingFlowControllerProvider` (the booking wizard), `myBookingsControllerProvider` (paginated list with load-more), and Phase 8's `ownerBookingsControllerProvider`, `staffListControllerProvider`, `ownerCustomerListControllerProvider`, `ownerServiceListControllerProvider` — each the same "paginated list + server-side filters + load-more" shape as `myBookingsControllerProvider`, not a new pattern. Phase 9's `staffAppointmentsControllerProvider` (`.family<String>`, keyed by staff id) is the **same** `OwnerBookingsController` class, given an `initialFilters` constructor parameter (new in this phase) rather than a duplicate controller. Phase 10's `PaymentHistoryController`/`InvoiceHistoryController` are two more instances of that same shape.
- **`StateProvider`** for one piece of simple shared UI state: `selectedBranchProvider`.

No other state management package is present in `pubspec.yaml`.

## Network layer: `ApiClient`

A single `Dio`-backed `ApiClient` (`core/network/api_client.dart`) is the only place that constructs HTTP requests:

- Base URL, timeouts, and headers come from `AppConfig` (see below) — never hard-coded per call site.
- An interceptor attaches `Authorization: Bearer <token>` from `SecureStorage` to every request automatically.
- A second interceptor calls `onUnauthorized` (wired once, in `AuthController`) whenever a response is `401`, so a single place handles "the session died — log the user out."
- `LogInterceptor` is attached only when `kDebugMode` is true (compiled out of release builds regardless of the `ENABLE_NETWORK_LOGGING` dart-define) and explicitly disables header logging, so the bearer token is never printed even in debug logs.
- Every method (`get`/`post`/`put`/`patch`/`delete`) unwraps the backend's `{success, message, data}` envelope and converts any failure into a typed `ApiException` (see `core/network/api_exception.dart`) — UI code never touches a raw `DioException` or the envelope shape. Phase 8 added `delete<T>()` (staff/service/category/branch/customer deletion) and `postMultipart<T>()` — a Laravel `_method`-override `POST` for the staff-photo/service-image/category-image upload screens, since PHP cannot parse a multipart body on `PUT`/`PATCH`. Phase 10 added an optional `headers` parameter to `post<T>()`, used for the `Idempotency-Key` header on checkout/renewal requests, and `ApiErrorType` gained a `paymentRequired` case mapped from HTTP `402` (a subscription-not-active response from `EnsureActiveSubscription`).

Repositories (`AuthRepository`, `SalonRepository`, `ServiceRepository`, `BookingRepository`, `ProfileRepository`, and Phase 8's `DashboardRepository`, `StaffRepository`, `OwnerCustomerRepository`, `OwnerServiceRepository`, `OwnerBranchRepository`, `OwnerSalonRepository`, plus Phase 10's `SubscriptionRepository`) are the only classes that call `ApiClient`; every screen goes through a repository (usually via a Riverpod provider), never `Dio`/`http` directly. The owner surface's booking operations were added as new methods on the **existing** `BookingRepository` (`ownerBookings`, `ownerBookingDetails`, `confirmBooking`, `updateBookingStatus`, `ownerCancelBooking`, `ownerRescheduleBooking`) rather than a parallel `OwnerBookingRepository` — same `Booking` model, same envelope, only the base path differs. Phase 9 added exactly one repository method anywhere, `StaffRepository.me()` (`GET /staff/me`) — every other staff-app screen calls `BookingRepository`/`StaffRepository` methods that already existed, now with a server-resolved id instead of an owner-chosen one. `SubscriptionRepository.checkout()`/`renew()` send only a `plan_id` — never an amount — matching the backend's own "never trust a client-supplied price" rule; see `SAAS_BILLING_ARCHITECTURE.md`.

## Models

Every API response is parsed into a typed Dart class (`AppUser`, `AuthResult`, `CustomerProfile`, `Salon`, `Branch`, `CustomerSalon`, `ServiceCategory`, `SalonService`, `BranchServices`, `AvailabilityResult`/`AvailabilitySlot`/`StaffOption`, `Booking`/`BookingItem`/`BookingStatusHistoryEntry`, `BookingStatus`, and Phase 8's `DashboardSummary`/`NextAppointment`, `StaffMember`/`StaffWorkingHourEntry`/`StaffBreakEntry`/`StaffLeaveEntry`, `CustomerSummary`/`UpcomingAppointmentSummary`/`CustomerNoteEntry`, `AppRole`, and Phase 10's `Plan`/`Subscription`/`Payment`/`Invoice`/`InvoiceItemEntry`/`CheckoutOrder`). Models are written by hand (`fromJson` factory constructors) rather than via `freezed`/`json_serializable`, again to avoid a `build_runner` step for this phase — each model is small and the shape is pinned exactly to the corresponding Laravel API Resource (see `MOBILE_API_INTEGRATION.md`), verified against the live backend during development.

Decimal-cast money fields (`price`, `total`, `subtotal`, …) arrive from Laravel as JSON strings (e.g. `"300.00"`) to avoid float precision loss server-side; models parse them with `num.parse(...)`.

## Booking flow state

`BookingFlowState` (`features/booking/presentation/providers/booking_flow_state.dart`) is the single source of truth for the entire multi-screen booking wizard (branch → services → staff preference → date → availability → slot → notes → submission), owned by one `BookingFlowController` (`StateNotifierProvider`) rather than threading a dozen constructor parameters through five screens. See `MOBILE_API_INTEGRATION.md` for exactly how each step maps to a backend call, and the "Booking flow" section there for the UX-ordering decision forced by the real availability contract (staff names are only known once a date's availability has been fetched, not before).

## Routing: go_router

`core/routing/app_router.dart` defines one `GoRouter` with a `redirect` callback driven by `authControllerProvider`'s status (`unknown` → splash, `unauthenticated` → login/register, `authenticated` → role-checked), bridged from Riverpod via a small `RouterNotifier extends ChangeNotifier` passed as `refreshListenable`. An authenticated-only screen is therefore never reachable without a valid session — the redirect runs on every navigation attempt, not just at app start.

Phase 8 adds a role check on top of that same redirect: an authenticated user's `AppRole` (derived from the real `UserResource.role`, see `OWNER_APP_ARCHITECTURE.md`) decides their home route and gates route families against each other. This is UI/navigation convenience only, not a security boundary: the Laravel backend independently authorizes every request via the same tenant-management policies from Phases 2–6 regardless of which screen the app happens to show.

Phase 9 completes the three-way split: `AppRole.staff` (renamed from Phase 8's placeholder `staffPending` now that there's a real destination) decides `homeFor` → `/staff`, and a new `_isStaffRoute` guard (mirroring `_isOwnerRoute`) redirects a non-staff session away from `/staff/*` and a staff session away from `/owner/*` or any customer-only route. Final mapping: `ownerAdmin` → `/owner`, `customer` → `/home`, `staff` → `/staff`, `unknown` → `/login`. `test/widgets/owner_router_authorization_test.dart` exercises the real redirect logic end-to-end for every backend role, all three authenticated destinations, and both directions of every cross-role redirect.

## Payment gateway integration (Phase 10)

`gateway_checkout_launcher.dart` is the single, deliberately isolated function that opens the payment gateway's checkout UI — currently a browser-based Razorpay hosted checkout via `url_launcher`, not the native `razorpay_flutter` SDK. That SDK was tried first and reverted after `flutter build apk --debug` failed in this sandboxed environment (its legacy Gradle buildscript needs Maven artifacts with no network access here) — this project's Android build has stayed green since Phase 7 and that bar wasn't relaxed for this phase. See `SAAS_BILLING_ARCHITECTURE.md`, "Flutter payment flow," for the full reasoning, and `core/utils/money_format.dart` (`formatMoney`) for the one small addition this phase made to money display — it strips Dart's `500.0` artifact for whole-number amounts, scoped to the new billing screens only so Phase 7–9 screens' existing display behavior is untouched.

## Coupons / membership / loyalty (Phase 12)

New top-level feature folders `features/membership/` and `features/loyalty/` hold the models/repositories/screens shared or customer-facing for those two domains; owner-only management (coupons, membership plans, customer memberships, loyalty search/adjustment) lives under `features/owner/pricing/`. `MembershipCheckoutScreen`/`membership_gateway_checkout_launcher.dart` are a deliberate near-duplicate of Phase 10's `PaymentCheckoutScreen`/`gateway_checkout_launcher.dart` — same browser-hosted-checkout reasoning, same "poll the server, never trust a client-side signal" rule, just against the membership domain's own endpoint. The booking flow (`BookingFlowController`/`BookingFlowState`) gained `couponCode`/`loyaltyPointsToRedeem`/`pricing` state and a `previewPricing()` action that calls the new read-only price-preview endpoint — purely additive; a flow that never touches these fields behaves exactly as it did before this phase. `formatMoney()` is used in the new Phase 12 models (`Coupon.discountLabel`/`MembershipPlan.discountLabel`) and screens only, following the same scoping precedent Phase 10 set.

## Reports & analytics (Phase 13)

`features/owner/reports/` follows the same `data/{models,repositories}` + `presentation/{providers,screens,widgets}` split as every other feature, with plain hand-written `fromJson` models (no codegen, matching every other model in the project). `fl_chart` is the one new `pubspec.yaml` dependency this phase adds — the first chart library in the project — used exclusively to render `{date, value}`/`{label, value}` series the backend already computed; no chart widget performs arithmetic on report data itself. See `OWNER_APP_ARCHITECTURE.md` and `REPORTING_ANALYTICS_ARCHITECTURE.md` for the feature and backend design respectively.

## Security + performance hardening (Phase 14)

No new feature surface — a code audit of the existing client found and fixed three small issues: `core/network/api_client.dart`'s debug-only request/response logging (`_RedactingLogInterceptor`, `kDebugMode`-gated like its predecessor) now redacts any body field whose key contains `password`, `signature`, `token`, or `secret` before printing, since the previous stock `LogInterceptor` could print a plaintext password on `/auth/login`/`/auth/register` in a debug build; `dashboard_tab.dart` narrowed a `ref.watch(authControllerProvider)` to `.select((state) => state.user)` so an unrelated auth-state change doesn't rebuild the whole dashboard; and `ios/Runner/Info.plist` gained `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription`, missing despite `image_picker` being a dependency (their absence would crash the picker at runtime on a real device, found during a static iOS config review — this project cannot build/run iOS to verify at runtime). Token storage (`flutter_secure_storage` only, confirmed zero `SharedPreferences` usage anywhere), the Android release network-security config (cleartext exception scoped to the `debug` Gradle source set only, structurally excluded from release builds), and notification deep-link handling (always re-fetches through the normal authorized endpoint, never trusts push-payload data directly) were all reviewed and confirmed already correct — see `SECURITY_HARDENING.md` for the full audit.

## Owner onboarding: self-service salon-owner registration

`features/auth/` gained a third screen, `RegisterOwnerScreen`, alongside the untouched `LoginScreen`/`RegisterScreen` — same `data/{models,repositories}` + `presentation/{providers,screens}` split, no new feature folder needed since this is still the auth domain. `RegisterChoiceScreen` is the one new decision point: `LoginScreen`'s "Register" link now goes there instead of straight to `RegisterScreen`, offering "Register as Customer" / "Register your Salon" explicitly rather than assuming one. `AuthRepository.registerOwner()` posts to `/auth/register-owner` and returns a new `OwnerRegistrationResult` model (`user`, `token`, `tenantSlug` — deliberately not reusing `AuthResult`, since no other auth flow returns a tenant slug). `AuthController.registerOwner()` stores the token via the existing `SecureStorage` and sets `ApiClient.tenantSlug` from the response, then updates `AuthState` like `login()`/`register()` do, plus one addition — see "Owner onboarding: salon setup" below. `app_router.dart`'s `isAuthScreen` check gained the two new routes (`/register-choice`, `/register-owner`) so an unauthenticated session can reach them without being bounced to `/login`.

## Owner onboarding: salon setup

Real-device testing surfaced a second gap right after the one above: a freshly self-registered owner has a `Tenant` but no `Salon` yet, and `BranchController::store()` (and, before this fix, `SalonProfileScreen` itself) had no safe way to handle that — see `OWNER_APP_ARCHITECTURE.md`, "Owner onboarding: salon setup", for the full three-layer design (router redirect, dashboard banner, backend `422`). The Flutter-side pieces, all additive:

- `AuthState` gained a `hasSalonProfile` field (`bool?`, default `null`). `AuthController.registerOwner()` sets it `false` deterministically; a new `markSalonProfileComplete()` method sets it `true`. Every other auth flow (`login()`, `register()`, session restore) leaves it `null`, so an existing owner's routing is byte-for-byte unchanged.
- `app_router.dart`'s `homeFor` for `AppRole.ownerAdmin` is `hasSalonProfile == false ? '/owner/salon' : '/owner'` — a one-line change, evaluated only where `homeFor` already was (auth-screen/splash landing, and cross-role redirect-away guards).
- `OwnerSalonRepository` gained a `create()` method (`POST /salon`, same field-building shape as the existing `update()`). `SalonProfileScreen` now branches on whether `ownerSalonProvider` resolved a `Salon` or failed with `ApiErrorType.notFound`: the former renders the pre-existing edit form, the latter renders the same form in create mode (no `status` field, a short "Let's set up your salon" banner, "Create salon profile" button) instead of the generic `ErrorView` it used to show for every error including this one — so the backend's raw 404 body is never rendered as text.
- `DashboardTab` additionally watches `ownerSalonProvider` purely to decide whether to show a dismissable-by-navigation "Set up your salon profile" card above the existing content; a `404` shows it, anything else (including still-loading) shows nothing.

No new route, no new feature folder, no new provider file beyond what's listed above.

## Theming

`AppTheme` derives a full Material 3 `ColorScheme` (light + dark) from one seed color (`AppColors.seed`) and centralizes button/input/card/navigation-bar styling. No widget declares a raw `Color(0x...)` outside `core/theme/`.
