# Salon provisioning & seeders

Makes a salon bookable without manual setup. Slots are never stored: `AvailabilityService` derives them from branch hours, staff hours/breaks, staff↔service assignments and `salon_settings`, so provisioning seeds those inputs.

## What runs when
| Where | What |
|---|---|
| `POST /salon` (owner onboarding) and `POST /branches` | `CatalogProvisioningService` (master catalog copy, first branch only) then `BranchDefaultsService` |
| `php artisan salon:provision {tenant} [--branch=] [--with-catalog] [--dry-run]` | Same defaults for an existing tenant. Catalog only if the tenant has no services (or `--with-catalog`) |
| `php artisan db:seed --class=MasterDataSeeder --force` | Platform master data only (14 categories, 75 services: Male 19, Female 40, Unisex 13, Kids 3). Safe on production |
| `php artisan db:seed` (`DatabaseSeeder`) | Local only: master data + demo users + `demo-salon` via `DemoSalonSeeder` (refuses in production) |

## `BranchDefaultsService` (additive, per branch)
`config/salon_defaults.php`: settings (slot 30 min, min advance 30 min, max advance 30 days, buffer 0, cancellation window 120 min, booking enabled) inserted only for missing keys; branch hours Mon–Sat 09:00–20:00, Sunday closed, only for missing weekdays; one active "Default Stylist" (no login, `default-stylist-{branch}@staff.invalid`) **only when the branch has no staff**, assigned to the branch's active services, same weekly hours, 13:00–14:00 break. Services are assigned only when that stylist is created (or has none), so removals by the owner stick. Owners rename/replace the stylist in Staff. Set `salon_defaults.default_staff.enabled` false to skip.

Never seeded: holidays (they are dated and salon-specific), bookings, customers, payments, gallery items, Instagram connections. Enums (roles, statuses, gallery categories, audiences) and `plans` (inserted by its migration) need no seeder; there is no permissions or payment-methods table.
