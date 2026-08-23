# Database Architecture

Current tables include `users`, `tenants`, `tenant_user`, `salons`, `salon_settings`, `branches`, `branch_working_hours`, `branch_holidays`, `personal_access_tokens`, and Laravel cache/job/session/password-reset tables.

`tenants.id` is a ULID to avoid exposing sequential tenant identifiers. `tenant_user` has a composite primary key of `(tenant_id, user_id)`, a tenant-role column, and a reverse `(user_id, tenant_id)` index. Tenant-owned tables added in later phases must include `tenant_id`, foreign keys, and indexes based on actual tenant query paths.

`salons` has a unique tenant foreign key, enforcing one salon profile per tenant. Branch slugs are unique per tenant. Working hours are unique per `(branch_id, day_of_week)`; holidays are unique per `(branch_id, holiday_date)`. Branches and salons use soft deletes. All Phase 2 operational tables carry `tenant_id` and tenant/parent indexes.

`service_categories` and `services` are soft-deletable tenant-owned branch records. Service prices use `decimal(12,2)` and duration uses integer minutes. Indexes support branch/status, category, and gender filters.
