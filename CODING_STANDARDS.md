# Coding Standards

Follow Laravel conventions and PSR-12. Controllers remain thin; validation belongs in Form Requests, serialization in Resources, and authorization in policies/middleware. Use services only for genuine cross-model business workflows. All API endpoints must use the common response contract. Tenant-owned models must use the tenancy trait; platform models must be explicitly kept outside tenant scopes.
