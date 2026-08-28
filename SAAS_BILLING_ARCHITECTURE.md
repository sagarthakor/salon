# SaaS Billing Architecture

Phase 10 makes the salon application a real SaaS product: every tenant subscribes to a database-driven plan (default: **Salon Basic, ₹500.00/month, 14-day trial** — a row in `plans`, never a hard-coded constant anywhere in the codebase, front-end or back-end), pays through an abstracted payment gateway, and is billed through real invoices with server-generated sequential numbers. Nothing here touches Phases 1–9's booking/staff/customer/salon logic; it sits alongside it as its own domain.

## Domain model

```
Plan (platform-global)
  ↓
Subscription (one row per tenant — persists across its whole lifecycle)
  ↓
Payment (one per checkout/renewal attempt) ──→ Invoice ──→ InvoiceItem (billed-price snapshot)
```

- **`plans`** — platform-global, never tenant-scoped, no `BelongsToTenant`. `amount` is `decimal(12,2)`, matching this project's existing money convention (`services.price`, `bookings.total`, …) exactly — never a float, never an integer minor-unit column, because that's what Phases 1–9 already established and there was no reason to diverge.
- **`subscriptions`** — **one row per tenant** (`unique(tenant_id)`). A renewal or a plan change updates this same row (`current_period_start`/`current_period_end` move forward) rather than creating a new one; only `status` is ever allowed to change through `SubscriptionService`, never a client-supplied value.
- **`payments`** — one row per checkout/renewal *attempt*. Carries the idempotency key, gateway order/payment references (never a secret), and its own status independent of the subscription's.
- **`invoices`** + **`invoice_items`** — `invoice_items.description`/`unit_amount` snapshot the plan's name/price *at billing time*; a later plan price change never rewrites a historical invoice (see "Plan price history" below).
- **`webhook_events`** — platform-global idempotency ledger for inbound gateway webhooks, unique on `(gateway, gateway_event_id)`.
- **`invoice_number_counters`** — a single locked row backing `InvoiceNumberGenerator`; invoice numbers are `INV-{year}-{6-digit sequence}`, reserved atomically inside the same transaction that creates the invoice — never random, never derived from the invoice's own ulid.

## Every tenant gets a trial automatically

`Tenant::booted()` calls `SubscriptionService::startTrialFor()` on `Tenant::created`, for **every** tenant however it's created — there is currently no HTTP-driven "create a tenant" endpoint at all, so a model hook is the one place that reliably covers every creation path (registration flow, a test fixture, a seeder). It picks the earliest active plan and starts a `TRIALING` subscription with `trial_ends_at = now + plan.trial_days`. The default plan is seeded **in the migration itself** (`2026_08_25_000000_create_billing_tables.php`), not only in `DatabaseSeeder`, specifically so this works in every environment including a fresh test database — Phase 1–9's feature tests create tenants directly via Eloquent, never through a seeder, and none of them needed to change for this to work: **all 74 backend tests (Phase 1–9's 55 plus Phase 10's 19) pass unmodified.**

## Subscription state machine

```
TRIALING ──(trial ends, unpaid)──► PAST_DUE ──(next scheduler tick)──► GRACE_PERIOD ──(grace elapses)──► EXPIRED
ACTIVE ──(period ends, unpaid)───► PAST_DUE ──(next scheduler tick)──► GRACE_PERIOD ──(grace elapses)──► EXPIRED
ACTIVE ──(owner cancels)────────► ACTIVE + cancel_at_period_end=true ──(period ends)──► CANCELLED
any of the above ──(verified payment)──► ACTIVE, fresh current_period_start/end
```

Only `SubscriptionService` transitions a subscription; no controller accepts a client-supplied `status`, and `EXPIRED → ACTIVE` only ever happens through the same verified-payment path as first activation (`SubscriptionService::activate()`), never a direct status write — "an explicit renewal flow," per the design brief, is the *only* path back to `ACTIVE`.

**PAST_DUE vs. GRACE_PERIOD**: both are real, distinct statuses (not merged), but a subscription typically only *observes* PAST_DUE for a few hours — the same `processLifecycle()` call that detects trial/period expiry also immediately sweeps any subscription already in PAST_DUE into GRACE_PERIOD in the same pass, since every table scan in that method runs sequentially within one invocation. PAST_DUE genuinely persists as its own visible state only when a **payment attempt explicitly fails** (a bad signature at `/subscription/checkout/verify`, or a `payment.failed` webhook) — that transition happens immediately, outside the scheduler, and the subscription then waits in PAST_DUE until the next scheduled tick promotes it to GRACE_PERIOD. Both statuses grant identical business access (see below); the distinction is purely informational (`SubscriptionStatusX.statusMessage` in Flutter shows different copy for each).

**Access policy** (`SubscriptionStatus::accessAllowed()`): `TRIALING`, `ACTIVE`, `PAST_DUE`, `GRACE_PERIOD` all grant full business-feature access. `CANCELLED` and `EXPIRED` block it. Billing/subscription endpoints (`/subscription*`) are **never** gated by this — see "Subscription access control" below.

**Cancellation**: only `cancel_at_period_end` is implemented (Phase 10's own brief marks immediate cancellation optional — "if supported, implement separately and explicitly"). Requesting cancellation just sets a flag and a timestamp; the subscription keeps full access and stays `ACTIVE` until `current_period_end`, at which point the scheduler moves it to `CANCELLED` rather than `PAST_DUE` (the owner chose to leave — no grace period is offered).

## Money handling

`decimal(12,2)` columns throughout (`plans.amount`, `payments.amount`, `invoices.subtotal/tax/total`, `invoice_items.unit_amount/amount`), matched by Eloquent `'decimal:2'` casts — the exact convention already used for `services.price` and every `bookings` money column since Phase 3/6. No floating-point arithmetic anywhere in the billing code; PHP's decimal-cast strings flow straight from the database to the JSON response (`"500.00"`) exactly as `SalonService`/`Booking` already did, and the Flutter side parses them with `num.parse(...)` exactly as `SalonService`/`Booking` already did too. Tax is present in the schema (`invoices.tax`) but always `0` in this phase — no GST/tax rule was invented; if a real tax requirement is defined later, `BillingService::openInvoiceFor()` is the one place that would compute it.

## Plan price history

`invoice_items.description`/`unit_amount` are written once, at invoice-creation time, from the plan's *current* values — never a live join to `plans`. If `Salon Basic` goes from ₹500 to ₹600, every invoice already issued still shows ₹500; only the *next* checkout/renewal uses ₹600 (proven by `test_a_later_plan_price_change_never_alters_an_already_issued_invoice`).

## Payment gateway: Razorpay, abstracted

`PaymentGatewayInterface` (`createOrder`, `verifyPaymentSignature`, `verifyWebhookSignature`, `refundPayment`) is the only contract `SubscriptionService`/`BillingService`/every controller depend on — no gateway SDK class appears outside `app/Services/Billing/Gateways/`. **Razorpay** was selected: it's the standard India-focused gateway, with native INR, order-based recurring-style billing, webhooks, HMAC-SHA256 signature verification, refunds, and a real sandbox/test mode.

`RazorpayGateway` talks to Razorpay's REST API directly over `Http` (Laravel's HTTP client) rather than adding the `razorpay/razorpay` Composer SDK — the API surface used here (create order, refund) is small, stable, and well documented, and avoiding the SDK keeps this phase from adding an unverified third-party dependency. Signature verification uses PHP's built-in `hash_hmac('sha256', ...)` and `hash_equals()` (timing-safe comparison) against Razorpay's documented algorithm — no SDK needed for that either.

`FakePaymentGateway` is the test-only stand-in (`app/Services/Billing/Gateways/FakePaymentGateway.php`), bound in `BillingApiTest::setUp()` via `$this->app->bind(PaymentGatewayInterface::class, ...)`. It never makes an HTTP call; signature verification is driven by a `validSignatures` map the test populates, so both the "verified" and "tampered" paths are exercised deterministically. **What was mocked**: the entire Razorpay REST API surface. What was *not* mocked: every backend authorization rule, the state machine, invoice/payment creation, and idempotency — all of that runs against the real database and real Laravel routing/middleware stack in every test.

## Payment flow (server-authoritative, never client-trusted)

```
Owner selects a plan (id only)
  ↓
POST /subscription/checkout {plan_id} — server loads the plan, resolves amount/currency itself
  ↓
Server creates an OPEN invoice (real snapshot), a PENDING payment, and a gateway order
  ↓
Client opens the gateway's own checkout UI
  ↓
Gateway webhook (payment.captured) OR client-driven /subscription/checkout/verify
  ↓
BillingService::verifyAndFinalize / recordPaymentSuccess — signature re-verified server-side
  ↓
Payment → PAID, Invoice → PAID, Subscription → ACTIVE (SubscriptionService::activate)
  ↓
Flutter re-fetches GET /subscription and shows success only once the server says `status: active`
```

**The client never sends an amount.** `CheckoutRequest`/`RenewRequest` validate only `plan_id`; the controller loads the `Plan` row and passes `$plan->amount`/`$plan->currency` to `BillingService` and the gateway — proven by `test_checkout_always_uses_the_server_side_plan_price_and_ignores_a_client_supplied_amount`, which sends `amount: 1` in the request body and asserts the created order is still ₹500.

**The client's claim of success is never trusted.** `SubscriptionController::verify()` calls `PaymentGatewayInterface::verifyPaymentSignature()` again, server-side, against the stored `gateway_order_id` before doing anything — an invalid signature marks the payment `FAILED` and moves the subscription to `PAST_DUE`, proven by `test_verify_with_an_invalid_signature_fails_the_payment_and_moves_the_subscription_to_past_due`.

### Flutter payment flow — why it's browser-based, not a native SDK

Phase 10's brief calls for opening "the gateway's official payment UI/SDK." A native SDK (`razorpay_flutter`) was added to `pubspec.yaml` and tested first; **`flutter build apk --debug` failed** — the package's own `android/build.gradle` declares a legacy Gradle/Kotlin buildscript toolchain (Android Gradle Plugin 7.1.3, `dokka` 1.4.32, etc.) that requires downloading Maven artifacts this sandboxed environment has no network access for. Since this project's hard, consistently-honored rule since Phase 7 is "never claim a build succeeded without actually running it, and never leave the build broken," the native SDK was reverted. `url_launcher` (a modern, actively-maintained, dependency-light plugin) was verified to build cleanly instead, and the checkout screen (`PaymentCheckoutScreen`) opens Razorpay's hosted checkout page in the device's browser via `openGatewayCheckout()` (`lib/features/owner/billing/presentation/gateway_checkout_launcher.dart`) — a single, clearly isolated function that is exactly where a native SDK would be substituted if this were built in an environment with full Maven access.

Because a browser redirect can't hand `razorpay_payment_id`/`razorpay_signature` back into the Flutter app without deep-linking (out of scope this phase), the checkout screen never calls the client-driven `verify` endpoint after opening the browser — the app instead re-fetches `GET /subscription` (on the user tapping "I've completed the payment," and automatically on app-resume via `WidgetsBindingObserver`) and trusts only what the server's webhook has already confirmed. This is arguably the *more* correct mobile+webhook pattern regardless of the build constraint: the webhook is authoritative and fires independently of whatever the client does. The `verify` endpoint remains fully implemented and is what the backend's own test suite exercises for the SDK-driven case (`checkout/verify` with a client-supplied signature), so it's ready if a native SDK integration is added in an environment that can build it.

## Idempotency

**Webhooks**: every inbound event is recorded in `webhook_events` (unique `(gateway, gateway_event_id)`) *inside a transaction with a row lock*, before it's processed. A duplicate delivery of the same event id is detected and short-circuited to a no-op — proven by `test_webhook_with_a_valid_signature_activates_the_subscription_and_a_duplicate_delivery_is_a_no_op` (asserts exactly one `webhook_events` row and one `payments` row after two identical deliveries).

**Payments**: a client-side-generated (or server-generated, if omitted, and echoed back in the checkout response for the client to retry with) `Idempotency-Key` header. `BillingService::initiateCheckout()` looks up an existing `PENDING`/`PAID` payment with that key before creating anything; a retried checkout call returns the *same* payment and never creates a second gateway order — proven by `test_checkout_idempotency_key_returns_the_same_payment_instead_of_creating_a_second_order`. `payments.idempotency_key` is a unique-constrained column as a second line of defense.

**Payment finalization itself** is idempotent regardless of key handling: `BillingService::verifyAndFinalize()`/`recordPaymentSuccess()` both check `status === PAID` first and return unchanged if so — the webhook and the client-driven verify call race safely, whichever arrives first wins and the second is a no-op.

## Subscription access control

`EnsureActiveSubscription` (alias `subscription.active`) is appended to the **existing** `['auth:sanctum', 'tenant.context']` group that already wraps salon/branch/service/staff/customer/booking/dashboard routes — every one of those now additionally requires the tenant's subscription to be in an access-allowed state (`TRIALING`/`ACTIVE`/`PAST_DUE`/`GRACE_PERIOD`), returning `402 Payment Required` with a clear message otherwise. The **billing routes themselves** (`/subscription*`) are registered in their own separate group with `['auth:sanctum', 'tenant.context']` only — no `subscription.active` — so an owner can always view/renew/cancel regardless of status, exactly as required ("Do NOT lock out critical account/billing functionality"). Proven by `test_expired_subscription_blocks_business_routes_but_never_billing_routes`.

This required no change to `AuthController@login` or anywhere near authentication — the gate lives entirely in middleware, applied only to the business-route group, exactly as instructed ("avoid making authentication dependent on payment gateway availability").

**Customer/staff impact**: customers hold no tenant membership at all (a Phase 5 design decision), so they can never reach a `tenant.context` route regardless of subscription status — nothing to enforce there. Staff share the same `subscription.active` gate as the owner on every business route, since it's the *tenant's* standing being checked, not the caller's role; there is no staff-specific carve-out. This is enforced entirely server-side — the Flutter Staff/Customer apps do not independently duplicate this check, matching "do not rely only on Flutter to enforce subscription restrictions."

## Scheduler

`php artisan subscriptions:process-lifecycle` (registered `Schedule::command(...)->daily()` in `routes/console.php`) is the only place subscriptions transition due to the passage of time — it never initiates a charge; payment collection always goes through the gateway-driven checkout flow described above, never blindly from the scheduler. Running it requires the standard Laravel cron entry in production: `* * * * * php artisan schedule:run >> /dev/null 2>&1`. `SubscriptionService::processLifecycle()` is directly unit-testable (and tested) without waiting real time — tests set `trial_ends_at`/`current_period_end`/`grace_ends_at` to past timestamps and call it directly.

It queries `withoutGlobalScope('tenant')` throughout — a console command has no `TenantContext`, and needs to operate across every tenant platform-wide; this is the same established pattern `CustomerBookingController` already uses for a customer's cross-tenant own-bookings list, not a new one.

## Events

`SubscriptionCreated`, `SubscriptionActivated`, `PaymentSucceeded`, `PaymentFailed`, `SubscriptionCancelled` (fired when a subscription actually reaches `CANCELLED`, not when cancellation is merely requested), `SubscriptionExpired`, `InvoicePaid` — all real Laravel events, dispatched at the right points in `SubscriptionService`/`BillingService`, with no listeners yet (notifications are explicitly out of scope this phase). They exist now so a future notifications phase has real hook points rather than needing to retrofit them.

## Authorization

- **Customer**: no tenant membership, cannot reach any `/subscription*` route — `tenant.context` rejects them before any billing controller runs.
- **Staff**: `viewableTenant()` on every read endpoint (`GET /subscription`, `/subscription/payments`, `/subscription/invoices`, `/subscription/plans`) — staff can see billing status. `managedTenant()` on every mutating endpoint (`checkout`, `renew`, `cancel`) — staff cannot manage the subscription. Proven by `test_staff_can_view_billing_but_cannot_checkout_renew_or_cancel`.
- **Owner**: `managedTenant()` passes for their own tenant only — there is no client-supplied tenant id anywhere in the billing API surface (everything derives from `TenantContext`, resolved from the authenticated session's `X-Tenant-Slug`/membership), so there is no "pass another tenant's id" attack surface to even test against directly. What *is* tested is that a payment/invoice/subscription can never be read or verified across tenants by direct id (`test_a_tenant_cannot_verify_or_list_another_tenants_payments_or_invoices`) — `Payment`/`Invoice`/`Subscription` all use `BelongsToTenant`, so a cross-tenant `findOrFail()` 404s exactly like every other Phase 1–9 resource.
- **Platform admin** (`super_admin`, the existing `manage-platform` Gate from `AppServiceProvider`): can create/update/activate/deactivate plans under `/platform/plans`. No Platform Admin Flutter app was built this phase (explicitly out of scope) — these are backend-only management APIs.

## APIs

See `API_DOCUMENTATION.md` and `MOBILE_API_INTEGRATION.md` for the full endpoint list. Route paths deviate from the brief's suggested list in exactly one place: `POST /subscription/checkout/verify` was added (not in the original list) because `checkout` only *creates* an order — a second endpoint is genuinely needed for the client-driven verification step, and extending the `checkout` path was more consistent with this project's existing route-naming conventions than inventing a new top-level path.

## Documentation / testing summary

Backend: 19 new tests in `tests/Feature/BillingApiTest.php` (plan management, pricing/tampering, checkout+verify happy path, invalid signature, idempotency, webhooks including duplicate delivery and `payment.failed`, historical invoice pricing, lifecycle transitions, cancel-at-period-end, access-control gating, authorization, tenant isolation) — 74 backend tests total, zero regressions. Flutter: 29 new tests (model parsing, repository behavior/amount-tampering, all six subscription UI states, plan selection, the payment-checkout screen's wait-for-confirmation behavior, payment/invoice history) — 158 Flutter tests total, `flutter analyze` clean, `flutter build apk --debug` still succeeds.
