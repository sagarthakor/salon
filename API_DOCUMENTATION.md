# API Documentation

Base path: `/api/v1`. Responses use `success`, `message`, and `data` on success; errors use `success`, `message`, and `errors`.

- `POST /auth/register` — customer registration; role and tenant input are ignored.
- `POST /auth/register-owner` — self-service salon-owner registration. Creates a `User` (role always `salon_owner`, never client-supplied), a new `Tenant`, and the caller's owner membership on it, all in one transaction; the tenant's trial subscription starts automatically via the existing `Tenant::booted()` hook — no separate step. See "Owner onboarding" below for the full request/response shape and semantics.
- `POST /auth/login` — email/password token login.
- `POST /auth/logout` — revoke the current Sanctum token.
- `GET /auth/me` — authenticated user and tenant memberships.

Login/register endpoints (including `register-owner`) are rate-limited to five requests per minute by email and IP. Use `Authorization: Bearer <token>` for protected endpoints.

### Owner onboarding — `POST /auth/register-owner`

The one HTTP-reachable way a `Tenant` is ever created (every other tenant-creation path — seeders, test fixtures — is outside the API). Public, unauthenticated, same `throttle:auth` limiter as `/auth/register`/`/auth/login`.

**Request:**

```json
{
  "name": "Asha Owner",
  "email": "asha-owner@example.test",
  "password": "SecurePassword1!",
  "password_confirmation": "SecurePassword1!",
  "salon_name": "Asha Hair Studio",
  "slug": "asha-hair-studio"
}
```

`name`, `email`, `password`/`password_confirmation` (min 12 characters), and `salon_name` are required. `slug` is optional — when omitted, one is derived from `salon_name` (via `Str::slug()`) and, if that value is already taken, a numeric suffix (`-2`, `-3`, ...) is appended until a free one is found; the database's own `tenants.slug` unique constraint is still the authoritative guard against a same-instant collision, not just this pre-check. An explicitly-supplied `slug` that's already taken is rejected with a normal `422` validation error instead — it is never silently renamed. No `role`, `tenant_id`, or membership field is ever accepted from the request; the server always assigns `salon_owner` and always creates a brand-new tenant.

**Response (`201`):**

```json
{
  "success": true,
  "message": "Salon owner registration successful.",
  "data": {
    "user": { "id": 42, "name": "Asha Owner", "email": "asha-owner@example.test", "role": "salon_owner" },
    "token": "42|abcdef0123456789...",
    "tenant_slug": "asha-hair-studio"
  }
}
```

Same envelope shape as `/auth/register`'s response, plus `tenant_slug` — the one new field, since this is the only registration path that creates a tenant. The client sets this as `X-Tenant-Slug` on subsequent requests (see `ApiClient`/`ResolveTenantContext`); in practice a brand-new owner has exactly one tenant membership, so the header isn't strictly required for the very first request (`ResolveTenantContext` defaults to a user's sole membership when no header is sent), but sending it is always correct and never assumed away.

After this call, the owner has full access to every existing owner endpoint (`/salon`, `/branches*`, `/services*`, `/staff*`, `/customers*`, `/bookings*`, `/reports/*`, `/coupons*`, `/membership-plans*`, `/loyalty/*`, `/subscription*`) scoped to their new tenant only — no new endpoints were added for salon setup itself, since they already existed.

**Setup-completion gap (fixed):** a brand-new owner has a `Tenant` + trial but no `Salon` yet — `GET /salon` correctly `404`s for this (a plain "this resource doesn't exist" response; the Flutter Salon Profile screen treats that 404 as "show the create form", never as an error to display). `POST /branches`, however, used to call `Salon::query()->firstOrFail()` directly to derive `salon_id`, which surfaced Laravel's raw `ModelNotFoundException` shape (`{"message": "No query results for model [App\\Models\\Salon]."}` , off-brand envelope, internal class name, effectively an unhandled-exception response) instead of a clean business error. `BranchController::store()` (via `TenantManagementController::requireSalon()`) now returns a normal `422`:

```json
{
  "success": false,
  "message": "Please set up your salon profile before adding a branch.",
  "errors": { "salon": ["Salon profile not found."] }
}
```

`requireSalon()` uses `Salon::query()->first()` — already tenant-scoped via the `BelongsToTenant` global scope, so it can never select another tenant's salon — never a global "first salon in the table" lookup. `POST /service-categories` and `POST /services` needed no equivalent fix: both already require a tenant-scoped `branch_id` (Laravel's `Rule::exists(...)->where('tenant_id', ...)`), and a salon-less tenant has zero branches, so those already fail with an ordinary `422` validation error, never a 500. See `OWNER_APP_ARCHITECTURE.md`, "Owner onboarding: salon setup", for the matching Flutter-side UX.

Salon management endpoints require `auth:sanctum` and `tenant.context`; only a tenant owner or super admin may use them.

- `GET|POST|PUT|PATCH /salon`
- `GET|PUT|PATCH /salon/settings`
- `GET|POST /branches`, `GET|PUT|PATCH|DELETE /branches/{branch}`
- `GET|PUT /branches/{branch}/working-hours`
- `GET|POST /branches/{branch}/holidays`
- `PUT|PATCH|DELETE /branches/{branch}/holidays/{holiday}`

`X-Tenant-Slug` may select an active tenant only after server-side membership verification. Branch and holiday IDs are never sufficient authorization.

Service management APIs: `GET|POST /service-categories`, `GET|PUT|PATCH|DELETE /service-categories/{service_category}`, `GET|POST /services`, and `GET|PUT|PATCH|DELETE /services/{service}`. Service lists paginate and accept `branch_id`, `category_id`, `gender`, `status`, `sort`, and `per_page` (maximum 100).

Staff management APIs (owner/super admin for all writes; a staff member may `GET` their own profile, services, working hours, and leave):

- `GET|POST /staff`, `GET|PUT|PATCH|DELETE /staff/{staff}`. Staff lists paginate and accept `status`, `branch_id`, `sort` (`name`, `joining_date`, `newest`), and `per_page` (maximum 100). Create/update accept `branch_ids` (array) to assign branches.
- `GET|PUT /staff/{staff}/services` — assign the full set of services a staff member can perform (`service_ids`); each service must belong to the tenant and, if the staff member has assigned branches, to one of them.
- `GET /staff/me` — added in Phase 9; resolves the authenticated user's own staff profile within the current tenant (`404` if none is linked). Any tenant member may call it, but it only ever returns the caller's own record — never a client-supplied id. Registered ahead of `GET /staff/{staff}` so `me` is never captured by the wildcard route.
- `GET|PUT /staff/{staff}/working-hours` — replace the full weekly schedule (`hours`, one entry per `day_of_week` with `is_working`, `start_time`, `end_time`).
- `GET|POST /staff/{staff}/breaks`, `PUT|PATCH|DELETE /staff/{staff}/breaks/{break}` — per-day breaks; must fall within that day's working hours and not overlap another break.
- `GET|POST /staff/{staff}/leaves`, `PUT|PATCH|DELETE /staff/{staff}/leaves/{leave}` — date-range leave with an optional reason; overlapping non-rejected leave for the same staff member is rejected.

Customer management APIs (owner/super admin for writes and notes/summary; staff get read-only list/view):

- `GET|POST /customers`, `GET|PUT|PATCH|DELETE /customers/{customer}`. Customer lists paginate and accept `status`, `gender`, `search` (matches name, email, phone, or normalized phone), `sort` (`name`, `newest`), and `per_page` (maximum 100). Create/update normalize `phone`+`country_code` and reject a duplicate phone within the same tenant.
- `GET /customers/{customer}/summary` — owner/super-admin only; returns the customer profile plus a `summary` object (`total_visits`, `completed_appointments`, `cancelled_appointments`, `no_show_count`, `total_spent`, `last_visit_at`, `upcoming_appointment`) derived from the customer's real `bookings` history (fixed in Phase 8 — previously a placeholder returning zeros; see `OWNER_APP_ARCHITECTURE.md`).
- `GET|POST /customers/{customer}/notes`, `PUT|PATCH|DELETE /customers/{customer}/notes/{note}` — owner/super-admin only internal notes; never exposed to staff or customer endpoints.

Customer self-service (any authenticated user; not gated by `tenant.context` since a customer holds no tenant membership):

- `GET|PUT|PATCH /api/v1/customer/profile` — resolves the caller's own `customer_profiles` row by `user_id`. If the user has profiles in more than one tenant, pass `X-Tenant-Slug` to select one; omit it when there is exactly one.
- `GET /api/v1/customer/salons` — added in Phase 7 for the mobile app; lists the tenants (salon + active branches) the caller already has a `customer_profiles` relationship with. Not a public salon directory — see `MOBILE_API_INTEGRATION.md`.

Availability and branch service catalog (`auth:sanctum` only — no `tenant.context`, no `X-Tenant-Slug`; these serve owner/staff and customers alike):

- `GET /branches/{branch}/availability?date=Y-m-d&service_ids[]=...&staff_id=...` (`staff_id` optional). Returns `{date, duration_minutes, buffer_minutes, slots: [{start_time, end_time, staff_ids}], staff: [{id, name}]}` (`staff` added in Phase 7, additive). `date` is rejected with `422` if it's in the past or beyond the salon's configured maximum advance-booking window.
- `GET /branches/{branch}/services` — added in Phase 7 for the mobile app; returns `{categories: [...], services: [...]}`, active only, for the branch (see `MOBILE_API_INTEGRATION.md` — without this a customer has no way to discover `service_ids` for the availability call above).

Booking management APIs (owner/super admin and staff both get full operational access — see `BOOKING_ENGINE.md` for why staff are broader here than in Phases 4–5):

- `GET|POST /bookings`, `GET|PATCH /bookings/{booking}`. Lists paginate and accept `date`, `status`, `branch_id`, `customer_id`, `staff_id`, and `per_page` (maximum 100). `POST` accepts `branch_id`, `customer_id`, `date`, `start_time`, `items[]` (`service_id`, `staff_id` nullable for automatic assignment), and `notes`. `PATCH` accepts `status` (`checked_in|in_service|completed|no_show`) and/or `notes`.
- `POST /bookings/{booking}/confirm` — `pending` → `confirmed`.
- `POST /bookings/{booking}/cancel` (`reason` optional) — owner/staff cancellation always bypasses the cancellation-window setting.
- `POST /bookings/{booking}/reschedule` (`date`, `start_time`) — fully revalidates against the new date/time.
- `POST /bookings/price-preview` (Phase 12) — read-only; never creates a booking. Body: `branch_id`, `customer_id`, `service_ids[]`, `coupon_code`/`loyalty_points_to_redeem` (both optional). Returns the full pricing breakdown (`subtotal`, `coupon_discount`, `membership_discount`, `loyalty_points_redeemed`, `loyalty_discount`, `discount`, `tax`, `total`, `messages[]`). The actual `POST /bookings` recalculates everything again server-side — this response is never trusted as-is.

Customer booking self-service (`auth:sanctum` only, own bookings only):

- `GET|POST /customer/bookings`, `GET /customer/bookings/{booking}`, `POST /customer/bookings/{booking}/cancel`, `POST /customer/bookings/{booking}/reschedule`. `POST` accepts the same `branch_id`/`date`/`start_time`/`items[]`/`notes` shape as the owner surface but never accepts `customer_id` — it is resolved from the caller's own profile for that branch's tenant. Self-cancellation is rejected with `409` if the salon's `cancellation_window_minutes` setting is set and the booking starts within that window. `POST` additionally accepts `coupon_code`/`loyalty_points_to_redeem` (Phase 12, both optional) — see `LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md`.
- `POST /customer/bookings/price-preview` (Phase 12) — same shape as the owner preview above, always priced for the caller's own profile.

Owner dashboard (`auth:sanctum` and `tenant.context`; owner/super-admin only — added in Phase 8 for the Flutter owner app):

- `GET /dashboard/summary` — real, server-computed aggregates only, never fabricated: today's booking counts by status (`{total, pending, confirmed, checked_in, in_service, completed, cancelled, no_show}`), `revenue_today` (sum of `total` for today's `completed` bookings), `next_appointment` (the soonest active booking today or later, `null` if none), `staff.active`/`staff.on_leave_today` counts, and `customers.total`/`customers.new_this_month`. See `OWNER_APP_ARCHITECTURE.md` for exactly how each field is derived.

**Every business route above (`/salon*`, `/branches*`, `/service-categories*`, `/services*`, `/staff*`, `/customers*`, `/bookings*`, `/dashboard/summary`) additionally requires the tenant's subscription to be in an access-allowed state as of Phase 10** (`trialing`/`active`/`past_due`/`grace_period` — `cancelled`/`expired` return `402 Payment Required`). The billing routes below are exempt from this. See `SAAS_BILLING_ARCHITECTURE.md`, "Subscription access control".

SaaS billing / subscription (Phase 10 — see `SAAS_BILLING_ARCHITECTURE.md` for the full lifecycle, payment flow, and idempotency strategy):

- `GET /subscription` — `auth:sanctum` + `tenant.context`, any tenant member (owner or staff). Returns the tenant's one subscription row with its plan, status, trial/period/grace dates, `cancel_at_period_end`, and `has_business_access`. Never itself gated by subscription status — always reachable.
- `GET /subscription/plans` — same access; active plans only (`id`, `name`, `code`, `description`, `amount`, `currency`, `billing_interval`, `billing_interval_count`, `trial_days`).
- `POST /subscription/checkout` (owner/super-admin only — `managedTenant()`) — body: `{plan_id}` only, **never an amount**. Optional `Idempotency-Key` header for safe retries. Creates a real invoice + pending payment + gateway order; returns `{payment_id, idempotency_key, gateway, gateway_key, gateway_order_id, amount, currency, plan}` — `gateway_key` is a public/publishable key, never a secret.
- `POST /subscription/checkout/verify` (owner/super-admin only) — body: `{payment_id, gateway_payment_id, gateway_signature}`. Re-verifies the signature server-side against the stored gateway order before activating anything; returns the updated subscription. Idempotent — verifying an already-`paid` payment again is a no-op.
- `POST /subscription/renew` (owner/super-admin only) — identical shape to `checkout`, `plan_id` optional (defaults to the current plan). Same order-creation path; finalized through the same `checkout/verify` endpoint or the webhook.
- `POST /subscription/cancel` (owner/super-admin only) — no body. Sets `cancel_at_period_end`; the subscription keeps full access until `current_period_end`, then the scheduler moves it to `cancelled`. There is no way to set `status` directly — every transition happens as a side effect of checkout/renew/cancel/the scheduler.
- `GET /subscription/payments`, `GET /subscription/invoices` — any tenant member; paginated (`per_page`, maximum 100), newest first. Payments never include a gateway secret.
- `POST /webhooks/razorpay` — no `auth:sanctum` (the gateway calls this, not an authenticated user). Authenticity comes entirely from an HMAC-SHA256 signature check (`X-Razorpay-Signature`) against the raw request body; every event is recorded (unique per `gateway_event_id`) before processing, so a duplicated delivery is a safe no-op.

Platform plan administration (`auth:sanctum` only, not tenant-scoped; `manage-platform` gate — super_admin only. No Flutter Platform Admin app exists yet — backend-only APIs):

- `GET /platform/plans` — every plan, including inactive ones.
- `POST /platform/plans`, `PUT|PATCH /platform/plans/{plan}` — `name`, `code` (unique), `description`, `amount`, `currency`, `billing_interval` (`day`/`week`/`month`/`year`), `billing_interval_count`, `trial_days`, `is_active`, `features` (optional JSON).
- `POST /platform/plans/{plan}/activate`, `POST /platform/plans/{plan}/deactivate`.
- Changing a plan's `amount` never rewrites an already-issued invoice — see `SAAS_BILLING_ARCHITECTURE.md`, "Plan price history".

Notifications (Phase 11 — `auth:sanctum` only, never `tenant.context`: every query/mutation is scoped to the authenticated user directly, since a customer's inbox spans every tenant they hold a profile with; see `NOTIFICATION_ARCHITECTURE.md`):

- `GET /notifications` (`unread_only`, `page`, `per_page` — max 100), `GET /notifications/unread-count`, `POST /notifications/{notification}/read`, `POST /notifications/read-all`. Direct-ID access to another user's notification 404s rather than exposing it.
- `POST /notifications/device-tokens` — body `{platform, token, device_identifier?}`; upserts by the globally-unique `token`, reassigning it if a different user registers the same device. `POST /notifications/device-tokens/deactivate` — body `{token}`; a no-op (not an error) if the token doesn't exist or belongs to someone else.
- `GET|PUT /notifications/preferences` — personal channel opt-in/out (`{preferences: [{event_type, channel, enabled}]}`), independent of tenant. Only external channels (`push`/`email`/`whatsapp`/`sms`) are exposed; in-app is always on in this phase.

Tenant-wide notification defaults (`auth:sanctum` + `tenant.context` + `subscription.active`, same group as `/salon/settings`):

- `GET|PUT|PATCH /salon/notification-settings` — same `{event_type, channel, enabled}` matrix shape as the personal endpoint above, but scoped to the tenant and writable only by the salon owner (re-checked server-side on every write, not just tenant membership).

Coupons (Phase 12 — `auth:sanctum` + `tenant.context` + `subscription.active`, owner/super-admin only for every action; see `LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md`):

- `GET|POST /coupons`, `GET|PATCH|DELETE /coupons/{coupon}` — `code` (normalized upper-case, unique per tenant), `name`, `description`, `discount_type` (`percentage`|`fixed_amount`), `discount_value`, `minimum_booking_amount`, `maximum_discount_amount`, `starts_at`, `expires_at`, `usage_limit`, `usage_limit_per_customer`, `is_active`, `first_booking_only`, `service_ids[]`, `category_ids[]`. `DELETE` is a soft delete — historical bookings keep their coupon reference readable.
- `POST /coupons/{coupon}/activate`, `POST /coupons/{coupon}/deactivate`.

Membership plans (owner/super-admin only) and customer memberships (owner/super-admin, view + grant):

- `GET|POST /membership-plans`, `GET|PATCH|DELETE /membership-plans/{membership_plan}` — `name`, `code`, `description`, `price`, `currency`, `duration_days`, `discount_type`, `discount_value`, `maximum_discount_amount`, `is_active`, `service_ids[]`, `category_ids[]`.
- `POST /membership-plans/{membership_plan}/activate`, `POST /membership-plans/{membership_plan}/deactivate`.
- `GET /memberships` (`status`, `expiring_soon` filters), `GET /memberships/{customer_membership}`, `POST /memberships/grant` (`{customer_id, membership_plan_id}` — no payment, `source: owner_grant`), `POST /memberships/{customer_membership}/cancel`.

Loyalty (owner/super-admin — search/adjust; loyalty *settings* are part of `/salon/settings` above, not a separate endpoint):

- `GET /loyalty/customers` (`search` by name/phone, only accounts with a positive balance), `GET /loyalty/customers/{customer}`, `GET /loyalty/customers/{customer}/transactions`.
- `POST /loyalty/customers/{customer}/adjust` — `{points, reason}`; `points` is a signed delta (negative to deduct), `reason` required. Always produces an `ADJUSTMENT` ledger row — the balance is never overwritten directly.

Customer-facing membership/loyalty (`auth:sanctum` only, same X-Tenant-Slug convention as `/customer/profile`/`/customer/bookings`):

- `GET /branches/{branch}/membership-plans` — public browse, active plans only, mirrors `GET /branches/{branch}/services`.
- `GET /customer/membership` — the caller's current membership, or `null`.
- `POST /customer/membership/checkout` — `{membership_plan_id}` only, never a price (same rule as `/subscription/checkout`). `POST /customer/membership/checkout/verify` — `{payment_id, gateway_payment_id, gateway_signature}`. Both converge with the shared `POST /webhooks/razorpay` handler — whichever arrives first activates the membership.
- `GET /customer/loyalty` — the caller's own account. `GET /customer/loyalty/transactions` — paginated ledger.

Reports & analytics (Phase 13 — `auth:sanctum` + `tenant.context` + `subscription.active`; owner/super-admin only, `403` for staff and customer sessions; see `REPORTING_ANALYTICS_ARCHITECTURE.md`):

- `GET /reports/dashboard`, `GET /reports/revenue`, `GET /reports/bookings`, `GET /reports/customers`, `GET /reports/services`, `GET /reports/staff`, `GET /reports/branches`, `GET /reports/coupons`, `GET /reports/memberships`, `GET /reports/loyalty`.
- Shared query parameters: `range` (`today`|`yesterday`|`this_week`|`last_week`|`this_month`|`last_month`|`this_year`|`custom`, default `this_month`), `from`/`to` (`Y-m-d`, required together when `range=custom`), `group_by` (`day`|`week`|`month`, series bucketing), `page`/`per_page` (max 100), `sort`/`direction` — plus whichever of `branch_id`, `staff_id`, `service_id`, `category_id`, `status`, `customer_id`, `coupon_id`, `membership_plan_id` apply to that specific report. Every ID filter must belong to the authenticated tenant or the request `422`s.
- Response shape: `data` contains whichever of `summary` (aggregate totals), `series` (a zero-filled, timezone-bucketed time series), `breakdown` (grouped sub-totals, e.g. by branch/staff/service), and `data` (a paginated list, e.g. top customers or coupon usage) apply to that report.
- `range=today`/`this_week`/etc. resolve against the salon's timezone (or a filtered branch's own timezone), never the server's — see "Timezone handling" in `REPORTING_ANALYTICS_ARCHITECTURE.md`. `GET /dashboard/summary` (Phase 8, above) was fixed in this phase to use the same resolution instead of the server's UTC clock.
- Revenue/staff/service figures use `booking_items`' historical price snapshots and proportionally allocate each booking's discount across its items — a later service-price or coupon-config change never changes a past report. Coupon/loyalty reports read only from their immutable ledgers (`coupon_usages`/`loyalty_transactions`), never a model's current configuration. Membership revenue is `membership_payments` only — never mixed with SaaS `payments`/`invoices` (Phase 10's own subscription/billing history remains at `/subscription*`, unchanged by this phase).
