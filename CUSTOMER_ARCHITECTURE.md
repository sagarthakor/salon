# Customer Architecture

## Ownership

`Customer` (table `customer_profiles`) is a tenant-scoped, soft-deletable profile — the tenant relationship itself, not a separate pivot. `Tenant → Customer` is a direct one-to-many: a `customer_profiles` row belongs to exactly one tenant, and the same person visiting two salons is represented by two separate rows (one per tenant), optionally sharing the same `user_id`.

## Customer/User relationship

`AuthController::register` already creates a platform `User` with `role = customer` for anyone who self-registers, independent of any tenant (`tenant`/`role` input is ignored — see `API_DOCUMENTATION.md`). Phase 5 builds on that fact rather than duplicating it:

- `customer_profiles.user_id` is a nullable, tenant-unique foreign key to `users`. A **walk-in customer** (front-desk record, no login) has `user_id = null`.
- Linking a profile to a login requires the target user's platform role to already be `customer` (`Rule::exists('users','id')->where('role','customer')`) — an owner cannot accidentally attach a staff/owner account as a customer.
- **Deliberate divergence from Staff**: unlike `staff_profiles`, customer linkage does **not** go through a `tenant_user`-style membership row. `TenantMembershipRole` intentionally still only has `salon_owner`/`staff` (unchanged from Phase 1) — a customer must never be able to pass `ResolveTenantContext`'s tenant-membership check, because that check is also the gate `TenantPolicy::manage`/`view` use for tenant configuration access. Extending `tenant_user` with a `customer` role would risk quietly widening what a customer can reach. `customer_profiles` itself is therefore the entire tenant-relationship record for a customer; no separate `tenant_customer` pivot exists.
- Consequence: customers cannot use `tenant.context`-gated routes at all (confirmed by test — a platform `customer`-role user gets 403 on `/customers`, same as any non-member). Their self-service routes (`/api/v1/customer/profile`) intentionally live outside `tenant.context` — see below.

## Self-service profile resolution (`/api/v1/customer/profile`)

Because a `User` may hold `customer_profiles` rows in more than one tenant (same phone/login, multiple salons), and because customers cannot resolve a tenant through `ResolveTenantContext`, `CustomerProfileController` resolves the caller's own profile directly:

1. Require only `auth:sanctum` (no `tenant.context`).
2. Look up `customer_profiles` by `user_id = auth()->id()`, bypassing the `BelongsToTenant` global scope explicitly (`withoutGlobalScope('tenant')`) — safe because every query is additionally constrained by the authenticated user's own ID, so it can only ever return that user's own rows, matching the "deliberately reviewed platform-only opt-out" pattern already described in `MULTI_TENANCY.md`.
3. If `X-Tenant-Slug` is supplied, scope to that tenant. Otherwise: exactly one profile → return it; zero → 404; more than one → 422 asking the client to disambiguate with `X-Tenant-Slug`.

`GET /api/v1/auth/me` is unchanged and still returns the platform identity; it is not duplicated by the customer profile endpoints, which return the tenant-scoped operational profile (phone, address, notes-free) instead.

Self-service profile creation (a customer creating their own `customer_profiles` row for a new tenant without staff involvement) was **not** implemented in Phase 5 — it belonged to the future booking flow (a customer can only meaningfully "join" a salon in the context of booking with it). It is now implemented — see "Customer salon discovery and first-time booking" below.

## Branch relationship

A customer is **not** bound to a single branch. `customer_profiles` has no `branch_id`. A customer of a multi-branch salon can visit any branch; the branch relationship belongs to the future booking record (`Tenant → Customer`, `Branch → Booking`), not to the customer profile itself.

## Phone and uniqueness

`phone` (display value) and `country_code` (optional) are stored as entered; `normalized_phone` (digits-only, country code prefixed when present) is a stored, tenant-unique column used for both duplicate detection and search. The same phone number is allowed across different tenants (verified by test) but rejected as a duplicate within one tenant regardless of formatting differences (e.g. `9876543210` and `(987) 654-3210` normalize to the same value). Phase 5 rejects the duplicate create with a validation error rather than silently creating a second record or auto-merging — merge flows are explicitly out of scope.

## Notes

`customer_notes` is a separate table (not a profile field) because the API contract requires a full CRUD sub-resource (`GET/POST/PUT/PATCH/DELETE /customers/{customer}/notes/...`), implying a running log of multiple timestamped entries rather than one field — the same shape as `staff_breaks`/`staff_leaves`. Each note records `author_id` (the staff/owner user who wrote it). Notes are **owner/super-admin only**: not returned to staff, and never exposed on any customer-facing endpoint (`CustomerResource` has no notes field; `/customer/profile` never touches `customer_notes`).

## Status

Customers reuse `BusinessStatus` (`active`/`inactive`), consistent with Salon/Branch/Service/Staff. `DELETE /customers/{customer}` soft-deletes (history-preserving, matching Staff); marking a profile `inactive` is the non-destructive way to stop new activity while keeping the record fully intact and visible to direct lookups.

## Summary endpoint

`GET /customers/{customer}/summary` returns the customer profile plus a `summary` object (`total_visits`, `completed_appointments`, `cancelled_appointments`, `no_show_count`, `total_spent`, `last_visit_at`, `upcoming_appointment`). No booking table exists yet, so every field is a real, honest zero/null rather than fabricated data — these are documented placeholders. The booking engine (Phase 6) is expected to populate this endpoint from its own tables; the shape is fixed now so client code can be built against it early.

## Authorization

- **Salon owner / super admin**: full CRUD on customers, notes, and summary (`TenantManagementController::managedTenant()`).
- **Staff**: read-only — list, view, search, and filter customers (`TenantManagementController::viewableTenant()`, a new additive method reusing the existing `TenantPolicy::view` gate, which already allows any tenant member). Staff have no access to notes or summary, per the literal Phase 5 brief ("do not automatically give staff access to sensitive/admin-only information") — loosening this to allow staff read access to summary/notes later is a one-line change if the business needs it.
- **Customer**: `/api/v1/customer/profile` only (own record, resolved by `user_id`, never by a client-supplied ID). No access to `/api/v1/customers*` at all, since customers hold no tenant membership.

## Tenant isolation

`Customer` and `CustomerNote` use `BelongsToTenant` exactly like every other Phase 2–4 model. Direct-ID access to another tenant's customer or notes resolves to 404 through scoped `findOrFail` queries (verified by test, including `summary`).

## Future booking dependency

The schema is shaped so a future `Booking` can reference `customer_id` + `branch_id` + `staff_id` independently: `Tenant → Customer` (this phase) and `Branch → Booking` (Phase 6) are separate edges, not `Customer → Branch`. The summary endpoint's placeholder fields map directly to future booking aggregates once that table exists.

## Customer salon discovery and first-time booking

A real-device QA finding showed the original `GET /customer/salons` (`CustomerSalonController::index()`) is membership-only by design — it lists only tenants where a `customer_profiles` row already links the authenticated user, created by staff via `CustomerController::store()` (Phase 5, above). A brand-new customer who has never been registered by any salon therefore saw an empty list, and even a customer staff *had* registered still saw nothing if that registration was never linked to their `user_id` (staff-side "add a customer" never collects/sets `user_id` — it's phone/name/email only).

The product requirement is that discovery and registration are independent: a customer must be able to find and book a salon without a staff member registering them first.

**Discovery is deliberately cross-tenant.** Two new endpoints, both under the existing tenant-free `/api/v1/customer` prefix (`auth:sanctum` only, no `tenant.context`, no `X-Tenant-Slug` requirement):

- `GET /customer/discover-salons` — every `Salon` with `status = ACTIVE`, across every tenant, via `Salon::withoutGlobalScope('tenant')`. No membership filter. Returns the same `SalonResource` shape `index()` already used for customers, which was already customer-safe (no owner/billing/staff fields) — the leftover *directory* gap was the query, not the resource.
- `GET /customer/salons/{salon}/branches` — resolves the salon (and therefore its tenant) entirely server-side from the `{salon}` id, requires `status = ACTIVE` on both the salon and its branches, and never accepts a tenant identifier from the client. `salons.tenant_id` and `salons.slug` are both globally unique (see `create_salon_management_tables` migration), so a salon id can never resolve to more than one tenant.

Once a branch is picked, everything downstream is unchanged and already tenant-safe: `CustomerServiceController`/`AvailabilityController` resolve their tenant from the `{branch}` id the same way, with no customer-profile requirement either.

**First-time booking auto-creates the profile.** `CustomerBookingController::store()`/`pricePreview()` used to 404 ("Ask the salon to register you first") when no `customer_profiles` row existed yet for the resolved tenant — the last real gap, since a customer who discovered a salon this way still couldn't complete a booking. Both now call a shared `resolveOrCreateCustomer()`:

1. Reuse the existing profile if `customer_profiles.user_id = auth()->id()` already has one for this tenant (unchanged existing-customer path).
2. Otherwise, require a `phone` in the booking/price-preview request and create the profile from the authenticated `User`'s own identity (`user_id`, `name`, `email`) plus that phone — never from a client-supplied `customer_id` or any other user's data.
3. The table's two unique constraints (`tenant_id`+`user_id`, `tenant_id`+`normalized_phone`) are handled explicitly: a race on the same user re-fetches and reuses the row the concurrent request created (no duplicate, no failed booking); a genuine conflict against a *different* existing phone (e.g. a walk-in profile staff already created for someone else) is surfaced as a normal 409, never a raw `QueryException`.

This does not change `CustomerController::store()` (owner/staff manual registration) at all — it remains the only path for walk-in/offline customers with no app account, and is unaffected by whether a given app customer ever discovers/books that salon themselves.
