# Security Hardening (Phase 14)

A production-oriented security audit of Phases 1–13, performed by direct code inspection (not assumption) across authentication, authorization, tenant isolation, mass assignment, concurrency, payment/webhook security, logging, secrets, rate limiting, and the Flutter client. Every finding below was verified against the actual code before being recorded — nothing here is speculative, and nothing was invented to pad the list.

**Severity scale:** CRITICAL / HIGH / MEDIUM / LOW / INFO. No CRITICAL or HIGH finding was identified in this pass.

---

## Findings — fixed

### 1. [MEDIUM] Booking staff-conflict check could miss a just-committed conflicting booking under MySQL REPEATABLE READ

- **Component:** `app/Services/Booking/BookingService.php`, `staffEligibleForSpan()`
- **Evidence:** Booking creation locks the assigned `Staff` row (`resolveAndLockStaff()`, `->lockForUpdate()`), but the subsequent check for a conflicting existing booking on that staff member (`BookingItem::query()->where('staff_id', ...)->whereHas('booking', ...)->get()`) was a **plain**, non-locking read. MySQL's default transaction isolation is REPEATABLE READ (confirmed: no `isolation_level` override anywhere in `config/database.php`, and `.env.example` targets `DB_CONNECTION=mysql` for production), under which a plain SELECT continues to use the transaction's original consistent-read snapshot even after the transaction has waited out and acquired a lock elsewhere. A locking read, by contrast, always reads the latest committed data regardless of snapshot.
- **Attack/failure trace:** Two overlapping booking requests for the same staff/slot both begin, each fixing its REPEATABLE READ snapshot at an early plain read (`Service::query()->whereIn(...)->get()`). Transaction A wins the staff-row lock, inserts its `BookingItem`, and commits. Transaction B, having been blocked on that same lock, now proceeds — but its plain conflict-check query still reflects its pre-A-commit snapshot, so it can fail to see A's just-committed item and conclude the slot is free, creating a real double-booking.
- **Why it wasn't caught by the test suite:** The project's test suite runs on SQLite, whose concurrency/isolation model differs from MySQL's REPEATABLE READ; SQLite's own `lockForUpdate()` is a syntactic no-op (`SQLiteGrammar::compileLock()` returns an empty string), so this class of bug is invisible under the existing tests regardless of what fix is applied.
- **Fix:** `staffEligibleForSpan()`'s conflict-check query now uses `->lockForUpdate()`, so it always reads the latest committed state once it runs (which, by that point in the call chain, is always after the staff-row lock has already serialized concurrent attempts).
- **Regression test:** Not practical in this environment — see "Known testing limitation" below. **Status: Fixed (code-reviewed); not exercised by an automated regression test.**

### 2. [LOW-MEDIUM] Coupon per-customer usage limit / first-booking-only check had the same snapshot-staleness gap

- **Component:** `app/Services/Pricing/CouponService.php`, `validate()`/`reserve()`/`hasPriorBookings()`
- **Evidence:** `reserve()` correctly locks the `Coupon` row before re-validating (`lockForUpdate()`), which fully protects the *total* `usage_limit` (the field the lock directly guards). But the *per-customer* usage count (`CouponUsage::where('coupon_id', ...)->where('customer_id', ...)->count()`) and the `first_booking_only` prior-booking check (`hasPriorBookings()`) were both plain reads — subject to the identical REPEATABLE READ staleness as finding #1. Two simultaneous bookings from the *same* customer against a `usage_limit_per_customer = 1` coupon would correctly serialize on the coupon-row lock, but the second request's plain re-check could still read pre-commit data and incorrectly pass.
- **Fix:** `validate()` now takes a `$forUpdate` parameter. `reserve()` (which already holds the coupon lock) passes `forUpdate: true`, upgrading both checks to locking reads (`lockForUpdate()->count()` and `lockForUpdate()->count() > 0` respectively — `exists()` isn't reliably combinable with `lockForUpdate()` across query builder internals, so the locked path counts instead). The unlocked preview path (`validate()` called directly from a price-preview endpoint) is unchanged — it must stay lock-free to avoid contention on every preview request.
- **Regression test:** Not practical in this environment, same reason as #1 — see "Known testing limitation" below. **Status: Fixed (code-reviewed); not exercised by an automated regression test.**

### 3. [MEDIUM] Webhook idempotency check treated "row exists" as "already processed," permanently swallowing a crashed delivery

- **Component:** `app/Http/Controllers/Api/V1/PaymentWebhookController.php`
- **Evidence:** The `WebhookEvent` row was created and committed *before* `$this->process($eventType, $payload)` ran (outside that transaction). The `alreadyProcessed` check only tested whether a row with that `gateway_event_id` existed — not whether `processed_at` was actually set. If `process()` threw for any reason (a transient DB error, an unexpected payload shape), the row already existed with `processed_at` still null. A Razorpay retry of that exact event would then find the row, conclude "already processed," and silently no-op forever — even though the payment/subscription/membership update never actually happened. This is a real reliability/business-impact gap: a customer could pay successfully at the gateway and never receive the access their payment was for.
- **Fix:** The idempotency check now requires `processed_at !== null` to short-circuit as a duplicate. A row that exists but was never marked processed is reused (not recreated, avoiding a duplicate-row insert conflict) and processing is genuinely retried.
- **Regression test:** `tests/Feature/BillingApiTest.php::test_webhook_retries_a_previously_unprocessed_event_row_instead_of_treating_it_as_a_duplicate` — seeds an unprocessed `WebhookEvent` row (simulating a crashed prior delivery), redelivers the same event, and asserts it now actually processes; a subsequent true duplicate delivery is still correctly a no-op. **Status: Fixed, regression-tested.**

### 4. [MEDIUM] Checkout held a DB transaction (and row locks) open across a synchronous Razorpay HTTP call

- **Component:** `app/Services/Billing/BillingService::initiateCheckout()`, `app/Services/Membership/MembershipService::initiateCheckout()`
- **Evidence:** Both methods wrapped invoice/payment row creation **and** the outbound `$this->gateway->createOrder(...)` HTTPS call inside the same `DB::transaction()`. This holds a database connection and row locks on the newly-inserted rows open for the full duration of an external network call — up to Laravel's default 30s HTTP timeout if Razorpay is slow — a real connection-pool-exhaustion and deadlock-adjacent risk under load, and exactly the pattern the phase brief's "External API timeouts"/"Deadlock" guidance calls out.
- **Fix:** The gateway call now happens **outside** any transaction, after the invoice/payment rows are already committed. To preserve idempotency-key retry semantics without this reordering causing duplicate invoices, `initiateCheckout()` now reuses an existing PENDING payment with no `gateway_order_id` (a prior attempt whose gateway call never completed) instead of creating a new one — this is a *better* recovery story than before, where a failed gateway call inside the old transaction would roll back and force a full re-creation on retry.
- **Regression test:** `tests/Feature/BillingApiTest.php::test_checkout_retry_after_a_gateway_failure_reuses_the_same_pending_payment_and_invoice` — simulates a gateway failure via a new `FakePaymentGateway::$failNextCreateOrder` flag, confirms the payment/invoice rows persist as PENDING with no `gateway_order_id`, then retries with the same `Idempotency-Key` and confirms the same rows are reused (no duplicate invoice) and the order is created successfully. **Status: Fixed, regression-tested.**

### 5. [MEDIUM] No general API rate limiting beyond login/register

- **Component:** `routes/api.php`, `bootstrap/app.php`
- **Evidence:** Only the `auth` route group (`POST /auth/login`, `POST /auth/register`) had a `throttle:` middleware (5/min by email+IP). Every other authenticated endpoint — all ten `/reports/*` aggregation endpoints, booking creation, price-preview, checkout, device-token registration — had zero application-level rate limit. An authenticated client (or a leaked/stolen bearer token) could hammer expensive endpoints with no throttle at all.
- **Fix:** Added two new named rate limiters in `AppServiceProvider`: `api` (120/min, keyed by user id, applied broadly to every authenticated route group) and a tighter `checkout` (10/min, keyed by user id) layered on top of it for the specific endpoints that call the payment gateway (`subscription/checkout`, `subscription/checkout/verify`, `subscription/renew`, `customer/membership/checkout`, `customer/membership/checkout/verify`). 120/min comfortably covers real mobile usage (dashboard refresh, report navigation, normal booking flow) while bounding abuse. The Razorpay webhook route (`POST /webhooks/razorpay`) is deliberately **not** throttled — it's gateway-authenticated via signature verification, not a client a mobile app talks to, and rate-limiting it risks dropping a legitimate Razorpay retry of a real event.
- **Regression test:** `tests/Feature/BillingApiTest.php::test_checkout_endpoint_is_rate_limited` — fires 11 checkout requests and asserts the 11th returns `429`. **Status: Fixed, regression-tested.**

### 6. [MEDIUM] Inconsistent cascade-delete on customer-linked loyalty/membership tables

- **Component:** `database/migrations/2026_08_27_100000_create_coupons_membership_loyalty_tables.php`
- **Evidence:** `customer_memberships.customer_id`, `loyalty_accounts.customer_id`, `loyalty_transactions.customer_id`, and `loyalty_transactions.loyalty_account_id` were all created with `cascadeOnDelete()` — inconsistent with every sibling financial/historical table in the *same migration* (`coupon_usages.customer_id` and `membership_payments.customer_id` both correctly use `restrictOnDelete()`, matching the project's own established pattern of protecting historical/financial records, also used by `bookings.customer_id`). Since `Customer` only ever soft-deletes through the current API (`CustomerController::destroy`), this cascade cannot fire through any reachable path today — but it is a real landmine: any future hard-delete of a customer row (an admin cleanup script, a GDPR-erasure feature, direct DB access) would silently and irrecoverably destroy that customer's entire loyalty ledger and membership history, with nothing to stop it.
- **Fix:** New migration `2026_08_27_100300_harden_loyalty_membership_fk_and_notification_index.php` changes all four foreign keys to `restrictOnDelete()`.
- **Regression test:** `tests/Feature/CouponMembershipLoyaltyTest.php::test_hard_deleting_a_customer_with_loyalty_or_membership_history_is_blocked_not_cascaded` — grants a membership and earns loyalty points for a customer, then asserts `Customer::forceDelete()` throws a `QueryException` rather than silently cascading. **Status: Fixed, regression-tested.**

### 7. [LOW] Placeholder SMS provider logged customer phone numbers and full message bodies in plaintext

- **Component:** `app/Services/Notifications/Providers/LogSmsProvider.php`
- **Evidence:** This intentional no-op stand-in (no real SMS vendor is configured yet) logged `['to' => $to, 'message' => $message]` at `info` level on every SMS-eligible notification — real phone numbers and full notification content (which can include booking details) accumulating indefinitely in the application log.
- **Fix:** Logs a masked phone number (first 4 digits, rest starred) and the message's length only, never its content.
- **Status: Fixed.** No regression test added (a log-content assertion for a placeholder class due for replacement wasn't judged worth the test-suite weight; verified by code review).

### 8. [LOW] `.env.example` ships `APP_DEBUG=true` with no production warning

- **Component:** `.env.example`
- **Evidence:** `config/app.php` itself defaults safely to `false` if `APP_DEBUG` is unset, so this only matters if someone copies `.env.example` straight into a production `.env` without changing it — a soft risk, since a debug response leaks stack traces/SQL/file paths.
- **Fix:** Added an inline comment above the line warning that production must override it to `false`.
- **Status: Fixed (documentation only — the value itself stays `true` for local-dev convenience, matching standard Laravel scaffolding).**

### 9. [LOW] Flutter debug network logging could print a plaintext password or gateway signature

- **Component:** `mobile/lib/core/network/api_client.dart`
- **Evidence:** The debug-only `LogInterceptor` (`kDebugMode`-gated, so it never runs in a release build) correctly excluded headers (so the bearer token was never logged) but logged full request/response **bodies**. `AppConfig.enableNetworkLogging` defaults to `true`, so any debug build — the default `flutter run` experience — would print a plaintext password on `/auth/login`/`/auth/register`, and could print a Razorpay payment signature on a checkout-verify call.
- **Fix:** Replaced the stock `LogInterceptor` with a small custom `_RedactingLogInterceptor` that recursively redacts any map key containing `password`, `signature`, `token`, or `secret` (case-insensitive) before printing — still headers-free, still `kDebugMode`-gated, still fully compiled out of release builds.
- **Status: Fixed.** No dedicated Flutter unit test added for the redaction logic itself — verified by code review; the interceptor is exercised indirectly by the existing repository/screen tests that already pass with it installed.

### 10. [Functional, not security — fixed alongside] iOS `Info.plist` missing camera/photo-library usage descriptions

- **Component:** `mobile/ios/Runner/Info.plist`
- **Evidence:** `image_picker` is a dependency (used for staff/service/category photo upload), but no `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` keys existed. On a real iOS device this causes an immediate **crash** when the picker is invoked, not merely a denied permission — found during the Flutter audit's static iOS review (Linux cannot build/run iOS to confirm at runtime).
- **Fix:** Added both keys with plain-language descriptions.
- **Status: Fixed (static review only — cannot be runtime-verified on this host; see "iOS limitations" below).**

---

## Findings — reviewed, no fix needed (documented for completeness)

These were specifically investigated and confirmed **not** to be vulnerabilities, or judged not worth changing:

- **Authentication.** Login/register return identical, non-distinguishing error messages (no user-enumeration via error text); passwords are never logged or returned in any response (`UserResource` excludes the field entirely); a registering client cannot set their own `role` (hardcoded to `customer` server-side, and `RegisterRequest` doesn't even accept the field); `throttle:auth` (5/min by email+IP) is verified wired up in code, not just documented.
- **Privilege escalation.** No API endpoint exists anywhere that attaches or modifies a `tenant_user` pivot role — tenant membership is created outside the API entirely (seeder/tinker), so there is currently no reachable path for a customer or staff user to escalate to `salon_owner` via the API. (This is also a product gap — no self-service "create a tenant and become its owner" flow exists yet — noted as INFO, not a vulnerability, and out of this phase's scope to add.)
- **Authorization coverage.** All 34 API controllers were individually checked: every action calls `managedTenant()`/`viewableTenant()`/`Gate::authorize()`/a Policy, or is one of a small, deliberately-public/self-scoped set (catalog browsing, customer self-service resolved only from the authenticated user's own id, the signature-verified webhook). No action was found with zero authorization check that should have one.
- **`BelongsToTenant` coverage.** All 35 models checked. Every tenant-owned business model uses the trait. The three models with a `tenant_id` column that don't (`NotificationPreference`, `UserDeviceToken`, `NotificationDelivery`) were each individually confirmed to have an intentional, correct alternative scoping strategy (see Phase 11's design — a personal/tenant-wide dual-scope table, and two write-only-from-the-dispatcher tables with no direct-access route at all).
- **Mass assignment.** `tenant_id` appears in **zero** models' `$fillable`. Grepped the entire codebase for `$request->all()` used in any `create()`/`update()` call — zero occurrences; every mutation goes through `$request->validated()`. Spot-checked FormRequests never validate a privileged field they shouldn't (`CustomerProfileRequest` has no `status` rule; `LoyaltyManagementController::adjust` only ever produces a new ledger row, never a direct balance write).
- **Client-trust of financial values.** `CheckoutRequest`/`MembershipCheckoutRequest` validate only a plan/membership-plan id — amount is always read server-side from the database row. `VerifyPaymentRequest` accepts only payment/signature identifiers, never a success flag. `BookingRequest` never accepts `total`/`subtotal`/`discount`/`tax`. Confirmed the gateway order amount and the `verifyAndFinalize()` re-verification both derive exclusively from server state.
- **Cross-tenant relationship attacks.** `BookingRequest` validates every `branch_id`/`customer_id`/`items.*.service_id`/`items.*.staff_id` with `Rule::exists(...)->where('tenant_id', $currentTenantId)` — a cross-tenant id fails validation (422), never silently succeeds. Same pattern confirmed for `CouponRequest`/`MembershipPlanRequest`'s `service_ids`/`category_ids`, and Phase 13's report filters (re-verified, unregressed).
- **IDOR via route-model-binding.** Every cross-tenant direct-ID access path checked resolves through a tenant-scoped Eloquent lookup (either the `BelongsToTenant` global scope or an explicit ownership filter for the two intentionally-non-tenant-scoped self-service domains) — a Tenant-B id from a Tenant-A session correctly 404s or is rejected at validation, never leaks data. One INFO-level style inconsistency: `VerifyPaymentRequest`'s `exists:payments,id` rule is tenant-blind (Laravel's `Rule::exists` bypasses Eloquent global scopes by design), but the controller's subsequent `Payment::query()->findOrFail()` re-applies the scope, so a cross-tenant `payment_id` still correctly 404s at the real enforcement point — not exploitable, just not the most consistent way it could have been written.
- **File uploads.** All four upload points (staff/service/category/customer photos) validate `image` + `mimes:jpg,jpeg,png,webp` + `max:5120` + `dimensions:` bounds, store via Laravel's auto-generated random filename (never the client's original filename), and never trust client-reported MIME type alone (the `image`/`mimes` rules sniff actual content).
- **SQL injection.** The only `whereRaw` outside `app/Services/Reports/*` is a single hardcoded literal (`BelongsToTenant::whereRaw('1 = 0')`, no input). Every `selectRaw` in the Reports layer uses literal column expressions with enum values passed as bound parameters, never string-concatenated. Every dynamic `sort`/`orderBy` anywhere in the app (controllers and Reports) goes through an explicit whitelist (`Rule::in`/`in_array`) before reaching the query builder.
- **XSS/output safety.** This is a JSON API + Flutter client; the only two Blade views are a static welcome page and a notification email template using escaped `{{ }}` output exclusively — no `{!! !!}` anywhere, no HTML-rendering widget anywhere in the Flutter client.
- **CORS.** Laravel's framework default (`allowed_origins: ['*']`, `supports_credentials: false`) is in effect — safe, and moot regardless: this API authenticates via Sanctum bearer tokens, never cookie/session-based credentialed CORS flows, and the Razorpay checkout runs in an external browser tab (`url_launcher`) that never calls this API directly.
- **Error responses.** Validation/authentication/authorization exceptions are explicitly mapped to clean JSON with no internals; any other exception falls through to Laravel's own default handler, which with `APP_DEBUG=false` (the real production default) returns a generic message with no stack trace, SQL, or file paths — unmodified, correct framework behavior.
- **Secrets hygiene.** `.env` is correctly untracked; `.env.example` contains only blank placeholders for every real secret; `config/services.php`/`config/billing.php`/`config/notifications.php` read every credential via `env()` with no hard-coded fallback secret value. A repo-wide scan for live-looking key patterns (`sk_live`, `rzp_live`, `AIza`, PEM headers) found nothing. No `Log::` call anywhere logs a signature, key, secret, or access token — every one logs only status codes, entity ids, and error messages.
- **Debug artifacts.** No `dd(`/`dump(`/`var_dump(`/`print_r(` anywhere in `app/`, `routes/`, `database/`. No temporary/debug routes exist.
- **Seed data.** `DatabaseSeeder` uses only `@example.test` (RFC 2606 reserved) emails and an obvious placeholder password for demo accounts — no real credentials or PII.
- **Event idempotency / listener double-registration.** The Phase 11 auto-discovery double-fire bug (documented in `TESTING.md`) is confirmed still fixed — all four notification/loyalty listener classes implement `shouldBeDiscovered(): false` and are registered exactly once in `AppServiceProvider`. `loyalty_transactions.unique(['booking_id', 'type'])` is confirmed real and does correctly make `earnForBooking()` idempotent against a duplicated `BookingCompleted` event (a second attempt hits the unique constraint and is treated as "already earned," not an error).
- **Loyalty redemption concurrency.** Confirmed race-safe: `LoyaltyAccount` is locked (`lockForUpdate()`) before the balance check, and the balance the check reads comes from that same locked row — unlike the booking/coupon cases above, there is no separate table whose plain read could be stale, because the locked row *is* the row being checked.
- **Coupon total usage_limit concurrency.** Confirmed race-safe for the identical reason — the locked `Coupon` row's own `usage_count` is both the lock target and the value checked.
- **Payment/membership IDOR.** `SubscriptionController::verify()`'s `Payment::findOrFail()` and `CustomerMembershipController::verifyCheckout()`'s customer-scoped `MembershipPayment::findOrFail()` both correctly prevent a customer/tenant from verifying or claiming another party's payment.
- **Membership activation without payment.** The only payment-free path (`MembershipManagementController::grant()`) is owner-only (`managedTenant()`) and explicitly audited (`source = owner_grant`); the customer-facing path always requires independent server-side signature re-verification, never trusting a client-reported success.
- **Subscription status tampering.** Every write to `Subscription::status` is a hardcoded enum value inside `SubscriptionService`; no endpoint accepts a client-supplied status.
- **Coupon re-validation at booking time.** Confirmed a preview/validate call's result is never trusted at actual booking creation — `reserve()` always re-runs full validation under lock, regardless of what a prior preview said.
- **Notification/push/deep-link security.** Every notification query/mutation is scoped to `$request->user()->id`; a deep link's `booking_id`/route data is used only to navigate, and the destination screen always re-fetches through the normal authorized endpoint — no sensitive push-payload data is trusted/rendered directly. `DeviceTokenRepository` has no live call site yet (FCM isn't integrated into the Flutter app), so there is currently no reachable attack surface there at all.
- **Flutter token storage.** Confirmed exclusively `flutter_secure_storage` (Android Keystore-backed, iOS Keychain) — zero `SharedPreferences` usage anywhere in `lib/`. Token is attached only via the `Authorization` header, never a URL parameter.
- **Android network security config.** No cleartext exception exists in the main/release manifest at all (secure-by-default); a cleartext exception scoped to `10.0.2.2`/`localhost` exists only under Gradle's `debug` source set, which is structurally excluded from release builds — not merely "currently set to something safe."
- **Android build config.** Release build type signs with the debug keystore (expected, unmodified Flutter-template boilerplate for a pre-release project — no real signing credentials exist to leak). Manifest requests only the `INTERNET` permission plus Flutter's own boilerplate text-selection intent query.

## Known testing limitation

Findings #1 and #2 above are genuine, verified, and fixed at the code level, but their *underlying defect* is specific to MySQL's default REPEATABLE READ transaction isolation and cannot be reproduced or regression-tested against this project's SQLite-based test suite: SQLite's own `lockForUpdate()` is a complete syntactic no-op (confirmed in `SQLiteGrammar::compileLock()`), and PHPUnit cannot issue genuinely parallel HTTP requests regardless of database engine (the same documented limitation `BOOKING_ENGINE.md` already notes for its own concurrency test). A test asserting final row counts after two *sequential* calls within one PHPUnit process cannot distinguish "locked read" from "plain read," because there is no separate transaction/snapshot boundary to make the two behave differently outside real concurrent MySQL connections. These two fixes were verified by direct code review and by tracing the exact MySQL locking/snapshot semantics involved, not by an automated test — consistent with the phase instruction to say so plainly rather than fabricate a misleading test.

## Rate limiting reference

| Limiter | Rate | Applied to |
|---|---|---|
| `auth` (pre-existing) | 5/min by email+IP | `POST /auth/login`, `POST /auth/register` |
| `api` (new) | 120/min by user id (IP for unauthenticated) | Every other authenticated route group |
| `checkout` (new, stacked on top of `api`) | 10/min by user id | `subscription/checkout(/verify)`, `subscription/renew`, `customer/membership/checkout(/verify)` |
| none (deliberate) | — | `POST /webhooks/razorpay` — gateway-authenticated via signature, not client-facing; throttling risks dropping a legitimate Razorpay retry |

## Environment / production checklist

- `APP_DEBUG` must be `false` in production (`.env.example` now says so explicitly; the framework default is already safe if unset).
- All payment/notification credentials (`PAYMENT_KEY`/`PAYMENT_SECRET`, `FCM_*`, `WHATSAPP_*`) must be supplied via environment variables in the real deployment target, never committed — confirmed `.env.example` carries only blank placeholders and no code path falls back to a hard-coded secret.
- `DB_CONNECTION=mysql` in production inherits REPEATABLE READ by default; findings #1/#2 above are fixed for this, but any *future* plain-read query added near a lock should be reviewed against the same class of staleness bug.

## iOS limitations

This audit's Flutter-side findings for iOS (network security config, the `Info.plist` fix) are **static configuration review only** — this Linux host cannot build, run, or verify iOS behavior at runtime. No claim is made that iOS was runtime security-tested in this phase.

## Not addressed in this phase (explicitly out of scope)

Production deployment, production payment/notification credentials, Play Store/App Store release, and infrastructure/monitoring — all explicitly reserved for Phase 15 per the phase brief. No CRITICAL or HIGH finding was identified that would require pulling any of that work forward.
