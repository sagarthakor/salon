# Testing

Run `php artisan test`. Phase 1 covers registration, login, logout, current-user access, tenant membership, authorization policy decisions, cross-tenant context rejection, and automatic tenant model scoping. Phase 2 adds salon/settings, branch CRUD, working-hour validation, holiday uniqueness, staff denial, and cross-tenant direct-ID tests. Tests use isolated SQLite databases through Laravel's default test configuration.

Phase 3 adds category/service CRUD, ownership, money/duration validation, filters, soft deletion, and direct-ID tenant-isolation tests.
