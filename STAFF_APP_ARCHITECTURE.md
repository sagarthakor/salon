# Staff App Architecture

Phase 9 extends the same Flutter project (`mobile/`) a third time — never a second or third app. A `staff`-role session now sees a real, focused staff surface at `/staff` instead of Phase 8's placeholder screen; the customer app (Phase 7) and owner/admin app (Phase 8) are unchanged.

## Role-aware navigation

`AppRole.staff` (renamed in this phase from the Phase 8 placeholder name `staffPending`, since there is now a real destination behind it — the backend role string itself, `'staff'`, is unchanged) is the navigation target for a `UserResource.role` of `staff`. `core/routing/app_router.dart`'s redirect logic gained a `_isStaffRoute` guard mirroring `_isOwnerRoute`: a non-staff session pushed into `/staff/*` is redirected to its own home route, and a staff session pushed into `/owner/*` or a customer-only route (`/home`, `/booking/*`, `/bookings/*`, `/profile/edit`) is redirected back to `/staff`. As with every role check in this app, this is navigation-only — the Laravel backend independently authorizes every request regardless of which screen is showing (see OWNER_APP_ARCHITECTURE.md, which this phase's authorization model matches exactly).

## Staff identity: `GET /staff/me` (the one new backend endpoint)

The Flutter client has no way to know its own `staff_id` — `UserResource` never included one, and every existing Phase 4 staff endpoint (`/staff/{id}*`) expects an id in the URL. Inventing a "select your staff record" screen, or worse, trusting a client-supplied id, was rejected outright (see `StaffController::me` in `app/Http/Controllers/Api/V1/StaffController.php`): a staff member must never be able to view another staff member's data by changing an id in a request.

`GET /staff/me` (registered *before* the `staff/{staff}` apiResource route, so it isn't swallowed by the wildcard) resolves `Staff::where('user_id', $request->user()->id)->first()` **inside** the already tenant-scoped query (`Staff` uses `BelongsToTenant`, so this is automatically the current tenant's staff row and no other tenant's), and returns 404 with a clear message if the authenticated user has no linked staff profile — matching Phase 9's instruction to show a real configuration error rather than silently creating one client-side. This mirrors `CustomerProfileController::show`'s existing self-resolution-by-`user_id` pattern from Phase 5 exactly.

Every other staff-app screen resolves through this once (`staffMeProvider`, `lib/features/staff/presentation/providers/staff_self_providers.dart`) and then calls the **existing** owner-surface endpoints with that server-verified id — `StaffRepository.services/workingHours/breaks/leaves(myStaffId)`, `BookingRepository.ownerBookings(staffId: myStaffId, ...)`. No other new backend endpoint was needed.

## Why booking access needed no backend change

`BookingController`'s every action (`index`, `show`, `update`, `confirm`, `cancel`, `reschedule`) is gated by `viewableTenant()` — any tenant member, staff included, already has full tenant-wide booking read/write access; this was a deliberate Phase 6 design decision (see `BOOKING_ENGINE.md`, "staff's full operational access"), not something Phase 9 introduced or should narrow. The staff app therefore reuses `BookingRepository` **unchanged**: `OwnerBookingsController` (Phase 8) gained an optional `initialFilters` constructor parameter so the staff app's "My Appointments" list can permanently pin `staffId: <my id>` without duplicating the controller, and `/staff/appointments/:id` and `/staff/appointments/:id/reschedule` route directly to the **same** `OwnerBookingDetailsScreen`/`OwnerRescheduleScreen` widgets Phase 8 already built and tested — same fields, same `BookingStatus.nextActions`-driven transition buttons (confirm, check-in, in-service, complete, cancel with a reason prompt, no-show, reschedule), because the backend genuinely authorizes staff for all of them identically to an owner. A staff-only subset would have been an invented restriction with no backend basis.

## Why there is no staff dashboard endpoint

The "Today" tab needs today's appointment counts, the next appointment, and a real-time working status. All of it is derivable from data already being fetched for an already-authorized purpose:

- Today's appointments: `BookingRepository.ownerBookings(staffId: myId, date: today)` — the existing endpoint, exact-date filter.
- Completed / remaining counts, next appointment: computed client-side from that one response's `status`/`start_time` fields — the same kind of derivation Phase 7's `upcomingBookingProvider` already does (`for (final booking in bookings) if (booking.status.isActive) return booking;`), not a new pattern.
- Working status (`deriveStaffWorkingStatus`, `lib/features/staff/data/staff_working_status.dart`, unit-tested in isolation): a pure function over already-fetched working hours, breaks, and leave plus the device clock — `onLeave` (any non-rejected leave covering today) → `offToday` (no working-hours entry for today) → `onBreak` (device time falls inside a break window) → `workingNow`. Every input is real backend data; nothing is fabricated or estimated.

A dedicated `/staff/dashboard` endpoint was considered and rejected as unnecessary — everything it would return is already obtainable from endpoints the client calls anyway, and duplicating that logic server-side would be strictly more code for identical output.

## Why Schedule, Services, Leave, and Profile are view-only

Every write path a staff member might want on their own record already exists — and is already owner-only:

- `PATCH /staff/{id}` (profile edit) — requires `managedTenant()`.
- `PUT /staff/{id}/working-hours` — requires `managedTenant()`.
- `POST/PUT/DELETE /staff/{id}/breaks` and `/leaves` — require `managedTenant()`.
- `PUT /staff/{id}/services` — requires `managedTenant()`.

Only the `index`/`show`/`me` reads on these resources allow self-access (`Gate::authorize('view', $staff)`, `StaffPolicy::view`, which already permitted `$staff->user_id === $user->id` since Phase 4). Phase 9's instructions are explicit that a screen must never show a control that always fails with 403, so **My Schedule**, **My Services**, **My Leave** (folded into My Schedule as a read-only section), and **My Profile** are all read-only. No leave-request endpoint exists in the backend, and none was invented — requesting leave remains an owner-managed action outside this phase's scope, exactly as instructed.

## Directory layout

```
lib/features/staff/
  data/
    staff_working_status.dart        # pure, unit-tested derivation (see above)
  presentation/
    providers/
      staff_self_providers.dart      # staffMeProvider (GET /staff/me)
      staff_booking_providers.dart   # staffAppointmentsControllerProvider, staffTodayBookingsProvider
    screens/
      staff_shell.dart               # bottom-nav shell + "account not configured" error state
      staff_today_tab.dart           # dashboard-equivalent landing tab
      staff_appointments_screen.dart # Upcoming / Today / Past
      staff_schedule_screen.dart     # working hours + breaks + leave, view-only
      my_services_screen.dart        # assigned services, view-only
      staff_profile_screen.dart      # view-only profile + log out
```

Every model, the `BookingRepository`, and the `StaffRepository` (which gained one new method, `me()`, wrapping `GET /staff/me`) are reused unchanged from Phase 7/8 — nothing under `features/staff/` reimplements a model or a repository that already existed. `MyServicesScreen` is named to avoid colliding with the owner app's own (editable, assignment-management) `StaffServicesScreen` class — same underlying data, different screen for a different audience and purpose.

## Demo account

Seeded (idempotently, additively — `database/seeders/DatabaseSeeder.php`) alongside the existing owner/customer demo accounts: `staff@example.test` / `ChangeMe123!`, a real `staff`-role platform user with a `staff` tenant membership, linked to the existing "Amit" staff profile created live during Phase 7/8 verification (already has a branch and a service assigned). Logging in as this account now opens the staff app at `/staff` instead of Phase 8's placeholder.

## Testing

`tests/Feature/StaffManagementApiTest.php` gained three tests for `GET /staff/me`: resolving the caller's own profile and never another staff member's, a 404 when no profile is linked, and correct per-tenant scoping for a user with staff profiles in two different tenants (55 backend tests total after Phase 9). The Flutter suite gained unit tests for `deriveStaffWorkingStatus`, a repository-behavior test for `StaffRepository.me()`, widget tests for every new staff screen, an extension of the existing end-to-end router-authorization test (`test/widgets/owner_router_authorization_test.dart`) covering the staff role's real landing screen and both cross-role redirect directions, and a dedicated test proving the `/staff/appointments/:id` route reaches the reused `OwnerBookingDetailsScreen` and that a real transition (check-in) still works through it — the full transition matrix for that shared widget is already covered exhaustively by Phase 8's own test file, so it was not duplicated. See `TESTING.md`.

## Coupons / memberships / loyalty (Phase 12)

Staff gained no new screens or endpoints in this phase — they cannot manage coupons, membership plans, or loyalty (backend-enforced: every write is `managedTenant()`-gated, owner/super-admin only). Staff continue to see full booking detail via the reused `OwnerBookingDetailsScreen`, which now additionally shows a booking's coupon/membership/loyalty discount breakdown alongside the total — visible, never editable. See `LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md`.
