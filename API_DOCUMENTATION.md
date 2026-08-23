# API Documentation

Base path: `/api/v1`. Responses use `success`, `message`, and `data` on success; errors use `success`, `message`, and `errors`.

- `POST /auth/register` — customer registration; role and tenant input are ignored.
- `POST /auth/login` — email/password token login.
- `POST /auth/logout` — revoke the current Sanctum token.
- `GET /auth/me` — authenticated user and tenant memberships.

Login/register endpoints are rate-limited to five requests per minute by email and IP. Use `Authorization: Bearer <token>` for protected endpoints.

Salon management endpoints require `auth:sanctum` and `tenant.context`; only a tenant owner or super admin may use them.

- `GET|POST|PUT|PATCH /salon`
- `GET|PUT|PATCH /salon/settings`
- `GET|POST /branches`, `GET|PUT|PATCH|DELETE /branches/{branch}`
- `GET|PUT /branches/{branch}/working-hours`
- `GET|POST /branches/{branch}/holidays`
- `PUT|PATCH|DELETE /branches/{branch}/holidays/{holiday}`

`X-Tenant-Slug` may select an active tenant only after server-side membership verification. Branch and holiday IDs are never sufficient authorization.

Service management APIs: `GET|POST /service-categories`, `GET|PUT|PATCH|DELETE /service-categories/{service_category}`, `GET|POST /services`, and `GET|PUT|PATCH|DELETE /services/{service}`. Service lists paginate and accept `branch_id`, `category_id`, `gender`, `status`, `sort`, and `per_page` (maximum 100).
