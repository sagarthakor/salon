# Booking Engine

Phase 6 implements the appointment booking engine described in Phases 4–5's forward-looking notes. This document is the source of truth for how it works; `PROJECT_ARCHITECTURE.md`/`DATABASE_ARCHITECTURE.md`/`MULTI_TENANCY.md`/`API_DOCUMENTATION.md` cross-reference it rather than repeating it.

## Booking architecture

```
Tenant → Branch → Booking → Booking Item → Service
                          ↘ Staff (per item)
Tenant → Customer → Booking
```

A `Booking` (table `bookings`) belongs to a tenant, a branch, and a customer, and holds the overall envelope (`booking_date`, `start_time`, `end_time`, `status`, pricing totals). A booking has one or more `BookingItem` rows (table `booking_items`), each representing one service performed by one specific staff member with its own `start_time`/`end_time`. This item-level staff assignment (not a single staff per booking) is what lets one booking mix multiple services performed by different people, per Phase 6's requirement.

`BookingStatusHistory` (table `booking_status_histories`) records every status change (`from_status` → `to_status`, who changed it, an optional reason) for audit/reporting. A reschedule (which does not change status) still writes a history row with `from_status === to_status` and a reason describing the old/new date-time, since it's the same append-only audit log and a dedicated table for that alone isn't justified.

## Booking item snapshots (historical pricing)

Every `booking_items` row stores `service_name`, `service_price`, and `service_duration_minutes` captured from the `Service` record at creation time, plus `service_id`/`staff_id` as nullable/soft-delete-tolerant foreign keys for reporting. Nothing about pricing or duration is ever recomputed from the current `Service` row after creation — confirmed by test (`test_historical_snapshot_is_unaffected_by_later_service_price_change`): changing a service's price after a booking exists leaves that booking's stored price untouched.

## Staff selection

A client can either name a specific `staff_id` per item, or leave every item's `staff_id` null for automatic assignment. Mixing null and non-null across items in one request is rejected (ambiguous). `BookingService::resolveStaffMode()` classifies the request into one of three modes:

- **auto** — every item's `staff_id` is null. One eligible staff member (capable of *every* requested service, assigned to the branch, active) is picked automatically, in ascending ID order among those who are actually free for the full sequential span. This is a deliberately simple, deterministic policy (documented here as a known place to add load-balancing or a "fewest bookings today" heuristic later).
- **sequential** — every item names the *same* staff_id. That one staff member performs every service back-to-back (see below).
- **parallel** — items name *different* staff_ids. Each staff member performs their item independently, all starting at the same requested `start_time`.

`StaffEligibilityChecker` (a pure, DB-free class operating on pre-loaded collections) is the single source of truth for "is this staff member free for this time span," reused by both slot generation (`AvailabilityService`, which bulk-preloads data for many candidates/slots to stay N+1-free) and booking creation/reschedule (`BookingService`, which queries a small, already-identified set of staff directly since it only ever checks one to a few candidates).

## Sequential vs. parallel multi-service scheduling

Per the Phase 6 brief, sequential-same-staff is the default/primary model: `BookingService::computeItemTimes()` lays items back-to-back (`item[0]` from the requested start, `item[1]` starting where `item[0]` ends, and so on) when the same staff performs everything. Parallel scheduling — different staff, same overall start time — is supported when the client explicitly assigns distinct staff per item; each item is validated independently against its own staff's schedule. The booking's overall `end_time` is the latest of its items' end times in both modes.

## Availability algorithm

`AvailabilityService::forBranch()` (used by both the availability endpoint and, conceptually, by booking creation's revalidation) computes candidate start times across the branch's open hours for the requested services, filtering out anything that fails:

1. Branch active, not holiday, open that day of week (`branch_working_hours`).
2. Not in the past, not beyond `max_advance_booking_days`, and — for today only — not before `min_advance_booking_minutes` from now (see Timezone below for how "now" is computed).
3. For each staff candidate (capable of every requested service, assigned to the branch, active): working that day (`staff_working_hours`), no break overlap (`staff_breaks`), not on leave (`staff_leaves`), and no conflicting existing booking item.

All of a branch's candidate staff's working hours/breaks/leave/existing items for the target date are loaded in a handful of bulk queries up front and then scanned in memory per candidate slot — no query runs inside the slot/staff loop.

## Slot interval, min/max advance booking, and buffer (configuration)

These reuse Phase 2's `salon_settings` key/value extension point (`App\Enums\SalonSettingKey`) rather than new columns — five new keys were added: `slot_interval_minutes`, `min_advance_booking_minutes`, `max_advance_booking_days`, `booking_buffer_minutes`, `cancellation_window_minutes`. They're managed through the existing `PUT /api/v1/salon/settings` endpoint with no controller changes required. `App\Support\BookingSettings` wraps a `Salon` and resolves each with a sane default when unset:

| Setting | Default | Notes |
|---|---|---|
| `slot_interval_minutes` | 15 | candidate-slot step size |
| `min_advance_booking_minutes` | 0 | no minimum unless configured |
| `max_advance_booking_days` | 30 | |
| `booking_buffer_minutes` | 0 | no cleanup gap unless configured |
| `cancellation_window_minutes` | 0 | unrestricted self-cancellation unless configured |

**Buffer time**: buffer is cleanup time *between different bookings* for the same staff member, not between items of the *same* booking (a staff member moving from one service to the next for the same customer needs no gap). `StaffEligibilityChecker` applies the buffer symmetrically around every *existing* booking item when checking a new candidate for conflicts — both sides of the comparison are extended by the buffer — so a new booking can neither start inside another booking's trailing cleanup window nor leave too little cleanup room before the next one. Working-hours and break checks are exact boundaries and are not buffer-adjusted (buffer only governs booking-to-booking spacing). Verified by test: a 15-minute buffer blocks a booking starting immediately when an existing one ends, but allows one starting exactly `buffer` minutes later.

## Cancellation

`POST /bookings/{booking}/cancel` (owner/staff) always passes `override = true`, bypassing the cancellation window — this is never client-controlled; it's implied entirely by which endpoint handled the request. `POST /customer/bookings/{booking}/cancel` (customer self-service) always passes `override = false`: if `cancellation_window_minutes` is set and the booking starts within that window, the cancellation is rejected with a 409. Every cancellation records `cancellation_reason`, `cancelled_by`, and `cancelled_at`, plus a `BookingStatusHistory` row.

## Rescheduling

`BookingService::reschedule()` only allows `pending`/`confirmed` bookings (not checked-in/completed/cancelled/no-show), and re-runs the *entire* validation pipeline against the new date/time from scratch inside a locking transaction — branch hours, holiday, staff working hours/breaks/leave, and existing-booking conflicts (excluding the booking being rescheduled itself). It never trusts a previously-fetched availability response. Verified by test: rescheduling into a slot that has since been booked by someone else is rejected with a 409.

## Double-booking prevention (concurrency strategy)

Every mutating operation (`create`, `cancel`, `reschedule`, `transition`) runs inside `DB::transaction()` with a retry count for MySQL deadlocks. Availability is never trusted from a prior read — it is always **re-checked inside the transaction, under a row lock**:

- `create()` locks the specific staff row(s) being assigned (`Staff::...->lockForUpdate()`) — the *candidate pool* for "auto" mode, or the exact named staff for "sequential"/"parallel" mode, always in ascending ID order to avoid lock-ordering deadlocks between concurrent requests that touch overlapping staff sets.
- `reschedule()`/`cancel()` additionally lock the `Booking` row itself, since two concurrent operations on the *same* booking (e.g. a customer cancelling while an owner reschedules) must also serialize.
- Only *after* acquiring the lock does the code re-run the exact same overlap query used everywhere else. If nothing eligible is found, the whole transaction rolls back and the caller gets a 409 — no partial booking is ever left behind.

This is standard pessimistic locking: locking the staff row (rather than trying to express "no overlapping interval" as a single unique DB constraint, which isn't expressible for variable-duration bookings) is what a database transaction can enforce that a plain "check availability, then insert" cannot — a second request blocks on the lock until the first commits, then sees the first's booking when it re-checks, and correctly loses the race. This works identically on MySQL (real row locks) and SQLite (the test suite's engine, where a transaction already serializes writers at the connection level, so the same code path holds).

**Concurrency test and its limitation**: `test_two_requests_for_the_same_staff_and_slot_result_in_exactly_one_successful_booking` fires two identical booking requests for the same staff/date/time back to back and asserts exactly one `201`/one `409`, and that exactly one matching row exists. PHPUnit runs this suite single-threaded against one SQLite connection, so genuinely simultaneous requests from separate OS processes/connections cannot be exercised here. What *is* exercised is the real code path a race would hit: the second request's transaction re-validates under the staff lock and observes the first request's already-committed row — this is the exact mechanism that makes concurrent requests behave as if serialized, whether or not the test can literally run them in parallel.

## Timezone strategy

`booking_date`/`start_time`/`end_time` (on both `bookings` and `booking_items`) are stored as **branch-local naive wall-clock values** — the same convention Phase 2's `branch_working_hours` and Phase 4's `staff_working_hours` already use (no timezone embedded in those columns either). No UTC conversion is introduced; comparisons (branch hours, staff hours, breaks, existing-booking overlap) are all naive-local-to-naive-local string/integer comparisons, exactly like the existing break/working-hours validation in Phases 2 and 4.

The one place real timezone awareness is needed is "what is *now*, locally, for this branch" — used for past-booking rejection and min-advance-booking. That's computed once per operation as `CarbonImmutable::now($branch->timezone ?: 'UTC')`, converting the server's current instant into the branch's civil time, then compared against the naive stored values as if they were already in that zone. No stored value is ever converted; only "now" is projected into the branch's zone. DST transitions therefore only affect that single "now" conversion (handled correctly by PHP's tz database) and never distort a stored booking's civil time — a booking made for "10:00" stays "10:00" regardless of DST, matching how a salon actually thinks about its own clock.

**Known limitation**: branch hours that cross midnight (e.g. open 23:00–01:00) are not supported — `TimeMath` wraps a computed end time back into a 0–23 hour range rather than rolling into the next calendar day. This mirrors the fact that Phase 2 never handled cross-midnight hours either; it's called out here as a pre-existing, documented limitation rather than a new one.

## Past bookings

`BookingService::assertWithinBookingWindow()` rejects any `create`/`reschedule` where the target date/time (evaluated in the branch's local "now") is in the past, independent of whatever the availability endpoint returned earlier — the same re-validation-under-lock principle as double-booking prevention. Historical (already-created) bookings remain fully readable regardless of their date.

## Status model

`BookingStatus` (`pending`, `confirmed`, `checked_in`, `in_service`, `completed`, `cancelled`, `no_show`) exposes `canTransitionTo()`, enforced by every mutation:

```
pending → confirmed | cancelled
confirmed → checked_in | cancelled | no_show
checked_in → in_service | cancelled
in_service → completed | cancelled
completed | cancelled | no_show → (terminal)
```

`POST /bookings/{booking}/confirm` is the only path to `confirmed`; `POST /bookings/{booking}/cancel` (owner/staff) and `POST /customer/bookings/{booking}/cancel` are the only paths to `cancelled`; `PATCH /bookings/{booking}` (owner/staff only) handles the remaining operational transitions (`checked_in`, `in_service`, `completed`, `no_show`) plus `notes` edits. This split keeps each endpoint's business rules (e.g. cancellation-window enforcement) unambiguous rather than folding every transition into one generic PATCH.

## Pricing

`subtotal` is the sum of each item's snapshotted `service_price` (× `quantity`, always `1` in Phase 6 — the column exists for a possible future multi-quantity/group-service case but is not exposed to clients yet). `discount` and `tax` are structural columns set to `0` for every booking; Phase 6 does not implement coupons, discounts, or tax rules — `total = subtotal - discount + tax`. Nothing about price is ever accepted from the client; it is always read fresh from the `Service` row inside the creating transaction.

## Domain events (no notifications yet)

`BookingCreated`, `BookingConfirmed`, `BookingCancelled`, `BookingRescheduled`, `BookingCompleted` are dispatched at the corresponding points in `BookingService`. None has a listener registered — they exist purely as attachment points for a future notification system (WhatsApp/SMS/email/push), which is explicitly out of scope for Phase 6.

## APIs

Owner/staff surface (`auth:sanctum` + `tenant.context`, `TenantManagementController::viewableTenant()` — see Authorization below):

- `GET|POST /bookings`, `GET|PATCH /bookings/{booking}` — list (filters: `date`, `status`, `branch_id`, `customer_id`, `staff_id`; paginated), create, view, and update (`status` ∈ `checked_in|in_service|completed|no_show`, `notes`).
- `POST /bookings/{booking}/confirm`, `POST /bookings/{booking}/cancel`, `POST /bookings/{booking}/reschedule`.

Customer self-service surface (`auth:sanctum` only — customers hold no tenant membership, same reasoning as `/customer/profile` in Phase 5):

- `GET|POST /customer/bookings`, `GET /customer/bookings/{booking}`, `POST /customer/bookings/{booking}/cancel`, `POST /customer/bookings/{booking}/reschedule`. `customer_id` is never accepted from the client — it is resolved server-side from the authenticated user's own `customer_profiles` row for the target branch's tenant; if none exists, a 404 asks the salon to register the customer first (self-service profile provisioning during a first booking is intentionally deferred — see `CUSTOMER_ARCHITECTURE.md`).

Availability (`auth:sanctum` only, **not** `tenant.context`): `GET /branches/{branch}/availability?date=...&service_ids[]=...&staff_id=...` — one endpoint serves both owner/staff and customers, since availability is not tenant-configuration data; it resolves the branch's tenant directly from the branch ID (bypassing the tenant scope explicitly, the same reviewed pattern as the customer self-service surface) rather than requiring the caller to already be a tenant member.

## Authorization

- **Salon owner / super admin**: full access to the owner/staff booking surface.
- **Staff**: the *same* full operational access as owner on the booking surface (create/update/confirm/cancel/reschedule/view) — this is a deliberate broadening relative to Phases 4–5's conservative "staff read-only" default, because running the day-to-day appointment book is core front-desk work and the Phase 6 brief explicitly grants staff update access to bookings, unlike its treatment of staff/customer records. Implemented via a new `TenantManagementController::viewableTenant()` (reuses the existing `TenantPolicy::view` gate — any tenant member) rather than `managedTenant()` (owner/super-admin only) for every `BookingController` action.
- **Customer**: only the `/customer/bookings*` surface, and only their own bookings, resolved by `user_id`, never by a client-supplied ID.

## Tenant isolation

`Booking`, `BookingItem`, and `BookingStatusHistory` use `BelongsToTenant` exactly like every prior phase. Direct-ID access to another tenant's booking resolves to 404 through scoped queries. Cross-tenant resource references (a Tenant A booking naming a Tenant B branch, customer, service, or staff member) are rejected server-side — either by Form Request validation (`Rule::exists(...)->where('tenant_id', ...)`) or, for the branch/customer/service *active* re-checks, inside `BookingService` itself — never trusted from the request payload.
