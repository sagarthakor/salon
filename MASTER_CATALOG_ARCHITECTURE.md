# Master Catalog & Service Segmentation Architecture

A targeted feature addition, not a new numbered phase: makes the salon SaaS usable by a non-technical owner out of the box, by giving every new tenant a professional starting service catalog instead of an empty one, and giving customers a simple "Men / Women / Unisex / Kids" way to browse it. Builds directly on Service Media (`services.image_url`/`instagram_url`/`description`) and reuses the existing tenant, authorization, and booking architecture unchanged — see `SERVICE_ARCHITECTURE.md`, `MULTI_TENANCY.md`, and `BOOKING_ENGINE.md`.

## The problem

A brand-new owner, right after completing Salon Profile + their first Branch (see `OWNER_APP_ARCHITECTURE.md`, "Owner onboarding: salon setup"), previously had zero services and zero categories. Building a real catalog from scratch — typing in "Hair Cut," "Beard Trim," "Bridal Makeup," one at a time, each needing a category, a price, a duration — is exactly the kind of setup friction a less tech-savvy owner is likely to abandon.

## Two-tier design: master catalog vs. tenant services

```
MASTER CATALOG (platform-level, never tenant-scoped)
  master_service_categories (audience, name, slug, sort_order, is_active)
      └── master_services (audience, name, description, default_duration_minutes, default_price, sort_order, is_active)

                    │  CatalogProvisioningService — one-time COPY
                    ▼

TENANT (per-branch, existing tables extended)
  service_categories (+ audience column)
      └── services (+ audience column, + master_service_id provenance column)
```

`master_service_categories`/`master_services` (new tables, migration `2026_08_30_000000_create_master_catalog_tables.php`) hold the platform's curated template — no `tenant_id`, no `BelongsToTenant`, not reachable through any owner-facing write API. They are read only by `CatalogProvisioningService` and by `MasterCatalogSeeder`, and by nothing else in the request lifecycle.

`service_categories`/`services` (existing tables, migration `2026_08_30_000100_add_audience_to_service_tables.php` adds a nullable `audience` column to each, plus a nullable `services.master_service_id`) are exactly what they were before this feature — tenant-owned, tenant-isolated, fully independent rows. **Provisioning is a one-time copy, never a live link.** Once a tenant's `Service` row exists, editing its price, duration, image, or Instagram URL never touches the master catalog or any other tenant, and nothing ever writes back to `master_services`. `master_service_id` exists purely for idempotency bookkeeping (see below) and is `nullOnDelete()`, so even removing a master catalog row later can never cascade into an already-provisioned tenant service.

## Audience segmentation: `ServiceAudience`

A new enum, `App\Enums\ServiceAudience` (`MALE`, `FEMALE`, `UNISEX`, `KIDS`), deliberately separate from the pre-existing `GenderType` (Salon's served-gender classification) — this project's established convention is one small enum per concept (see also `CustomerGender`, `StaffGender`), never one shared "gender" enum forced across unrelated entities. `Service.gender` (the original `GenderType`-backed field, male/female/unisex only) is untouched for backward compatibility — every existing filter, report, and client that reads it keeps working exactly as before. `audience` is the new, authoritative classification for the master-catalog/segmentation feature: it appears on both `MasterServiceCategory`/`MasterService` and their tenant `ServiceCategory`/`Service` counterparts, and is what `GET /services?audience=`, `GET /service-categories?audience=`, and `GET /branches/{branch}/services?audience=` all filter on.

A Kids-audience master service has no `GenderType` equivalent to map to (that enum has no "kids" case); `CatalogProvisioningService` maps it to `GenderType::UNISEX` for the legacy `gender` column specifically — a deliberate, documented compromise so the old field never needs a breaking change, while `audience` (not `gender`) is the field every new code path actually filters on.

**Unisex is never a synonym for "male or female."** A service belongs to exactly one audience. Selecting Unisex on the customer app never pulls in Male/Female services, and selecting Male never pulls in Unisex ones — verified explicitly by `CatalogProvisioningApiTest::test_unisex_audience_filter_returns_only_unisex_services_never_male_or_female`.

## Provisioning: `CatalogProvisioningService`

```php
app(CatalogProvisioningService::class)->provisionForBranch($branch);
```

Called from `BranchController::store()`, right after a branch is created — the earliest point a tenant-owned service can exist at all, since `branch_id` is a required column on both `service_categories` and `services`, and a brand-new tenant has no branch until the owner creates one (see `OWNER_APP_ARCHITECTURE.md`, "Owner onboarding: salon setup," for why there's no earlier hook point like `Tenant::booted()`).

**Idempotency** is a single guard, not split across the controller and the service: `provisionForBranch()` checks whether the calling tenant already has *any* `Service` row with a non-null `master_service_id` (on any branch) and returns immediately if so. Because `Service` is `BelongsToTenant`-scoped, this check is automatically tenant-isolated — it can only ever see the current tenant's own rows. The check-then-insert runs inside one `DB::transaction()` that first takes a `lockForUpdate()` on the tenant's own row — the same pattern `BookingService`/`CouponService` already use for their own check-then-write races (see `SECURITY_HARDENING.md`). Without this, two `POST /branches` requests for the same brand-new tenant's first two branches arriving concurrently (two browser tabs, a retried request) could both pass the "not yet provisioned" check before either had inserted anything, and both proceed to copy the full catalog; the lock forces the second transaction to wait for the first to commit, at which point its own check correctly sees the catalog already exists. Consequences:

- A tenant's **first** branch gets the full catalog copied in, inside one `DB::transaction()`.
- A tenant's **second** (and every subsequent) branch is a no-op for provisioning — the owner is free to build a completely different catalog there without the master catalog re-injecting itself.
- Calling `provisionForBranch()` twice for the same branch, or a thousand times, only ever provisions once.
- If a tenant somehow ends up with zero services again (its only branch deleted, `cascadeOnDelete()` removing the services with it) and creates a new branch, provisioning correctly fires again — the guard reflects real current state, not a one-time flag.

**What gets copied, and what deliberately doesn't:** name, description, `default_duration_minutes` → `duration_minutes`, `default_price` → `price` (or `0` if a master service has no suggested price — new services should never be created price-less), `audience`, category. **Never** copied: `image`/`instagram_url` — every provisioned service starts with both `null`, exactly like a service an owner created by hand. The owner adds their own photo and Instagram link afterward, through the same Service Media UI as any other service (see `OWNER_APP_ARCHITECTURE.md`, "Service media").

## Backfilling existing tenants

Provisioning only fires from `BranchController::store()`, so a tenant that already has branches before this feature shipped is never retroactively touched — its existing services and categories are left completely alone (`audience` stays `null` on them, same as any manually-created category/service going forward that an owner doesn't tag). There is no automatic backfill migration for existing tenant data, by design: silently injecting ~75 new services into an already-configured salon's catalog would be far more disruptive than leaving it as-is. An existing owner who wants the starter catalog can be given it manually (fixture/support tooling only, never a public API) by invoking `CatalogProvisioningService::provisionForBranch()` for one of their branches — the same idempotency guard applies.

## Master catalog seeder

`Database\Seeders\MasterCatalogSeeder` is the *only* way `master_service_categories`/`master_services` are ever populated — there is no admin UI or write API for the master catalog (see "Authorization" below). It is safe to run any number of times: every row is `updateOrCreate`d against a stable key — `(audience, slug)` for categories, `(master_service_category_id, slug)` for services — never bare names, and never destructive (it never deletes a row, so re-running after manually editing `is_active`/`sort_order` in the database is the only way those edits would be overwritten — expected seeder behavior, not a bug). Registered in `DatabaseSeeder::run()` for local dev/`php artisan migrate:seed`; run standalone via `php artisan db:seed --class=Database\\Seeders\\MasterCatalogSeeder --force`.

The starting catalog itself: 4 audiences, 14 categories, 75 services — Male (Hair, Beard & Shaving, Facial & Skin), Female (Hair, Facial & Skin, Threading, Waxing, Nails, Makeup), Unisex (Hair, Skin, Nails, Spa), Kids (Hair). `duration`/`price` are set once per category and applied to every service listed under it — a deliberate simplification over hand-tuning ~75 individual values, and, per the feature's own framing, suggested/default data only: the tenant's own `Service.price`/`duration_minutes` (set once at provisioning, then fully independent) is what booking/pricing actually uses.

## Authorization & tenant isolation

Nothing about authorization changed except adding one more optional, validated field to the existing Service/ServiceCategory write paths:

- **Owner**: `managedTenant()` gates every write, exactly as before Service Media/this feature. An owner can freely edit their own tenant's `audience` field on a service/category (e.g. re-tagging a manually-created service), same as any other field.
- **Customer**: read-only, via the existing `CustomerServiceController` (now accepting an optional `audience` filter) — never able to write, unaffected by this feature.
- **Staff**: unchanged — no owner-level catalog management was ever available to staff, and this feature adds none.
- **Master catalog**: no route reaches it at all. `POST /master-service-categories` and `POST /master-services` simply don't exist — the master catalog is unreachable from any authenticated session, owner or otherwise, by construction rather than by a permission check that could be misconfigured. See `CatalogProvisioningApiTest::test_master_catalog_has_no_write_endpoint_reachable_by_an_owner`.
- **Cross-tenant isolation**: unchanged mechanism (`Service`/`ServiceCategory`'s existing `BelongsToTenant` global scope on every lookup), verified explicitly for provisioned (not just hand-created) services — a fully valid same-tenant request body targeting another tenant's provisioned service by ID still 404s.

## Customer experience

```
Home (existing) → tap a branch (existing)
  → Audience selection (new): "What service are you looking for?" — Men / Women / Unisex / Kids
    → Service catalog (existing screen, unchanged widgets) — now audience-filtered
      → select service(s) → existing booking flow, completely unchanged
```

The audience step is a new screen (`AudienceSelectionScreen`, four large cards, never a dropdown or a screen full of category IDs) inserted between the existing branch tile and the existing service catalog screen — `home_tab.dart`'s branch tap now navigates to `/booking/audience` instead of straight to `/booking/services`. Everything downstream — `BookingServiceSelectionScreen`'s category-grouped, checkbox-driven service list, the image/description/price/duration/Instagram-link tile from Service Media, the booking flow itself — is unchanged, just now given a `(branchId, audience)` key instead of `branchId` alone. A "Categories" screen was deliberately **not** added as a separate tap-through step: the existing category-header-then-services-beneath layout already satisfies "Audience → Categories → Services" without an extra screen, and adding one would work against the feature's own accessibility goal ("avoid deep navigation where possible").

An audience with zero services for a given branch shows a friendly message ("No Kids services here yet. Please check back soon or choose another option.") — never an error, never a blank screen.

## Owner experience

The existing Services screen (`ServiceListScreen`) gained two things, both additive:

- An audience filter bar (All / Men / Women / Unisex / Kids chips) — the same segmentation the customer sees, so an owner reviewing "what am I offering Men?" sees exactly what a Men customer would.
- A quick ON/OFF `Switch` per service, and an explicit "Edit" button — enabling/disabling a service no longer requires opening the edit form at all. The switch reuses the existing `updateService()` call (there is no separate toggle endpoint) with every other field carried over unchanged from the service already in memory.

No new screen, no new provider file beyond what's listed — `service_list_screen.dart`, `owner_service_list_controller.dart` (`setAudience()`, `toggleStatus()`), and `owner_service_repository.dart` (`audience` query parameter) are the only owner-side changes.

## Performance

Both new `audience` columns are indexed alongside `tenant_id` (`(tenant_id, audience)` on `services` and `service_categories`), matching every filterable/scoped column this project already indexes. `CatalogProvisioningService` eager-loads `masterServiceCategory.masterServices` in two queries total (not N+1) regardless of catalog size. The customer catalog endpoint (`GET /branches/{branch}/services`) already returned only one branch's active services before this feature and still does — audience narrows that same query further, it never fetches the master catalog or any other tenant's data.
