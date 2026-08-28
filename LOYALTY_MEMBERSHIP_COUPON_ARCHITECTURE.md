# Coupons + Membership + Loyalty Architecture (Phase 12)

Phase 12 gives salons three retention tools — coupons, paid customer memberships, and a loyalty points program — all converging on one server-side pricing engine that `BookingService::create()` already calls. Nothing here duplicates Phases 1–11's architecture: it extends the same tenant model, the same event/notification system, and (for membership purchase) the same payment gateway abstraction.

## Domain model

```
Tenant
  ├─ Coupons ──────────────┬─ coupon_services / coupon_categories (restrictions)
  │                        └─ coupon_usages (immutable audit ledger)
  ├─ Membership Plans ─────┬─ membership_plan_services / membership_plan_categories
  │                        └─ customer_memberships (one row per purchase/grant/renewal)
  │                              └─ membership_payments (its own payment ledger — see below)
  └─ Customers
        └─ Loyalty Account (one per customer per tenant)
              └─ Loyalty Transactions (immutable ledger: earn/redeem/adjust/expire/reversal)

Booking
  ├─ coupon_id / coupon_code / coupon_discount        (snapshot, never changes after creation)
  ├─ customer_membership_id / membership_discount     (snapshot)
  └─ loyalty_points_redeemed / loyalty_discount / loyalty_points_earned (snapshot)
```

## The money rule

Every discount is calculated by `BookingPricingService`, called from inside `BookingService::create()`'s existing transaction — never in a controller, never trusting a client-submitted amount. A client may send a `coupon_code` and/or `loyalty_points_to_redeem`; it can never send a discount amount, and a client-supplied `membership_id` doesn't exist as a concept at all — membership benefit is resolved automatically from the customer's own active membership, never selected by the client.

## Pricing breakdown & discount stacking

```
Subtotal
 − (Coupon discount   OR   Membership benefit)   ← at most ONE of these two
 − Loyalty discount                              ← may additionally apply
 + Tax (always 0 in this phase, same as Phases 6/10)
 = Total
```

**Stacking rule**: an explicitly-supplied, currently-valid coupon always wins over an automatic membership benefit — never both. If no coupon is supplied (or the supplied one turns out invalid), the customer's active membership benefit (if any) applies automatically. Loyalty point redemption is independent and may stack on top of whichever primary discount was applied, computed against the *post-primary-discount* amount and capped by `LOYALTY_MAX_REDEMPTION_PERCENT` of the original subtotal.

`BookingPricingService` has two entry points:
- **`preview()`** — pure, never throws, never mutates anything. Backs the read-only `POST /bookings/price-preview` (owner) and `POST /customer/bookings/price-preview` (customer) endpoints. A coupon that fails validation here is reported as a `messages` string in the response, not an error — the endpoint always returns 200.
- **`reserve()`** — re-validates everything under a row lock and actually consumes a coupon usage slot / loyalty balance. Only ever called from inside `BookingService::create()`'s transaction, after the `Booking` row already exists (see "Transaction safety" below). If an explicitly-supplied coupon is no longer valid at this point (a race, or it expired between preview and confirm), this throws `BookingUnavailableException` — the whole transaction, including the just-inserted booking, rolls back and the client gets a 409. A loyalty redemption that can't be fully honored is **not** an error — the customer simply gets however many points are still actually redeemable (see "Loyalty redemption" below); this asymmetry (coupon = strict, loyalty = lenient) is deliberate.

## Coupons

`coupons` — tenant-owned, `code` always normalized (`Coupon::normalizeCode()`: uppercased + trimmed) so `welcome10`/`WELCOME10`/` Welcome10 ` are one logical coupon, enforced by a `unique(tenant_id, code)` index on the normalized value. Restrictions to specific services/categories live in `coupon_services`/`coupon_categories` pivot tables (never a comma-separated ID column); a coupon with no rows in either applies tenant-wide. When restricted, the discount is computed only against the *qualifying* subset of the booking's services — a booking with both a covered and an uncovered service still gets a valid, partial discount.

`CouponService::validate()` checks (in order): active, `starts_at`/`expires_at`, total `usage_limit`, `usage_limit_per_customer` (queried from `coupon_usages`, not a client-supplied count), `first_booking_only` (a customer's real prior-booking history, excluding the booking currently being created — see the gotcha below), qualifying-service restriction, `minimum_booking_amount`, and the computed discount capped by `maximum_discount_amount`.

**A real bug this caught**: `BookingService::create()` inserts the `Booking` row *before* calling `BookingPricingService::reserve()` (see "Transaction safety"), so by the time coupon validation runs, the booking being created already exists in the database — meaning a naive "does this customer have any prior bookings" check would count the booking against itself, making `first_booking_only` reject a customer's actual first booking. `CouponService::validate()`/`reserve()` take an `$excludeBookingId` specifically to exclude the in-progress booking from that check.

**Coupon usage tracking**: `coupon_usages` is an append-only audit ledger — one row per successful application, `unique(coupon_id, booking_id)`. `coupons.usage_count` is a denormalized counter kept in lockstep inside the same locked transaction. Neither is ever decremented/deleted on cancellation — the coupon really was used.

**Race safety**: `CouponService::reserve()` re-fetches the coupon `lockForUpdate()` and re-runs full validation before incrementing `usage_count`/inserting the usage row — the same lock-and-revalidate pattern `BookingService` already uses for staff/slot conflicts (see `BOOKING_ENGINE.md`). `test_coupon_usage_limit_is_race_safe_...` proves the mechanism a genuine concurrent request would hit (PHPUnit can't exercise true parallel HTTP requests — same documented limitation as the booking engine's own concurrency test).

## Membership

`membership_plans` — tenant-owned, database-driven price/duration/benefit (never hard-coded), with the same service/category-restriction pivot pattern as coupons and the same `discount_type`/`discount_value`/`maximum_discount_amount` shape (a `CouponDiscountType` enum shared between both — a membership benefit and a coupon discount are structurally the same "percentage or fixed amount, capped" calculation, so nothing is duplicated). Only percentage/fixed-amount benefits are implemented in this phase — "free services" or "priority booking" benefits were deliberately not attempted (see Phase 12 spec §21: "implement only benefits that can be represented safely by the existing architecture"; a free-service benefit would need its own per-period redemption-tracking mechanism this phase doesn't build).

`customer_memberships` — **one new row per purchase, renewal, or owner grant** — never mutated/overwritten. `MembershipService::activate()` cancels any other currently-ACTIVE membership for that customer first (at most one active membership at a time), then inserts a fresh row; a customer's full membership history stays intact and readable regardless of what they have now. A membership's `isCurrentlyActive()` check is `status === ACTIVE && expires_at->isFuture()` — evaluated fresh on every pricing calculation, so an expired-but-not-yet-swept membership never grants a benefit even before the daily `memberships:expire` scheduler command runs.

### Subscription vs. Membership — a deliberate, hard separation

Phase 10's **SaaS Subscription** (`subscriptions`/`payments`/`SubscriptionService`/`BillingService`) is the salon owner paying the *platform* ₹500/month. Phase 12's **Customer Membership** (`customer_memberships`/`membership_payments`/`MembershipService`) is a salon's *customer* paying the *salon*. These are completely different domains and were kept structurally separate on purpose:

- Separate tables (`membership_payments`, not `payments`) — Phase 10's `payments.subscription_id` is a **required** foreign key into `subscriptions`; there is no way to record a membership purchase in that table without either making that column nullable (an invasive change to a working Phase 10 migration) or fabricating a fake subscription row. Neither is acceptable.
- Separate service classes (`MembershipService`, never touching `SubscriptionService`/`BillingService`).
- **The same `PaymentGatewayInterface`** in both cases — never a second gateway, never a new SDK. `MembershipService::initiateCheckout()`/`verifyAndFinalize()` mirror `BillingService`'s checkout/verify shape exactly (server-resolved price only, re-verified gateway signature, idempotency key), just against the membership domain's own tables.
- **The same Razorpay webhook endpoint** (`POST /webhooks/razorpay`) now serves both domains: `PaymentWebhookController::process()` looks up the incoming `gateway_order_id` against `payments` first, then falls back to `membership_payments` if no subscription payment matches, converging on `MembershipService::recordSuccess()`/`recordFailure()` — the same signature-already-verified, idempotent, no-second-gateway pattern Phase 10 established. This was added deliberately (not skipped as "unnecessary new payment functionality") because without it, a customer's browser-based checkout (see "Flutter membership purchase" below) would have no way to ever get confirmed at all in this environment.

## Loyalty

**Settings, not a new table**: loyalty configuration (`LOYALTY_ENABLED`, `LOYALTY_EARN_RATE_AMOUNT`, `LOYALTY_MIN_BOOKING_AMOUNT_FOR_EARNING`, `LOYALTY_POINTS_EXPIRY_DAYS`, `LOYALTY_REDEMPTION_VALUE`, `LOYALTY_MAX_REDEMPTION_PERCENT`) are new `SalonSettingKey` cases read through a new `LoyaltySettings` helper (mirroring the existing `BookingSettings`) — reusing the exact same `salon_settings` key-value store `BookingSettings` already reads from, not a dedicated `loyalty_settings` table. This meant the existing `GET/PUT /salon/settings` endpoint needed **zero new code** to support loyalty configuration.

`loyalty_accounts` — one row per (tenant, customer), `balance`/`lifetime_earned`/`lifetime_redeemed` denormalized for cheap reads but never mutated except alongside a matching ledger row.

`loyalty_transactions` — an immutable ledger (`EARN`/`REDEEM`/`ADJUSTMENT`/`EXPIRE`/`REVERSAL`). `points` is always the *signed delta actually applied* to the balance. Never deleted, never edited — a correction is always a new `ADJUSTMENT` row with a required reason.

**Earning timing**: points are only ever earned when a booking reaches `COMPLETED` — `AwardLoyaltyPointsOnBookingCompleted` listens to the existing `BookingCompleted` event (never a new one; see "Notifications" below), computed on `booking.total` (what the customer actually paid, not the pre-discount subtotal). Cancelled/no-show bookings never earn anything, since they never reach `COMPLETED`.

**Idempotency**: `unique(booking_id, type)` on `loyalty_transactions` guarantees at most one `EARN` row per booking. This works specifically *because* NULL is never considered equal to NULL in a unique index (SQLite, MySQL, and Postgres all agree on this) — `ADJUSTMENT`/`EXPIRE` rows (which have no associated booking) have `booking_id = NULL` and are completely unconstrained by this index, while a `REDEEM`/`EARN` row tied to a real booking is deduplicated exactly once. `LoyaltyService::earnForBooking()` checks for an existing row first (fast path) and additionally catches the underlying unique-constraint `QueryException` as the final race-safety net — a concurrent/duplicated event delivery is a no-op, not an error.

**Redemption**: `LoyaltyService::redeem()` locks the account row, computes `min(requested, available balance, subtotal × max_redemption_percent ÷ redemption_value)`, deducts, and records a `REDEEM` transaction against the booking. A customer requesting more points than allowed is never an error — they simply get however many points the server determines are actually redeemable, and the response reports the real number applied (never trusting "500 points = ₹500" just because the client said so).

**Expiration**: `loyalty:expire-points` (scheduled daily) zeroes the balance of any account whose most recent ledger activity is older than the tenant's `LOYALTY_POINTS_EXPIRY_DAYS`, producing an `EXPIRE` transaction — never a silent `DELETE`/balance overwrite. A tenant with `LOYALTY_POINTS_EXPIRY_DAYS = 0` (the default) never expires points at all.

## Booking snapshot

Once created, a booking's discount fields never change even if the coupon is later edited/deactivated or the membership plan's benefit changes — `coupon_code`/`coupon_discount`/`membership_discount`/`loyalty_points_redeemed`/`loyalty_discount` are written once, from the server-computed `PricingBreakdown`, at creation time. The pre-existing `bookings.discount` column (which Phase 6's Flutter `Booking` model already parses) is kept as the simple combined total of the three — full backward compatibility for every booking created before this phase, and for any request that sends no `coupon_code`/`loyalty_points_to_redeem` at all.

## Transaction safety

`BookingService::create()`'s existing single DB transaction now also covers pricing:

```
1. Resolve services, compute subtotal            (existing, unchanged)
2. Create the Booking row + BookingItems         (existing, unchanged — with discount fields = 0 initially)
3. BookingPricingService::reserve()               (NEW — locks coupon/loyalty account, re-validates,
                                                    records CouponUsage/LoyaltyTransaction referencing
                                                    the now-existing booking_id)
4. Update the Booking row with the final numbers  (NEW)
5. BookingStatusHistory + event(BookingCreated)   (existing, unchanged)
```

Step 2 must happen *before* step 3: `coupon_usages`/`loyalty_transactions` both have a foreign key to `bookings.id`, and unlike SQLite's relaxed default, a real FK-enforcing database checks constraints per-statement rather than deferring to commit — inserting a child row referencing a booking that doesn't exist yet would fail immediately even inside the same uncommitted transaction. If step 3 throws (an explicitly-requested coupon lost a race or expired), the whole transaction — including the Booking/BookingItems already inserted in step 2 — rolls back together. No orphaned coupon usage, no deducted-but-unbooked loyalty points, no half-created booking.

## Authorization & tenant isolation

Coupons, membership plans, and loyalty adjustments are **owner/super-admin only** (`TenantManagementController::managedTenant()` on every write) — staff can view booking pricing (it's just fields on `BookingResource`, which staff already has full access to) but cannot manage any of these three configuration surfaces. Customers can only ever act on their own coupon application (server-resolved, not client-chosen), their own membership, and their own loyalty account/redemption — never another customer's.

Tenant isolation is structural, not a rule to remember: every new model (`Coupon`, `MembershipPlan`, `CustomerMembership`, `MembershipPayment`, `LoyaltyAccount`, `LoyaltyTransaction`, `CouponUsage`) uses `BelongsToTenant` exactly like every other tenant-owned model since Phase 1, so a direct-ID request for another tenant's row 404s automatically via the same global scope — proven in `test_tenant_a_cannot_access_tenant_bs_coupons_memberships_or_loyalty_by_direct_id`.

## Notifications (reused, not rebuilt)

Two new domain events — `MembershipActivated`, `MembershipExpired` — dispatched from `MembershipService`, and a new `NotificationEventType::LOYALTY_POINTS_EARNED` fired directly from `AwardLoyaltyPointsOnBookingCompleted`. All three flow through Phase 11's existing `NotificationDispatcher`/`NotificationMessageBuilder`/channel infrastructure exactly like every Phase 11/10 notification — no new channel, provider, or queue code. `CouponApplied`/`LoyaltyPointsRedeemed`/`LoyaltyPointsAdjusted` were deliberately **not** turned into separate dispatched events/notifications — a coupon application or loyalty redemption is already visible in the booking-created/confirmed notification and the loyalty ledger itself; a second notification for the same booking action would just be noise (see Phase 11's own "channel fallback"/anti-spam principle, which this phase follows rather than re-litigates).

## APIs

See `API_DOCUMENTATION.md` for the full list. Summary: `/coupons*`, `/membership-plans*`, `/memberships*`, `/loyalty/customers*` (owner/super-admin, tenant-scoped); `/customer/membership*`, `/customer/loyalty*`, `/branches/{branch}/membership-plans` (customer-facing, same X-Tenant-Slug convention as the rest of the customer surface); `/bookings/price-preview` and `/customer/bookings/price-preview` (read-only pricing preview, both owner and customer booking-creation paths).

## Flutter

The existing single Flutter codebase gained: an "Apply coupon" field + loyalty-points field + a live pricing-breakdown card in the customer booking summary screen (calls the price-preview endpoint; the actual booking creation still recalculates everything server-side); a customer Membership screen (current status + browsable/purchasable plans) and Loyalty screen (balance + ledger); owner screens for Coupons, Membership Plans, Customer Memberships (with a grant flow), and Loyalty (search + manual adjustment). Every price/discount value displayed comes straight from a backend response — no client-side discount math anywhere (see Phase 12 spec §84).

**Membership purchase in Flutter** reuses Phase 10's browser-based hosted-checkout pattern exactly (`MembershipCheckoutScreen`/`membership_gateway_checkout_launcher.dart` mirror `PaymentCheckoutScreen`/`gateway_checkout_launcher.dart`) for the same reason Phase 10 chose it: a native Razorpay SDK could not be verified to build in this sandboxed environment. Because a browser redirect can't hand `gateway_payment_id`/`signature` back into the app, the checkout screen never calls the client-driven verify endpoint itself — it polls `GET /customer/membership`, trusting only what the server-side webhook has already confirmed (see "Subscription vs Membership" above for why that webhook path exists at all in this phase).

## What Phase 12 does not attempt

- Membership benefits limited to percentage/fixed-amount discounts — no "free service" or "priority booking" benefit types (see "Membership" above for why).
- No membership-expiry-reminder notification (Phase 12 spec §63 explicitly frames this as optional; adding it would mean building a second idempotent reminder-scheduling mechanism alongside Phase 11's booking-reminder one for comparatively little value this phase, so it was left out — booking reminders' infrastructure was not duplicated for it).
- No renewal "grace"/proration logic — purchasing a new membership while one is already active cancels the old one and starts the new one from now, rather than appending remaining days. Documented as a deliberate simplification, not an oversight.
