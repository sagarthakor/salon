# Salon and Branch Architecture

## Ownership

`Tenant` is the salon business/account; it has one tenant-scoped `Salon` profile. `Salon` has many tenant-scoped `Branch` records, representing physical locations. A branch belongs to both the tenant and salon, which lets database constraints and tenant scoping validate the hierarchy.

## Configuration

`salon_settings` stores approved key/value settings as JSON. Phase 2 accepts only `booking_enabled`, `customer_booking_enabled`, and `default_timezone`; these are configuration values only and do not implement booking behavior. This provides a controlled extension point rather than columns scattered across unrelated tables.

Branch counts are intentionally not enforced in `BranchController`. A future subscription/entitlement service will evaluate limits centrally before branch creation, keeping billing policy outside this module.

## Availability inputs

Each branch can hold one record per weekday in `branch_working_hours`. Open days require a valid opening time before their closing time; closed days cannot carry times. `branch_holidays` has one record per branch/date and represents future availability closures. No slots or booking calculations are implemented in this phase.

## Authorization and isolation

All management APIs require Sanctum authentication plus resolved tenant context. Tenant owners and super admins can manage the selected tenant. Staff and customers cannot modify configuration. `BelongsToTenant` scopes every Phase 2 model; direct branch or holiday IDs from another tenant cannot resolve.
