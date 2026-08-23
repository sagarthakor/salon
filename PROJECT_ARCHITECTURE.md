# Project Architecture

Phase 2 adds a tenant-scoped salon profile and physical branches. Flutter and web clients will consume `/api/v1`; neither will access MySQL directly. The application uses controllers, Form Requests, Resources, policies, and application support services. Services, staff, booking, payments, and subscriptions have deliberately not been added.

`User` is the unified identity. `Tenant` represents a salon business. The `tenant_user` pivot allows one user to have memberships in multiple tenants with a tenant-specific role.

Each tenant has one `Salon` profile and zero or more `Branch` records. A salon owns settings; a branch owns working hours and holidays.

Phase 3 adds tenant-scoped, branch-specific service categories and services. Each branch owns its service price, duration, status, and future availability configuration.
