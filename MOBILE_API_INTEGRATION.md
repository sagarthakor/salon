# Mobile API Integration

Every endpoint the Flutter customer, owner/admin, and staff apps call, and — because most phases required small, deliberate backend additions to make the app functional at all — exactly what was added and why. All shapes below were verified against the live Laravel API (`php artisan serve`) during development, not assumed from reading code alone; see the request/response examples.

## Backend changes made in Phase 7

Phase 7's instructions are explicit: don't invent endpoints, and if a required API is genuinely missing, add the smallest compatible fix with tests rather than fake it client-side or silently work around it. Two gaps were genuinely blocking and were fixed this way; one non-gap (missing pagination metadata) was handled entirely client-side.

### 1. `GET /api/v1/customer/salons` (new)

**Problem**: `GET /auth/me` returns `tenant_user` memberships, but customers are *deliberately never* `tenant_user` members (a Phase 5 design decision — see `CUSTOMER_ARCHITECTURE.md`). There was therefore no way for an authenticated customer to discover which salon(s) they're a customer of at all — the home screen would have nothing to show.

**Fix**: `CustomerSalonController@index` lists the tenants where a `customer_profiles` row already links to the authenticated user (created by salon staff, per Phase 5), returning each tenant's salon profile and active branches. It was **not** a public salon directory/search at the time — a user with no existing customer relationship to any salon saw an empty list. A true public discovery feature (search all salons, browse without a relationship) was added later — see "Customer salon discovery and first-time booking" below.

```
GET /api/v1/customer/salons
Authorization: Bearer <token>

{
  "success": true,
  "data": [
    {
      "tenant_slug": "demo-salon",
      "salon": { "id": "...", "name": "Demo Salon", "slug": "demo-salon", ... },
      "branches": [ { "id": "...", "name": "Main Branch", "address": {...}, "status": "active", ... } ]
    }
  ]
}
```

### 2. `GET /api/v1/branches/{branch}/services` (new)

**Problem**: `GET /service-categories` and `GET /services` both require `tenant.context` (owner/staff only). Since `GET /branches/{branch}/availability` requires `service_ids[]` as *input*, a customer had no way to discover which services even exist to pass to it — the booking flow was unstartable.

**Fix**: `CustomerServiceController@index` returns the active categories and services for one branch, resolving the tenant from the branch id and bypassing its `BelongsToTenant` scope exactly the way `AvailabilityController` already does (`auth:sanctum` only, no `tenant.context`) — the same reviewed pattern, not a new one.

```
GET /api/v1/branches/{branch}/services
Authorization: Bearer <token>

{
  "success": true,
  "data": {
    "categories": [ { "id": "...", "name": "Hair", ... } ],
    "services": [ { "id": "...", "name": "Haircut", "category": {...}, "price": "300.00", "duration_minutes": 30, ... } ]
  }
}
```

### 3. `staff` field added to the availability response (additive)

**Problem**: `GET /branches/{branch}/availability` returned `slots[].staff_ids` (raw ULIDs) with no names anywhere reachable by a customer — "Display eligible staff using backend data" (Phase 7 §17) had no data to display.

**Fix**: `AvailabilityController` now also returns a top-level `staff: [{id, name}]` array — every staff member's name that appears in any returned slot, resolved once per response rather than duplicated per slot. Purely additive: `slots` is unchanged, so every Phase 6 test and any existing owner/staff client keeps working untouched.

```json
{
  "date": "2026-09-01",
  "duration_minutes": 30,
  "buffer_minutes": 0,
  "slots": [{ "start_time": "09:00", "end_time": "09:30", "staff_ids": ["st_1"] }],
  "staff": [{ "id": "st_1", "name": "Amit" }]
}
```

All three changes have backend tests (`tests/Feature/CustomerManagementApiTest.php`, `tests/Feature/BookingEngineApiTest.php`) and the full backend suite (50 tests) passes after them — see `TESTING.md`.

## Backend changes made in Phase 8

The owner/admin app is built almost entirely on the existing Phase 2–6 tenant-management APIs — `/staff*`, `/customers*`, `/services*`, `/service-categories*`, `/branches*`, `/salon*`, `/bookings*` — with only two changes, both required by the same "don't fabricate, add the smallest real fix" rule as Phase 7.

### 1. `GET /api/v1/dashboard/summary` (new)

**Problem**: the owner dashboard needs today's booking counts by status, today's revenue, the next upcoming appointment, how many staff are active/on leave today, and total/new-this-month customer counts. No existing list endpoint exposes "revenue" or "on leave today" at all, and assembling the rest client-side would mean several paginated requests per dashboard load (N+1-ish) plus real risk of the client quietly inventing a number the backend never validated.

**Fix**: `DashboardController@summary` (`app/Http/Controllers/Api/V1/DashboardController.php`) computes every field with a real Eloquent query — see the class-level docblock there for exactly which query backs which field. Every value is genuine and server-computed; there is no cached/estimated/placeholder field in the response.

```
GET /api/v1/dashboard/summary
Authorization: Bearer <token>
X-Tenant-Slug: demo-salon

{
  "success": true,
  "data": {
    "date": "2026-08-23",
    "bookings": { "total": 5, "pending": 1, "confirmed": 2, "checked_in": 0, "in_service": 1, "completed": 1, "cancelled": 0, "no_show": 0 },
    "revenue_today": "1250.50",
    "next_appointment": { "id": "...", "booking_date": "2026-08-23", "start_time": "15:00", "status": "confirmed", "customer_name": "Anita Rao" },
    "staff": { "active": 4, "on_leave_today": 1 },
    "customers": { "total": 120, "new_this_month": 8 }
  }
}
```

### 2. `GET /api/v1/customers/{customer}/summary` (fixed, not new)

**Problem**: this endpoint already existed from Phase 5, but `CustomerController::summary` returned a hard-coded placeholder — every counter was a literal zero regardless of the customer's actual booking history, flagged at the time as "not yet wired to `bookings`" because the booking engine didn't exist yet.

**Fix**: now that Phase 6 provides `Booking`/`BookingItem`, `CustomerController::summary` derives every field from the customer's real bookings — `total_visits`, `completed_appointments`, `cancelled_appointments`, `no_show_count`, `total_spent` (sum of `total` for completed bookings), `last_visit_at`, and `upcoming_appointment`. The response shape is unchanged, only the values are now real; no client code needed to change to pick this up.

Both changes have backend tests (`tests/Feature/BookingEngineApiTest.php`, `tests/Feature/CustomerManagementApiTest.php`) and the full backend suite (52 tests) passes after them — see `TESTING.md`.

## Backend change made in Phase 9

### `GET /api/v1/staff/me` (new)

**Problem**: the staff app needs to know the authenticated user's own `staff_id` to call any of the existing Phase 4 staff sub-resource endpoints (`/staff/{id}/services`, `/working-hours`, `/breaks`, `/leaves`) or filter bookings to `staff_id=<mine>`. `UserResource` never exposed one, and there was no way for the client to discover it that didn't involve either inventing a new field on the login/me response or — worse — trusting a client-supplied id, which `StaffPolicy::view` already guards against for every other staff endpoint.

**Fix**: `StaffController::me` resolves `Staff::where('user_id', $request->user()->id)->first()` inside the already tenant-scoped query (`Staff` uses `BelongsToTenant`), returning a `404` with a clear message if the authenticated user has no linked staff profile in the current tenant. Registered as `Route::get('staff/me', ...)` **ahead of** `Route::apiResource('staff', ...)` so it is never captured by the `staff/{staff}` wildcard. Mirrors the Phase 5 `GET /customer/profile` self-resolution-by-`user_id` pattern exactly — not a new authorization idea, the same one applied to a different resource.

```
GET /api/v1/staff/me
Authorization: Bearer <token>
X-Tenant-Slug: demo-salon

{
  "success": true,
  "data": {
    "id": "01m0s12xfbwv051hhy15n25h3h",
    "user_id": 4,
    "name": "Amit",
    "photo": null, "phone": null, "email": null,
    "gender": "male", "bio": null, "joining_date": null,
    "status": "active", "commission_type": null, "commission_value": null,
    "branches": [{ "id": "...", "name": "Main Branch", ... }]
  }
}
```

Has a backend test (`tests/Feature/StaffManagementApiTest.php`) covering self-resolution, the `404` no-profile case, and per-tenant scoping for a user with staff profiles in two tenants; full backend suite (55 tests) passes after it — see `TESTING.md`.

### Non-changes: booking access and a staff dashboard

Two things a naive implementation might have added as new backend surface turned out to need nothing: `BookingController`'s every action already authorizes any tenant member (`viewableTenant()`) with no staff-vs-owner distinction (a Phase 6 decision — staff already had full tenant-wide booking access), so the staff app's booking screens call the exact same endpoints the owner app calls, just with a `staff_id` filter the client chooses to always set. And no `/staff/dashboard`-style aggregate endpoint was added — see `STAFF_APP_ARCHITECTURE.md` for why everything the Today tab shows is derivable from data the client is fetching anyway.

### Non-change: list pagination metadata

Every paginated Laravel endpoint in this project (`services`, `staff`, `customers`, `bookings`, `customer/bookings`, …) returns just the page's array under `data`, with no `meta`/`links` — because `ApiResponse::success()` wraps values in a plain `response()->json([...])` rather than letting Laravel's resource-collection `toResponse()` add pagination metadata. This predates Phase 7 and affects every list endpoint identically, not something specific to the mobile app. Rather than changing that shared, cross-cutting response contract for one screen, `MyBookingsController` (`features/booking/presentation/providers/my_bookings_controller.dart`) infers "has more pages" from whether the last page came back full (`length == perPage`) — a standard, well-understood client heuristic that needs no backend change and works correctly against the actual pagination behavior (which does work; only the metadata is absent).

## Backend changes made in Phase 10

Full detail lives in `SAAS_BILLING_ARCHITECTURE.md`; summarized here for the mobile-integration record. One genuinely new endpoint family (`/subscription*`, `/platform/plans*`, `/webhooks/razorpay`) plus one new gate on every existing business endpoint:

### `GET|POST /api/v1/subscription*` (new)

The full billing surface — see `API_DOCUMENTATION.md` for every route. The Flutter owner app calls `GET /subscription` (status/plan/dates), `GET /subscription/plans` (active plans, real prices), `POST /subscription/checkout` and `POST /subscription/checkout/verify` (order creation + server-side signature verification), `POST /subscription/renew`, `POST /subscription/cancel`, and `GET /subscription/payments`/`GET /subscription/invoices` (paginated history).

### `EnsureActiveSubscription` middleware (new — a gate, not an endpoint)

Every existing Phase 2–6 business route (`/salon*`, `/branches*`, `/service-categories*`, `/services*`, `/staff*`, `/customers*`, `/bookings*`, `/dashboard/summary`) now returns `402 Payment Required` if the tenant's subscription isn't `trialing`/`active`/`past_due`/`grace_period`. `ApiExceptionMapper` gained `ApiErrorType.paymentRequired` for status `402` so the Flutter app can recognize this distinctly from a generic error, though no screen currently does anything more than surface the backend's message — the owner reaches the Subscription screen (reachable regardless of status) via the "More" menu to resolve it.

```
GET /api/v1/branches
Authorization: Bearer <token>
X-Tenant-Slug: demo-salon
(tenant's subscription is EXPIRED)

{
  "success": false,
  "message": "Your salon's subscription is not active. Please renew to continue.",
  "errors": {}
}
```

## Self-service salon-owner registration (owner onboarding)

Not part of the original numbered phase sequence — a targeted addition closing a gap Phases 1–15 had left open: there was no way for a new person to become a salon owner at all (see "Tenant onboarding" in `PROJECT_ARCHITECTURE.md` for the investigation that found this). One new endpoint:

### `POST /api/v1/auth/register-owner` (new)

Full request/response documented in `API_DOCUMENTATION.md`, "Owner onboarding". The Flutter app's registration flow now branches in two: the existing customer `RegisterScreen` is completely unchanged, and a new `RegisterOwnerScreen` (owner name/email/password + salon name, with `slug` behind an optional "Advanced" toggle) calls this endpoint instead. A new `RegisterChoiceScreen` sits between `LoginScreen`'s "Register" link and the two destination screens so the distinction is explicit, never inferred. On success, `AuthController.registerOwner()` stores the token (same `SecureStorage` as every other auth flow) and sets `ApiClient.tenantSlug` from the response's `tenant_slug`.

### Owner onboarding: salon setup (fixed, not new)

Real-device testing against the above flow found the next step was unsafe: a freshly-registered owner has no `Salon` yet, and `POST /branches` (deriving `salon_id` via `Salon::query()->firstOrFail()`) threw a raw, off-brand `ModelNotFoundException` response the moment they tried to add their first branch — not a `500` in the HTTP-status sense (Laravel maps it to `404`), but an unhandled-exception shape (`{"message": "No query results for model [App\\Models\\Salon]."}`) instead of the app's normal `{success, message, errors}` envelope. Fixed with no new endpoints, matching the existing "additive only" pattern this document tracks:

- `TenantManagementController::requireSalon()` (new protected helper) replaces that direct call in `BranchController::store()`, returning a normal `422` (`"Please set up your salon profile before adding a branch."`) when no Salon exists for the tenant — still `Salon::query()->first()`, so tenant-scoping (`BelongsToTenant`) is unaffected. `/services` and `/service-categories` already failed safely (tenant-scoped `branch_id` validation), so neither needed a backend change.
- `AuthController.registerOwner()` additionally sets a new `AuthState.hasSalonProfile = false`; the router resolves a `salon_owner`'s post-registration destination to `/owner/salon` instead of `/owner` when that flag is `false` (existing owners, whose flag is `null`, are unaffected). `OwnerSalonRepository` gained `create()` (`POST /salon` — the endpoint already existed; only the Flutter method was missing), and `SalonProfileScreen` now offers a create form when `GET /salon` 404s instead of showing a generic error. `DashboardTab` shows an independent "Set up your salon profile" prompt as a safety net for a session that navigates away before finishing setup. Full design in `OWNER_APP_ARCHITECTURE.md`, "Owner onboarding: salon setup".

## Service media: image, description, Instagram reference

A targeted feature addition, not a new phase: `POST`/`PUT` `/services` already accepted `description`; this adds `instagram_url` (new column) and fixes `image` to actually be usable by a client — the resource previously returned the raw internal storage path (e.g. `services/xyz.jpg`) under the key `image`, which no client could turn into a loadable URL. Every service response now returns `image_url` (a full `Storage::disk('public')->url(...)` URL, or `null`) and `instagram_url` (or `null`) instead. This is a rename, not an additive field, but the only consumer of the old `image` key was this same Flutter app's `SalonProfileScreen`/booking flow, which never actually rendered it correctly (it fed the raw path straight into `NetworkImage`) — so nothing that worked before stops working. See `API_DOCUMENTATION.md`, "Service media", for the full request/response shape, and `OWNER_APP_ARCHITECTURE.md` / `FLUTTER_ARCHITECTURE.md`, both "Service media", for the Flutter-side detail.

## Salon Instagram profile link (distinct from Service media above)

A second, smaller targeted addition: `salons.instagram_url` — new column, exposed as `instagram_url` on every `SalonResource` response, including `GET /customer/salons` (the customer's own salon-listing endpoint, `CustomerSalonController`, which already reused `SalonResource` — no controller change needed there). This is the salon's one official profile link (e.g. `https://www.instagram.com/primehairstudio/`), never a specific post — that's what `services.instagram_url` (above) is for. Both fields exist simultaneously and independently; neither replaces the other. Validation reuses `App\Support\InstagramUrl` (the same class Service media added) via a second method, `isValidProfile()`, which accepts a bare username path and rejects the `/p/`, `/reel/`, `/tv/` shapes the service field requires — so the two fields' valid inputs don't overlap. See `API_DOCUMENTATION.md`, "Salon Instagram profile", and `OWNER_APP_ARCHITECTURE.md` / `FLUTTER_ARCHITECTURE.md`, both "Salon Instagram profile", for the Flutter-side detail.

## Master catalog & service audience segmentation

A new tenant no longer starts with zero services — `POST /branches` now also provisions a starting catalog server-side the first time a tenant creates a branch (no new endpoint; existing clients calling this endpoint see no contract change beyond more services existing afterward). `GET /branches/{branch}/services` (the customer app's existing service-discovery call — see "Backend changes made in Phase 7" above) gained an optional `audience` query parameter (`male`/`female`/`unisex`/`kids`); omitted, it behaves exactly as before. The Flutter app's `ServiceRepository.forBranch()` gained a matching optional `audience` parameter, and a new screen (`AudienceSelectionScreen`) sits between the existing branch-selection and service-catalog screens, asking "What service are you looking for?" — Men/Women/Unisex/Kids. `SalonService`/`ServiceCategory` both gained an `audience` field (nullable, mirrors the backend). Full design in `MASTER_CATALOG_ARCHITECTURE.md`.

## Every endpoint the customer app calls

| Screen / flow step | Method & path | Notes |
|---|---|---|
| Splash → session restore | `GET /auth/me` | Validates a stored token; 401 clears it. |
| Login | `POST /auth/login` | `{email, password}` → `{user, token}`. |
| Register | `POST /auth/register` | `{name, email, password, password_confirmation}`; role/tenant ignored by the backend (Phase 1). |
| Logout | `POST /auth/logout` | Revokes the current Sanctum token; local session is cleared regardless of the response. |
| Home: find a salon (discovery) | `GET /customer/discover-salons` | New — see "Customer salon discovery and first-time booking" below. Replaces `mySalonsProvider`/`GET /customer/salons` as the Home tab's data source; membership is no longer required to see a salon. |
| Salon → branch selection | `GET /customer/salons/{salon}/branches` | New — same section. Single-branch salons auto-advance past this screen client-side. |
| Select branch → services | `GET /branches/{branch}/services` | New in Phase 7 — see above. |
| Select date/staff → availability | `GET /branches/{branch}/availability?date=&service_ids[]=&staff_id=` | `staff_id` omitted = "any available staff." Never computed client-side. |
| Confirm booking | `POST /customer/bookings` | `{branch_id, date, start_time, items:[{service_id, staff_id}], notes}`. `customer_id` is never sent — the backend resolves it from the caller's own `customer_profiles` row. A `409` means the slot was taken; the client shows "no longer available" and refetches availability. |
| My bookings | `GET /customer/bookings?page=&per_page=` | Own bookings only, across every salon the user is a customer of. |
| Booking details | `GET /customer/bookings/{id}` | Includes `items` and `status_history` (list endpoints omit them for payload size — see `Booking.fromJson`). |
| Cancel | `POST /customer/bookings/{id}/cancel` | `{reason}` optional. `409` if within the salon's cancellation window — shown verbatim from the backend message. |
| Reschedule | `POST /customer/bookings/{id}/reschedule` | `{date, start_time}` — keeps the booking's existing service/staff composition; the backend fully revalidates. |
| Profile | `GET /customer/profile` | |
| Edit profile | `PUT /customer/profile` | Only self-editable fields are ever sent — `status`, `tenant_id`, `user_id` are never client-controlled inputs anywhere in the app. |

## Every endpoint the owner/admin app calls (Phase 8)

| Screen / flow step | Method & path | Notes |
|---|---|---|
| Dashboard | `GET /dashboard/summary` | New in Phase 8 — see above. |
| Bookings list/filter | `GET /bookings?date=&status=&branch_id=&staff_id=&customer_id=&page=&per_page=` | Same `Booking` model/repository as the customer app, different base path. |
| Booking details | `GET /bookings/{id}` | |
| Confirm / status update / cancel / reschedule | `POST /bookings/{id}/confirm`, `PATCH /bookings/{id}` (`status`, `notes`), `POST /bookings/{id}/cancel`, `POST /bookings/{id}/reschedule` | Owner/staff cancel and reschedule always bypass the customer cancellation-window setting — never a client-supplied bypass flag, it's simply a different, broader-access endpoint (see `BOOKING_ENGINE.md`). |
| Staff list/details/CRUD | `GET|POST /staff`, `GET|PUT|PATCH|DELETE /staff/{id}` | Create/update use `postMultipart` for the optional photo. |
| Staff services/working hours/breaks/leave | `GET|PUT /staff/{id}/services`, `GET|PUT /staff/{id}/working-hours`, `GET|POST /staff/{id}/breaks` (+ `PUT|PATCH|DELETE .../{break}`), `GET|POST /staff/{id}/leaves` (+ `PUT|PATCH|DELETE .../{leave}`) | |
| Service/category list/CRUD | `GET|POST /services`, `GET|PUT|PATCH|DELETE /services/{id}`, `GET|POST /service-categories`, `GET|PUT|PATCH|DELETE /service-categories/{id}` | Create/update use `postMultipart` for the optional image. |
| Customer list/details/CRUD | `GET|POST /customers`, `GET|PUT|PATCH|DELETE /customers/{id}` | |
| Customer summary | `GET /customers/{id}/summary` | Fixed in Phase 8 — see above. |
| Customer notes | `GET|POST /customers/{id}/notes`, `PUT|PATCH|DELETE /customers/{id}/notes/{note}` | Owner/super-admin only; never reachable from the customer-facing side of the app. |
| Branch list/details/CRUD | `GET|POST /branches`, `GET|PUT|PATCH|DELETE /branches/{id}` | The Phase 2 owner-facing branch endpoints — distinct from the customer app's `GET /customer/salons` (Phase 7), which only ever returns *active* branches for salons the customer already has a relationship with. |
| Branch working hours/holidays | `GET|PUT /branches/{id}/working-hours`, `GET|POST /branches/{id}/holidays` (+ `PUT|PATCH|DELETE .../{holiday}`) | |
| Salon profile / booking settings | `GET|POST|PUT|PATCH /salon`, `GET|PUT|PATCH /salon/settings` | Settings screen edits the Phase 6 booking-engine keys (`slot_interval_minutes`, `min_advance_booking_minutes`, `max_advance_booking_days`, `booking_buffer_minutes`, `cancellation_window_minutes`) alongside the Phase 2 profile fields. |
| Subscription status | `GET /subscription` | New in Phase 10 — see above. Always reachable regardless of subscription status. |
| Plan selection | `GET /subscription/plans` | Active plans only, real prices. |
| Checkout / renew | `POST /subscription/checkout` or `/renew` `{plan_id}`, then `POST /subscription/checkout/verify` | `plan_id` only — never an amount. `verify` is only called if a gateway SDK returns a signature directly; this app's own checkout screen instead re-fetches `GET /subscription` after the browser-based checkout, trusting the server-verified webhook — see `SAAS_BILLING_ARCHITECTURE.md`. |
| Cancel subscription | `POST /subscription/cancel` | Sets `cancel_at_period_end`; no body. |
| Payment / invoice history | `GET /subscription/payments`, `GET /subscription/invoices` | Paginated, newest first. |

## Every endpoint the staff app calls (Phase 9)

| Screen / flow step | Method & path | Notes |
|---|---|---|
| Staff identity resolution | `GET /staff/me` | New in Phase 9 — see above. Resolved once at the shell level; every screen below uses the `id` it returns. |
| Today tab | `GET /bookings?staff_id=<mine>&date=<today>` | Same owner endpoint, exact-date filter; counts/next-appointment/working-status are all derived client-side from this one response plus working-hours/breaks/leave (already being fetched for the Schedule tab). |
| My Appointments (Upcoming/Today/Past) | `GET /bookings?staff_id=<mine>&page=&per_page=` | Same owner endpoint and pagination heuristic as every other list in this app; date-range grouping is done client-side (no server-side date-range filter exists — see STAFF_APP_ARCHITECTURE.md). |
| Appointment details / status actions | `GET /bookings/{id}`, `POST /bookings/{id}/confirm`, `PATCH /bookings/{id}`, `POST /bookings/{id}/cancel`, `POST /bookings/{id}/reschedule` | Identical to the owner surface — same `viewableTenant()` authorization, so the `/staff/appointments/:id` route reuses `OwnerBookingDetailsScreen`/`OwnerRescheduleScreen` outright. |
| My Schedule | `GET /staff/{id}/working-hours`, `GET /staff/{id}/breaks`, `GET /staff/{id}/leaves` | View-only — the `PUT`/`POST`/`PATCH`/`DELETE` variants of these all require `managedTenant()` (owner/super-admin only), so there is no write UI. |
| My Services | `GET /staff/{id}/services` | View-only — `PUT` requires `managedTenant()`. |
| My Profile | (no request — reuses the `GET /staff/me` result already held by the shell) | View-only — `PATCH /staff/{id}` requires `managedTenant()`. |

## Response envelope and error mapping

Every response is `{success, message, data}` (success) or `{success, message, errors}` (failure). `ApiClient` unwraps `data` for every successful call; `ApiExceptionMapper` (`core/network/api_exception.dart`) converts every failure — HTTP status, Dio-level network/timeout errors, and Laravel's `errors: {field: [messages]}` validation shape — into one `ApiException` with a typed `ApiErrorType` (`network`, `timeout`, `unauthorized`, `forbidden`, `notFound`, `validation`, `conflict`, `rateLimited`, `server`, `unknown`) and, where present, per-field messages. Screens react to the *type*, not the raw status code (e.g. `ApiErrorType.conflict` during booking confirmation specifically triggers the "slot no longer available, refresh" flow described in Phase 6/7's booking spec).

## Coupons / membership / loyalty (Phase 12)

`POST /customer/bookings` gained two optional fields (`coupon_code`, `loyalty_points_to_redeem`) — an existing request with neither still creates a booking exactly as before. A new `POST /customer/bookings/price-preview` lets the booking summary screen show the effect of a coupon/loyalty redemption before confirming, without creating anything; the real booking creation call recalculates independently, so the preview response is never sent back to the server as if it were authoritative. See `LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md`.

## Customer salon discovery and first-time booking

Real-device QA found the Phase 7 `GET /customer/salons` endpoint above is membership-only by design, so a brand-new customer — or even one a salon owner manually registered, since staff-side "add a customer" never links `user_id` — saw an empty Home tab. See `CUSTOMER_ARCHITECTURE.md`, "Customer salon discovery and first-time booking", for the full backend design. Mobile-side:

- `HomeTab` now calls `discoverSalonsProvider` (`GET /customer/discover-salons`) instead of `mySalonsProvider`, with a client-side name filter over the results ("Search salons") and the empty state changed from "You're not registered as a customer at any salon yet" to "No salons available near you yet."
- Tapping a salon card pushes a new route, `/salons/:salonId/branches` (`SalonBranchSelectionScreen`), which calls `salonBranchesProvider(salonId)` (`GET /customer/salons/{salon}/branches`). A single active branch auto-selects and advances straight to `/booking/audience`, matching the existing `selectedBranchProvider` contract those downstream screens already expect — nothing about `AudienceSelectionScreen`, `BookingServiceSelectionScreen`, or the audience/service catalog changed.
- `POST /customer/bookings` and `POST /customer/bookings/price-preview` both gained optional `phone`/`country_code` fields, only actually required (enforced server-side, reported as a normal `phone` field validation error) the first time a customer books with a given salon. `BookingFlowState` gained `phone`/`requiresPhone`; `BookingSummaryScreen` shows a phone `TextField` only once `requiresPhone` is set by a failed `confirmBooking()`/`previewPricing()` call, and retrying with a phone entered completes the same booking attempt — no second/parallel booking flow, no new screen in the booking funnel itself.

## Booking flow ordering vs. the spec diagram

Phase 7's flow diagram lists `Select Staff → Select Date → Fetch Availability`. In the real backend contract, staff *names* are only ever returned as part of an availability response (the `staff` field above) — there is no "list staff capable of these services" endpoint independent of a date, because staff eligibility inherently depends on that day's working hours/breaks/leave. The app therefore fetches availability first (staff mode defaulting to "any available"), then lets the customer optionally narrow to a specific staff member from the names that came back, which re-fetches availability filtered to that person. This is functionally equivalent — every requirement (staff preference, date selection, real availability, slot selection) is met — just reordered to match what the backend can actually answer, rather than inventing a staff-roster endpoint that doesn't exist.
