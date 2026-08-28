# Reporting & Analytics Architecture

Phase 13 gives the Salon Owner real, server-computed business reports — revenue, bookings, customers, services, staff performance, branches, coupons, membership, and loyalty — built entirely on Phase 1–12 data. It is not a separate reporting application: the ten new endpoints live in the existing `App\Http\Controllers\Api\V1` namespace behind the existing `auth:sanctum` + `tenant.context` + `subscription.active` middleware group, and the Flutter side is a new `Reports` section inside the existing Owner App (`mobile/lib/features/owner/reports/`), reached from the owner's existing `More` tab — not a new bottom-nav destination, not a second Flutter project.

Every number in every report is a real aggregate query result. Nothing is estimated, sampled, or hard-coded; where a metric can't be computed accurately from what Phases 1–12 actually store (see "Staff utilization" below), it is omitted rather than faked.

## Where the code lives

```
app/Support/
  DateRange.php                  # resolves range/from/to into a concrete, timezone-anchored start/end
  ReportTimezoneResolver.php     # decides which timezone "today" etc. are resolved against
  ReportSeriesBuilder.php        # zero-fills a day/week/month time series

app/Http/Requests/Reports/
  Concerns/HasReportFilterRules.php   # shared, composable filter/pagination/sort validation rules
  {Dashboard,Revenue,Booking,Customer,Service,Staff,Branch,Coupon,Membership,Loyalty}ReportRequest.php

app/Services/Reports/
  Concerns/FiltersBookings.php        # the one `bookings` query builder every report composes from
  Concerns/QueriesBookingItems.php    # the one `booking_items` JOIN query + discount-allocation formula
  {Dashboard,Revenue,Booking,Customer,Service,Staff,Branch,Coupon,Membership,Loyalty}Report.php
  StaffUtilizationCalculator.php

app/Http/Controllers/Api/V1/ReportController.php   # ten thin actions; no SQL or aggregation here

mobile/lib/features/owner/reports/
  data/models/            # one plain Dart class per report response, hand-written fromJson
  data/repositories/reports_repository.dart
  presentation/providers/reports_providers.dart      # FutureProvider per report + one shared ReportFilter
  presentation/screens/                               # hub + one screen per report
  presentation/widgets/   # ReportScaffold, ReportFilterBar, ReportStatCard, ReportLineChart, ReportBarChart
```

This mirrors the "reusable report/query classes rather than SQL in controllers" architecture called for by the phase brief: a `ReportController` action does exactly three things — authorize via `managedTenant()`, resolve a `DateRange` via `ReportTimezoneResolver`, and hand the validated filters to one `App\Services\Reports\*Report::generate()` class. All SQL lives in the `Report` classes and their two shared `Concerns` traits.

## Report response envelope

Every report uses the project's one existing envelope (`App\Support\ApiResponse::success`):

```json
{ "success": true, "message": "Revenue report retrieved.", "data": { "summary": {...}, "series": [...], "breakdown": {...} } }
```

Inside `data`, a report includes whichever of `summary` / `series` / `breakdown` / `data` (a paginated list) apply to it — there is no single fixed shape across all ten reports, because not every report has a time series or a breakdown. What's guaranteed is that `summary` (when present) never depends on pagination, and a paginated `data` list always uses the same `page`/`per_page` parameters and the same "belongs to this tenant" ID validation as every other list endpoint in the app.

## Date range resolution

Every report accepts `range` (one of `today`, `yesterday`, `this_week`, `last_week`, `this_month`, `last_month`, `this_year`, `custom`, default `this_month`) and, for `custom`, `from`/`to` (`Y-m-d`, `to >= from`). `App\Support\DateRange::resolve()` is the single place that turns these into a concrete `CarbonImmutable` start/end pair — no controller or report class computes a date boundary itself. An invalid preset or an incomplete/backwards custom range is a `422` with a field-level validation error, never a silently-clamped range.

`DateRange` also derives `defaultGroupBy()` (day for ranges up to ~2 months, week up to a year, month beyond that) so a caller who doesn't pass `group_by` still gets a sensibly-bucketed series, and `dailyDates()`, which `ReportSeriesBuilder` uses to zero-fill every bucket in the range — a chart never silently skips a day/week/month with no bookings.

## Timezone handling

`booking_date`/`start_time`/`end_time` on `bookings` and `booking_items` are branch-local naive wall-clock values, per the convention already established in `BOOKING_ENGINE.md` — never converted to or from UTC. Reports must resolve "today"/"this month"/etc. in that same local frame, or a range boundary silently drifts by a day relative to what the salon actually means by "today" (the phase brief's own example: a booking at `2026-08-27 00:30` local time must land on `2026-08-27`, not whatever date the server's UTC clock happens to be on).

`App\Support\ReportTimezoneResolver::resolve($tenant, $branchId)` is the single place this decision is made:

- A report filtered to one `branch_id` uses **that branch's own `timezone` column** — the exact timezone its `booking_date` values were captured in.
- A tenant-wide report (no branch filter) uses the **salon's `timezone` column**. A tenant operating branches across differing timezones gets an approximation for any branch other than the one the salon's timezone matches — this is a documented limitation, not a silent bug, since Phase 1–12 has no concept of an aggregate "tenant timezone" independent of one branch or the salon record.

This is exercised by `ReportsApiTest::test_today_range_resolves_against_salon_timezone_not_server_utc`, which fixes the server clock inside a UTC window that is already the next calendar day in `Asia/Kolkata` and asserts the `today` preset — and `GET /dashboard/summary` — both follow the salon's clock, not the server's.

**`DashboardController::summary()` had this exact bug** before Phase 13: it computed `CarbonImmutable::today()` with no timezone argument, i.e. the server's configured zone (`config/app.php` → UTC), not the salon's. This is now fixed to call `ReportTimezoneResolver::resolve($tenant, null)` — a minimal, targeted fix (not a rewrite of the Phase 8 dashboard), covered by the same regression test above.

## Tenant isolation

No report ever accepts a `tenant_id` from the client. `ReportController` resolves the tenant exclusively from `TenantManagementController::managedTenant()` → `TenantContext::require()`, which is itself populated by the `tenant.context` middleware from the authenticated user's session (or the `X-Tenant-Slug` header for a `super_admin`). Every Eloquent model queried by a report (`Booking`, `Customer`, `Staff`, `Branch`, `Coupon`, `CouponUsage`, `MembershipPlan`, `CustomerMembership`, `LoyaltyAccount`, `LoyaltyTransaction`) carries the `BelongsToTenant` global scope, so a plain `Booking::query()` is already tenant-scoped without an explicit `where`.

The one place this needs a manual `where('b.tenant_id', ...)` is `QueriesBookingItems::bookingItemsQuery()`, which uses `DB::table()` (a raw query builder join across `booking_items`/`bookings`, chosen for aggregate performance over large row counts) — `DB::table()` bypasses Eloquent's global scope entirely, so that `where` is unconditional and never optional.

Every ID filter (`branch_id`, `staff_id`, `service_id`, `category_id`, `customer_id`, `coupon_id`, `membership_plan_id`) is validated with `Rule::exists(...)->where('tenant_id', $currentTenantId)` in `HasReportFilterRules` — a filter ID belonging to another tenant fails validation with a `422`, it is never silently ignored or (worse) used to leak another tenant's row. `ReportsApiTest::test_tenant_a_cannot_see_tenant_bs_report_data_or_use_its_ids_as_filters` covers both the "no cross-tenant data leaks into an unfiltered report" case and the "a cross-tenant ID as a filter is rejected" case.

## Authorization

Every `ReportController` action calls `managedTenant()` — owner (or `super_admin`) only, via `TenantPolicy::manage()`. This deliberately differs from `DashboardController::summary()`, which staff can also read via `viewableTenant()`: Phase 13 reports are owner-only across the board (staff performance, revenue, and customer data are not staff-visible), per the phase brief. `ReportsApiTest::test_owner_can_access_reports_but_staff_and_customer_cannot` covers a staff session and a customer session each getting `403` from multiple report endpoints. No platform-wide/super-admin report endpoint was added — Phase 13 explicitly excludes it, and none of the ten endpoints reads across tenants.

## Metric definitions

Precise, in one place, so no report's terminology is ambiguous:

- **Revenue** = the `total` (subtotal − discount + tax; tax is currently always 0, no tax engine exists yet) of `COMPLETED` bookings only. There is no per-booking payment/POS capture anywhere in Phases 1–12 — `Payment`/`Invoice` belong exclusively to SaaS subscription billing (see "SaaS billing report" below) — so this figure is the *value of service rendered, recognized at completion*, and is never called "cash collected" or "amount paid."
- **Gross booking value** = `SUM(subtotal)` of the population in question. **Discount** = `SUM(discount)`. **Net revenue** = `SUM(total)`.
- **Average booking value** = net revenue ÷ completed-booking count, for whichever population the report is scoped to (branch/staff/service/overall). Cancelled and no-show bookings are always excluded from every revenue figure — they carry no completed value.
- **Total bookings** = every non-deleted booking in the filtered date range, regardless of status. **Completed / Cancelled / No-show bookings** = the count with that exact `BookingStatus`.
- **Cancellation rate** = `cancelled_bookings ÷ total_bookings`. **No-show rate** = `no_show_bookings ÷ total_bookings`. Both denominators are *every* booking in the range (not just terminal ones) — a range with mostly still-pending bookings correctly shows a low rate rather than an inflated one.
- **New customer** = a `customer_profiles` row whose `created_at` falls inside the selected range.
- **Active customer** = a customer with at least one non-cancelled booking in the range.
- **Returning customer** = a customer who booked in the range **and** has a `COMPLETED` booking dated before the range started — i.e. a real visit predates this period, not merely an earlier signup.
- **Repeat booking rate** = (customers with 2+ `COMPLETED` bookings in the range) ÷ (customers with 1+ `COMPLETED` booking in the range).
- **Top customer "total spend"** = that customer's `COMPLETED`-booking `total` sum *within the selected range* — never an all-time or re-derived figure.
- **Staff completion rate** = a staff member's completed booking-item count ÷ their assigned booking-item count, for the filtered range.
- **Staff utilization** (see below) = booked minutes ÷ available minutes.

## Revenue attribution (staff & service)

`staff_id` and `service_id` live on `booking_items`, not `bookings` — one booking can contain several services assigned to several different staff members. Revenue-by-staff and revenue-by-service therefore attribute at the **item** level: each `booking_items.subtotal` counts toward exactly the one staff member / service on that row, so a two-staff booking's revenue splits across both staff rather than being counted once per staff (no double counting).

A booking's `discount` is a single value on the parent `bookings` row — it isn't itemized per service. `QueriesBookingItems::allocatedDiscountExpression()` allocates it **proportionally** to each item by its share of the booking's subtotal:

```
item_discount = (item.subtotal / booking.subtotal) * booking.discount
```

The sum of every item's allocated discount for one booking always equals that booking's real `discount` — this never invents or drops money, only distributes an existing figure. (The SQL expression casts to a floating type explicitly, because SQLite performs integer division when both operands happen to be whole numbers, which would silently zero out every allocation on that driver; MySQL/Postgres already return a decimal here regardless.) `ReportsApiTest::test_revenue_by_staff_attributes_by_booking_item_without_double_counting` asserts the allocated amounts sum back to the booking's total exactly.

Both revenue-by-staff and revenue-by-service read `booking_items.service_price`/`subtotal` — the historical price **snapshot** captured at booking time, never the service's current, possibly since-changed `price`. `ReportsApiTest::test_revenue_by_service_uses_historical_price_snapshot_not_current_price` covers this directly: a service's price is changed after a booking is recorded, and the report still reflects the original price.

## Staff utilization

`available_minutes` ÷ `booked_minutes` × 100, computed by `StaffUtilizationCalculator` purely from each staff member's own `staff_working_hours`, `staff_breaks`, and `staff_leaves` rows for every calendar day in the range — never estimated. `booked_minutes` sums `booking_items.service_duration_minutes × quantity` for items whose parent booking is in a "blocking" status (`BookingStatus::blockingBooking()` — every status except `CANCELLED`/`NO_SHOW`, the same definition the booking-engine's own availability logic already uses).

Branch holidays are subtracted from `available_minutes` **only when the report is scoped to one `branch_id`** — a staff member can work across branches with different holiday calendars, so a tenant-wide figure cannot correctly net out any single branch's holidays. This is a documented simplification: `utilization_percent` is `null` (an explicitly omitted metric, per "no fake analytics") for a staff member with zero available minutes in the range, rather than a division-by-zero or a fabricated 0%/100%.

## Customer/service/branch reports

- **Service report**: most-booked services and the category breakdown, both from `booking_items` historical snapshots. `average_price` is the average of `service_price` (the historical per-booking price), not the service's current price.
- **Branch report**: every branch belonging to the tenant appears, including one with zero bookings in the range — a branch comparison must never silently drop an inactive-looking branch.
- **Booking report**: status counts, the status trend series, cancellation reasons (grouped, `Not specified` when none was recorded), and the by-branch/by-staff breakdown all live in one endpoint (`GET /reports/bookings`) — the phase's own route list (`GET /reports/bookings`) has no separate cancellation/no-show endpoints, so those are folded in here rather than invented as new routes.

## Coupon, membership, and loyalty reports

- **Coupon report** reads exclusively from `coupon_usages` — an immutable, one-row-per-application ledger — never the coupon's *current* `discount_type`/`discount_value`. Editing or deactivating a coupon after the fact never rewrites its historical usage figures. `usage_rate` = `times_used ÷ usage_limit` when the coupon has a limit, else `null` (never a division against an undefined denominator).
- **Membership report** counts `customer_memberships` whose `starts_at` (purchase/grant date) falls in the range, grouped by their **current** `status` — a membership doesn't freeze its status at the moment it was granted, so a report about "memberships started in March" still reflects whether each has since expired. `membership_revenue` sums `membership_payments` (Phase 12, PAID only) — **deliberately never** the SaaS `payments`/`invoices` tables (Phase 10), which bill the tenant for platform access, not the tenant's own customers for a membership. Mixing the two would misrepresent both figures.
- **Loyalty report** reads exclusively from the `loyalty_transactions` ledger, never the current `loyalty_accounts.balance` alone (a balance is a snapshot, not a history). `points` is a signed delta on each row; `EARN` is always positive, `REDEEM`/`EXPIRE` always negative — the report reports earned/redeemed/expired as positive magnitudes, and `ADJUSTMENT`/`REVERSAL` keep their sign since either direction is legitimate.

## SaaS billing report

Owner-visible subscription status, payments, and invoices already exist as the Phase 10 `GET /subscription`, `/subscription/payments` (`PaymentHistoryScreen`), and `/subscription/invoices` (`InvoiceHistoryScreen`) endpoints/screens — Phase 13 reuses these rather than duplicating a new `reports/billing` endpoint. `Subscription`/`Payment`/`Invoice` are platform billing records (what the tenant pays this SaaS product) and are never combined with, or presented alongside, booking/membership revenue (what the tenant's own customers pay the salon) — see "Membership report" above for the same distinction applied to `MembershipPayment`.

## Money & currency

Every monetary field follows the existing project convention: `decimal(12,2)` columns, `decimal:2` Eloquent casts, formatted through PHP's `number_format($value, 2, '.', '')` before it reaches JSON — a string like `"1234.00"`, never a float and never cents-as-integer. This matters because summing several cast-decimal-string attributes in PHP (e.g. a Collection's `->sum('total')`) produces a float, which is then re-formatted back to a fixed 2-decimal string rather than passed through raw — every report class does this consistently via a shared `money()` helper (`FiltersBookings::money()`) or an equivalent inline `number_format` call.

The application is INR-only in practice today: `currency` columns exist on some models (`MembershipPlan`, `Payment`, `Invoice`, `CustomerMembership`) but no multi-currency logic exists anywhere, and Phase 13 does not introduce any — the Flutter side renders every amount with a literal `₹` prefix, matching the existing (pre-Phase-13) dashboard convention.

## Filters, pagination, sorting

Not every report exposes every filter — only the ones that make business sense for it (e.g. `coupon_id` on the coupon/booking reports, not on the service report). `HasReportFilterRules` composes the shared building blocks (`dateRangeRules`, `branchFilterRule`, `staffFilterRule`, `serviceFilterRule`, `categoryFilterRule`, `statusFilterRule`, `customerFilterRule`, `couponFilterRule`, `membershipPlanFilterRule`, `groupByRule`, `paginationRules`, `sortRules`) so each `*ReportRequest::rules()` only lists what applies. `page`/`per_page` (max 100) follow the same convention as every other paginated endpoint in the app. Sorting always goes through an explicit server-side whitelist (`sortRules($allowed)`); a client-supplied column name never reaches raw SQL.

## Caching

No report response is cached. The phase brief is explicit that correctness outranks caching benefit when unsure ("if unsure, skip caching") — given the aggregate queries here run over indexed, date-bounded ranges (see below) rather than full-table scans, and given a cache key would need to encode tenant + report + every filter to be safe, the simplicity of "always query" was judged the better tradeoff for this phase. This can be revisited later if a specific report proves expensive at real data volumes.

## Database indexes added

Phase 1–12 already indexes `bookings`/`booking_items` well for the report query patterns that reuse them (`[tenant_id, branch_id, booking_date]`, `[tenant_id, status]`, `[tenant_id, staff_id]` on `booking_items`, etc.). Migration `2026_08_27_100200_add_reporting_indexes.php` adds the handful of composite indexes Phase 13's new query patterns actually need and that weren't already covered:

| Table | Index | Why |
|---|---|---|
| `booking_items` | `(tenant_id, service_id)` | Service/revenue-by-service reports `GROUP BY bi.service_id` |
| `customer_profiles` | `(tenant_id, created_at)` | Customer report's "new customers" filter and growth series range-scan `created_at` |
| `coupon_usages` | `(tenant_id, used_at)` | Coupon report's date-range filter — the ledger's primary time dimension |
| `customer_memberships` | `(tenant_id, starts_at)` | Membership report ranges over `starts_at` (the existing `[tenant_id, status, expires_at]` index doesn't cover this) |
| `loyalty_transactions` | `(tenant_id, created_at)`, `(tenant_id, type)` | Loyalty report's date-range filter and per-type ledger sums |

This is purely additive — no column or data changes, no new tables.

## Performance

Every report aggregates in SQL (`selectRaw`, `GROUP BY`, `COUNT`/`SUM`/`AVG`) rather than pulling rows into PHP and summing a Collection, with two narrow exceptions where a small, already-filtered-by-date row set is grouped in PHP because the aggregation needs values that don't fit cleanly into one SQL grouping (e.g. `CustomerReport`'s per-customer status-presence checks). Revenue/staff/service attribution across the `booking_items` ⋈ `bookings` join uses the raw query builder (`DB::table()`) specifically to avoid Eloquent model hydration over what can be a large row count. Pagination is always applied after sorting, never before.

## Export readiness

No PDF/Excel export exists (none was requested, and the phase brief explicitly says not to add a heavy export system). Every report's tabular data (`data`/`breakdown` arrays) already has stable column names, predictable server-side sorting, and standard pagination — the shape a future CSV/PDF export would consume directly without any response redesign.

## Testing

`tests/Feature/ReportsApiTest.php` covers: owner/staff/customer authorization per endpoint; cross-tenant data isolation and cross-tenant filter-ID rejection; date-range preset/custom resolution including invalid-range rejection; the salon-timezone-vs-server-UTC "today" boundary (including the `DashboardController` regression); revenue aggregation excluding cancelled bookings; staff/service revenue attribution without double-counting; historical price-snapshot correctness; booking status counts and rate calculations; new/returning customer classification; staff completion rate; branch reports including zero-booking branches; coupon-usage-ledger correctness under a later coupon config change; membership status/revenue; and loyalty ledger earn/redeem/outstanding balance. `mobile/test/reports/` covers model `fromJson` parsing, repository query-parameter construction (including that `null` filters are omitted, not sent as literal nulls), and a report screen's loading/data/error/empty states.

## Explicitly not built in Phase 13

Multi-currency support, a platform-wide/super-admin report surface, a PDF/Excel export pipeline, AI-driven analytics, and estimated/fabricated metrics of any kind (growth %, conversion rate, retention, or utilization figures the underlying data can't actually support — these are omitted rather than invented). Security hardening and deployment remain out of scope for this phase, per the phase brief — see `MODULE_ROADMAP.md`.

## Phase 14 re-audit

Phase 14's security audit specifically re-checked report tenant isolation and query safety and found no regression: every filter's `Rule::exists(...)->where('tenant_id', ...)` was re-verified intact, the one `whereRaw` outside this module was confirmed to take no user input, every dynamic sort still goes through a whitelist, and no report query pulls an unbounded row set into PHP. A general 120/min-per-user API rate limit was added at the platform level (see `SECURITY_HARDENING.md`) — applied to these endpoints like every other authenticated route, generous enough not to affect normal report navigation. No report-specific change was needed. See `SECURITY_HARDENING.md`/`PERFORMANCE_HARDENING.md` for the full audit.
