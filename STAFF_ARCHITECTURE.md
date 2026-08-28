# Staff Architecture

## Ownership

`Staff` (table `staff_profiles`) is a tenant-scoped, soft-deletable profile. It optionally links to a `User` via a nullable `user_id`, which lets a staff member log in and access their own tenant-scoped data without duplicating identity or credentials in `staff_profiles`. `user_id` is unique per tenant.

**Login decision**: creating or updating a staff profile does not create a `User` or a `tenant_user` membership. `user_id` must reference a user who *already* has an active `tenant_user` membership with role `staff` for the current tenant (validated server-side via `Rule::exists('tenant_user', ...)`). Provisioning staff login credentials is a separate, not-yet-built concern (an extension of Phase 1 auth); Phase 4 only links an existing membership to a profile. Staff who never need to log in simply have `user_id = null` and are managed entirely by the owner.

## Branch assignment

A staff member can be assigned to zero, one, or many branches via the `staff_branches` pivot table (many-to-many), supporting both single-branch salons today and multi-branch salons later. Branch IDs are validated against the current tenant on every write.

## Service assignment

`staff_services` is a many-to-many pivot between `staff_profiles` and `services`. Assigning services validates that each service belongs to the current tenant, and — when the staff member has one or more assigned branches — that the service's branch is one of them. A staff member with no branch assignment yet can be assigned any tenant service (branch assignment can follow later).

Both pivot tables carry `tenant_id`. Pivot inserts via `sync()`/`attach()` bypass Eloquent model events, so `tenant_id` is supplied explicitly in the pivot payload rather than relying on `BelongsToTenant`'s `creating` hook (which only fires for `Model::create()`).

## Working hours

`staff_working_hours` mirrors `branch_working_hours`: one row per `(staff_id, day_of_week)`, replaced wholesale via `PUT`. Working days require `start_time` and `end_time` with `start_time < end_time`; off days must not carry times.

## Breaks

`staff_breaks` allows multiple rows per staff per day. A break must fall within that day's working hours (a working, non-off day must exist for the break's `day_of_week`) and must not overlap any other break on the same day for that staff member.

## Leave

`staff_leaves` stores a date range, optional reason, and a `status` (`pending`, `approved`, `rejected`). Leave created by the owner defaults to `approved` since the owner is directly blocking the dates. Overlapping non-rejected leave ranges for the same staff member are rejected.

## Status

Staff reuse `BusinessStatus` (`active`/`inactive`), consistent with `Salon`, `Branch`, `Service`, and `ServiceCategory`. Deactivating a staff member (`status = inactive`) is the intended way to stop new assignments while keeping history; `DELETE /staff/{staff}` soft-deletes the profile so historical references (future bookings, reporting) remain intact.

## Authorization

- **Salon owner / super admin**: full CRUD on staff, services, branches, working hours, breaks, and leave (`TenantManagementController::managedTenant()`, same as Branch/Service).
- **Staff**: read-only access to their own profile, services, working hours, and leave via `StaffPolicy::view`, which allows the tenant owner or the user whose `staff_profiles.user_id` matches the authenticated user. Staff cannot create, update, or delete any staff record, including their own.
- **Customer**: has no tenant membership in this architecture (`tenant_user` only has `salon_owner`/`staff` roles), so `ResolveTenantContext` already rejects customers with 403 before any staff endpoint runs.

## Tenant isolation

All Phase 4 tables carry `tenant_id` and use `BelongsToTenant`. Direct-ID access to another tenant's staff, breaks, or leave resolves to 404 through scoped `findOrFail` queries, matching the Phase 2/3 pattern.

## Booking engine compatibility

The schema directly answers the questions Phase 6 will need:

1. Active? — `staff_profiles.status`.
2. Performable services? — `staff_services`.
3. Branch? — `staff_branches`.
4. Working that day? — `staff_working_hours.is_working` for the day.
5. Working hours? — `staff_working_hours.start_time`/`end_time`.
6. Breaks? — `staff_breaks` for the day.
7. On leave? — `staff_leaves` date range containing the target date.

No slot computation or availability merging is implemented in Phase 4.
