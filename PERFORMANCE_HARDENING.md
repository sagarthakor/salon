# Performance Hardening (Phase 14)

A production-oriented performance audit of Phases 1–13: N+1 queries, missing indexes, unbounded queries, report/dashboard query cost, caching, and Flutter-side rendering/network efficiency. Every item below reflects what was actually found by reading the code — no benchmark numbers are claimed unless they were actually measured, per the phase brief's explicit instruction not to invent figures.

---

## Fixed in this phase

### 1. Checkout no longer holds a DB transaction across the gateway call

- **Component:** `BillingService::initiateCheckout()`, `MembershipService::initiateCheckout()`
- **Before:** Invoice/payment row creation **and** the outbound Razorpay `createOrder()` HTTPS call ran inside the same `DB::transaction()` — a database connection and row locks held open for the full duration of a network round trip (bounded by Laravel's 30s default HTTP timeout, but that's still 30s of a held connection/lock in the worst case).
- **After:** The transaction now covers only the row creation (fast, local). The gateway call happens afterward, outside any transaction/lock. See "Webhook & payment security" section 4 in `SECURITY_HARDENING.md` for the accompanying idempotency-retry change this required.
- **Measurement:** Not benchmarked (no load-testing tooling available in this environment) — this is a structural fix to a documented anti-pattern (holding a DB lock across a network call), not a measured-improvement claim. The `FakePaymentGateway` used in tests returns instantly, so the existing test suite cannot demonstrate a wall-clock difference either; the correctness/reliability regression test (`test_checkout_retry_after_a_gateway_failure_reuses_the_same_pending_payment_and_invoice`) confirms the new code path behaves correctly, not that it's faster.
- **Tradeoff:** A payment row can now exist as PENDING with no `gateway_order_id` for longer if the gateway is slow (previously, the whole thing would have still been holding a lock for that same duration — this isn't a new state, just no longer one that blocks other transactions).

### 2. Explicit HTTP timeouts on the Razorpay gateway client

- **Component:** `RazorpayGateway::client()`
- **Before:** No explicit timeout — bounded only by Laravel's HTTP client default (30s request / 10s connect), which is longer than any of these synchronous, user-facing calls should legitimately need.
- **After:** `->timeout(10)->connectTimeout(5)` — fails fast on a slow/unresponsive gateway instead of holding a PHP-FPM worker (and a customer-facing HTTP response) for up to 30 seconds.
- **Measurement:** Not benchmarked — a bound-tightening change, not a measured improvement (there is no slow-gateway scenario to reproduce without a real or simulated slow endpoint).

### 3. Added five database indexes for real query patterns that lacked one

| Table | Index | Query pattern it serves |
|---|---|---|
| `customer_memberships` / `loyalty_accounts` / `loyalty_transactions` | *(see SECURITY_HARDENING.md #6 — FK hardening, not an index change)* | — |
| `notifications` | `(user_id, created_at)` | The notification inbox's primary query: `WHERE user_id = ? ORDER BY created_at DESC`. Existing indexes covered `user_id` alone, `created_at` alone, `(notifiable_type, notifiable_id)`, and `(user_id, read_at)` — none covered the actual filter+sort combination together, so this couldn't be satisfied by a single index scan. |

(Phase 13 already added five reporting-specific indexes in a prior migration — `booking_items(tenant_id, service_id)`, `customer_profiles(tenant_id, created_at)`, `coupon_usages(tenant_id, used_at)`, `customer_memberships(tenant_id, starts_at)`, `loyalty_transactions(tenant_id, {created_at, type})` — re-verified as still present and correct in this phase, not duplicated.)

- **Measurement:** Not benchmarked against real data volume (the dev/test databases are small). The notifications index addition is justified by the query shape alone (a compound `WHERE`+`ORDER BY` that no existing index covers), not a measured before/after.

### 4. Minor Flutter rebuild scoping

- **Component:** `mobile/lib/features/owner/dashboard/presentation/screens/dashboard_tab.dart`
- **Before:** `ref.watch(authControllerProvider).user` rebuilds the entire dashboard tab on any `AuthState` change, not just a change to `user`.
- **After:** `ref.watch(authControllerProvider.select((state) => state.user))` narrows the rebuild trigger to the one field actually read.
- **Measurement:** Not benchmarked — a low-practical-impact fix (a dashboard header greeting), included because it was a genuine, easily-fixed instance found during the audit, not because it was measured to matter.

---

## Reviewed — confirmed no fix needed

- **Report/dashboard query cost.** Each of the 10 `app/Services/Reports/*Report.php` classes issues roughly 5–10 aggregate SQL queries per request (counted by reading the code, e.g. `RevenueReport::generate()` ≈ 7: totals, daily series, byBranch×2, byStaff×2, byService×1) — none loop per-row, none pull an unbounded row set into PHP for summation. `by_branch`/`by_staff`/`by_service` breakdowns aren't paginated, but their cardinality is bounded by the tenant's *own* branch/staff/service count (realistically dozens, not thousands), and a tenant can only inflate its own report's cost by creating more of its own resources — not a cross-tenant abuse vector. No change made.
- **N+1 queries.** Checked booking list/detail (`BookingController` eager-loads `['customer','items']` and `['items.staff','items.service','customer','statusHistories']` respectively), customer list, staff list, notification list, the owner dashboard, and the Phase 13 report breakdowns (which batch entity names via a single `whereIn(...)->pluck('name','id')` rather than per-row lookups). No N+1 found in any endpoint checked.
- **Pagination/sorting abuse.** Every paginated list endpoint clamps `per_page` to 100 (14+ occurrences checked). Every dynamic `sort` parameter anywhere in the app goes through an explicit whitelist before reaching `orderBy()`. No unbounded-extraction path exists.
- **Caching.** Exactly one `Cache::` call exists in the entire app (the FCM OAuth token, keyed by a fixed service-account identity — not tenant-scoped, no cross-tenant contamination risk). Reports deliberately use no caching (a Phase 13 decision, re-confirmed unchanged: the phase brief explicitly says correctness outranks caching benefit when unsure, and the aggregate queries here already run over indexed, date-bounded ranges rather than full-table scans). No caching was added in this phase — nothing measured to justify the complexity of tenant-scoped cache keys and invalidation.
- **Soft-delete safety / orphaned financial data.** `bookings`, `payments`, `invoices`, `coupon_usages`, `loyalty_transactions`, `customer_memberships` have no `delete()` call anywhere in the app — pure append-only/status-transition tables. `Customer`/`Service`/`Staff`/`Branch`/`Coupon`/`MembershipPlan` use `SoftDeletes` correctly. (The one real defect found in this area — inconsistent cascade FK behavior — is a data-integrity/security finding, documented in `SECURITY_HARDENING.md` #6, not a performance item.)
- **Redundant indexes.** No two indexes on the same table were found to be duplicates or strict prefix-overlaps of each other, across every table reviewed (`bookings`, `booking_items`, `customer_profiles`, `services`, `staff_profiles`, `branches`, `notifications`, `notification_deliveries`, `coupons`, `coupon_usages`, `membership_plans`, `customer_memberships`, `loyalty_accounts`, `loyalty_transactions`, `payments`, `invoices`, `subscriptions`).
- **External API timeouts (FCM, WhatsApp).** Neither sets an explicit timeout, relying on Laravel's HTTP client default (30s/10s) — bounded, not unbounded, so not a defect. Not changed in this phase (unlike Razorpay's checkout path, these run from queued jobs, not a synchronous user-facing request, so the "fails fast for the user" motivation for an explicit shorter timeout doesn't apply the same way) — left as an opportunity for a future pass rather than a fix made here, to avoid over-engineering a change with no demonstrated need.
- **Flutter large lists.** Booking list, customer list, and notification list all use `ListView.separated`/builder-backed lazy rendering. Phase 13 report screens use a plain `ListView(children:[...])`, which is correct since those lists are already server-paginated to a bounded page size — not a defect.
- **Flutter image loading.** No `Image.network`/`CachedNetworkImage`/`Image.memory` usage exists anywhere in the app — `image_picker` is used only to *upload* a photo; nothing yet renders one back. No image-caching concern exists because there is no image-rendering code to have one, and no unused image-caching dependency exists in `pubspec.yaml` to remove.
- **Flutter duplicate requests.** Every Riverpod provider checked (dashboard, reports, bookings, customers) is defined once at top level, never constructed inline inside a widget's `build()` — the pattern that would cause provider-recreation-on-rebuild bugs. None found.

## Not addressed in this phase (explicitly out of scope)

No Redis, no Elasticsearch, no separate reporting database, no additional caching layer — none were found to be justified by an actual measured or reasoned bottleneck, and the phase brief explicitly warns against introducing them speculatively. Load testing / real benchmark measurement against production-scale data volume is not available in this environment and is not claimed to have been performed.
