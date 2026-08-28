# Salon and Branch Architecture

## Ownership

`Tenant` is the salon business/account; it has one tenant-scoped `Salon` profile. `Salon` has many tenant-scoped `Branch` records, representing physical locations. A branch belongs to both the tenant and salon, which lets database constraints and tenant scoping validate the hierarchy.

## Configuration

`salon_settings` stores approved key/value settings as JSON. Phase 2 accepts `booking_enabled`, `customer_booking_enabled`, and `default_timezone` as configuration values only. Phase 6 extends the same approved-key list with `slot_interval_minutes`, `min_advance_booking_minutes`, `max_advance_booking_days`, `booking_buffer_minutes`, and `cancellation_window_minutes`, read by `App\Support\BookingSettings` — see `BOOKING_ENGINE.md`. Adding a key is purely an enum + settings-resolver change; `PUT /salon/settings` needed no changes. This provides a controlled extension point rather than columns scattered across unrelated tables.

Branch counts are intentionally not enforced in `BranchController`. A future subscription/entitlement service will evaluate limits centrally before branch creation, keeping billing policy outside this module.

## Availability inputs

Each branch can hold one record per weekday in `branch_working_hours`. Open days require a valid opening time before their closing time; closed days cannot carry times. `branch_holidays` has one record per branch/date and represents future availability closures. No slot or booking calculations were implemented in Phase 2; Phase 6's `AvailabilityService` is the first consumer of this data — see `BOOKING_ENGINE.md`.

## Authorization and isolation

All management APIs require Sanctum authentication plus resolved tenant context. Tenant owners and super admins can manage the selected tenant. Staff and customers cannot modify configuration. `BelongsToTenant` scopes every Phase 2 model; direct branch or holiday IDs from another tenant cannot resolve.
