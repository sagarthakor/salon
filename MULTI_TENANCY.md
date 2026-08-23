# Multi-tenancy

This project uses shared-database, row-level tenancy. The authenticated user is the authority for membership; a body `tenant_id` is never trusted.

`ResolveTenantContext` chooses the user's active tenant membership, or an `X-Tenant-Slug` only after verifying that the user belongs to that active tenant. It stores the result in request-scoped `TenantContext` and clears it after the response. Future public routes can resolve by slug or subdomain without changing tenant-owned models.

Tenant routes must use `auth:sanctum` and the `tenant.context` middleware alias.

Tenant-owned models must use `App\Models\Concerns\BelongsToTenant`. The trait scopes queries to the context, fails closed when no context exists, and overwrites `tenant_id` during creation. Platform tables must not use this trait. Platform-wide reporting must deliberately opt out of the global scope from a reviewed platform-only service.

`Salon`, `SalonSetting`, `Branch`, `BranchWorkingHour`, and `BranchHoliday` are tenant-owned. Controllers do not accept tenant IDs or salon IDs from branch clients: tenant IDs come from the context and a branch is attached to the current tenant's salon. Direct branch and holiday IDs are resolved through scoped queries, so another tenant receives a 404 rather than data.

Service categories and services use the same scope. The API validates branch and category ownership in the current tenant context, including that a category belongs to the selected branch.
