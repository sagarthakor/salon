<?php

namespace App\Services\Catalog;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\ServiceAudience;
use App\Models\Branch;
use App\Models\MasterServiceCategory;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Tenant;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Copies the platform's master service catalog into a tenant's own
 * `service_categories`/`services` rows, once, the first time a tenant gets a
 * branch — the earliest point tenant-owned services can exist at all
 * (`branch_id` is a required column on both tables; see
 * OWNER_APP_ARCHITECTURE.md, "Owner onboarding: salon setup", for why a
 * brand-new tenant has no branch yet either). See
 * MASTER_CATALOG_ARCHITECTURE.md for the full design.
 *
 * This is a one-time COPY, never a live link: after provisioning, a
 * tenant's service is completely independent of the master catalog and of
 * every other tenant — editing Salon A's price/image/Instagram URL can
 * never affect Salon B or the master catalog, and vice versa.
 */
class CatalogProvisioningService
{
    /**
     * Idempotent and tenant-isolated by construction: `Service` is
     * `BelongsToTenant`-scoped, so the "already provisioned?" check only
     * ever sees the calling tenant's own rows (guaranteed by the tenant
     * context already being set — see BranchController::store()). A tenant
     * that already has at least one master-provisioned service (on any
     * branch) is skipped entirely, so provisioning only ever happens once
     * per tenant, no matter how many branches it later creates or how many
     * times this is called.
     *
     * The check-then-insert is wrapped in a single transaction that first
     * takes a `lockForUpdate()` on the tenant's own row — the same pattern
     * `BookingService`/`CouponService` already use for their own
     * check-then-write races (see SECURITY_HARDENING.md, "Cross-tenant
     * relationship attacks" / concurrency fixes). Without this, two
     * `POST /branches` requests for the same brand-new tenant's first two
     * branches arriving concurrently (e.g. two browser tabs) could both
     * pass the "not yet provisioned" check before either had inserted
     * anything, and both proceed to copy the full catalog — a genuine
     * duplicate-provisioning race, not just a sequential-request concern.
     * Locking the tenant row forces the second transaction to wait for the
     * first to commit, at which point its own check correctly sees the
     * catalog already exists and skips.
     */
    public function provisionForBranch(Branch $branch): void
    {
        DB::transaction(function () use ($branch): void {
            Tenant::query()->whereKey($branch->tenant_id)->lockForUpdate()->firstOrFail();

            if (Service::query()->whereNotNull('master_service_id')->exists()) {
                return;
            }

            $masterCategories = MasterServiceCategory::query()
                ->where('is_active', true)
                ->with(['masterServices' => fn ($query) => $query->where('is_active', true)->orderBy('sort_order')])
                ->orderBy('sort_order')
                ->get();

            foreach ($masterCategories as $masterCategory) {
                $category = ServiceCategory::query()->create([
                    'branch_id' => $branch->id,
                    'audience' => $masterCategory->audience,
                    'name' => $masterCategory->name,
                    'slug' => Str::slug($masterCategory->audience->value.' '.$masterCategory->name),
                    'status' => BusinessStatus::ACTIVE,
                    'sort_order' => $masterCategory->sort_order,
                ]);

                foreach ($masterCategory->masterServices as $masterService) {
                    // image/instagram_url are deliberately never set here —
                    // template/default data only (name, description,
                    // duration, a suggested price). A salon's own photo and
                    // Instagram link are always added by the owner
                    // afterward; see ServiceMediaApiTest for that flow.
                    Service::query()->create([
                        'branch_id' => $branch->id,
                        'category_id' => $category->id,
                        'audience' => $masterService->audience,
                        'name' => $masterService->name,
                        'slug' => Str::slug($masterService->audience->value.' '.$masterService->name),
                        'description' => $masterService->description,
                        'gender' => $this->genderFor($masterService->audience),
                        'price' => $masterService->default_price ?? 0,
                        'duration_minutes' => $masterService->default_duration_minutes,
                        'master_service_id' => $masterService->id,
                        'status' => BusinessStatus::ACTIVE,
                        'sort_order' => $masterService->sort_order,
                    ]);
                }
            }
        });
    }

    /**
     * `Service.gender` (the pre-existing `GenderType` field — male/female/
     * unisex only) predates the audience column and has no "kids" value.
     * Kept untouched for backward compatibility (existing filters/reports
     * still work); a Kids-audience service maps to `unisex` there, the
     * closest non-restrictive fit. `audience` (this feature's new column)
     * is the authoritative classification going forward — see
     * MASTER_CATALOG_ARCHITECTURE.md.
     */
    private function genderFor(ServiceAudience $audience): GenderType
    {
        return match ($audience) {
            ServiceAudience::MALE => GenderType::MALE,
            ServiceAudience::FEMALE => GenderType::FEMALE,
            ServiceAudience::UNISEX, ServiceAudience::KIDS => GenderType::UNISEX,
        };
    }
}
