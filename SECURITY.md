# Security

Sanctum issues expiring bearer tokens (default seven days); logout revokes the current token. Passwords are hashed by Laravel and requests are validated by Form Requests. Authentication endpoints are throttled.

Tenant membership is verified server-side in middleware and policies. Client-provided `role`, `user_id`, and `tenant_id` are not authorization inputs. Future tenant resource endpoints must use `auth:sanctum`, `ResolveTenantContext`, policies, and tenant-scoped models together. Do not log tokens, passwords, payment secrets, or unnecessary PII.
