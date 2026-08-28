<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Requests\Salon\SalonRequest;
use App\Http\Requests\Salon\SalonSettingsRequest;
use App\Http\Resources\SalonResource;
use App\Http\Resources\SalonSettingsResource;
use App\Models\Branch;
use App\Models\Salon;
use App\Models\SalonSetting;
use App\Services\Catalog\CatalogProvisioningService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class SalonController extends TenantManagementController
{
    public function show(): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new SalonResource(Salon::query()->firstOrFail()), 'Salon retrieved.');
    }

    /**
     * A brand-new tenant's very first Salon also gets a default Branch —
     * and, through it, the master service catalog — provisioned
     * automatically in the same request, atomically. Without this, a
     * self-registered owner who only completes Salon Profile (the actual
     * onboarding flow — see OWNER_APP_ARCHITECTURE.md) never discovers that
     * a Branch is a separate, required step, and is left staring at an
     * empty Services screen (the real-device bug this fixes — see
     * MASTER_CATALOG_ARCHITECTURE.md, "Automatic onboarding provisioning").
     *
     * This can only ever run once per tenant: the `$tenant->salon()->exists()`
     * guard above means `store()` itself is unreachable for a tenant that
     * already has a Salon, so an existing owner's data is never touched —
     * `BranchController::store()`'s own provisioning call (unchanged, still
     * how every subsequent/manual branch is created) simply never fires
     * again for this tenant, per `CatalogProvisioningService`'s own
     * idempotency guard.
     */
    public function store(SalonRequest $request, CatalogProvisioningService $provisioning): JsonResponse
    {
        $tenant = $this->managedTenant();
        if ($tenant->salon()->exists()) {
            return ApiResponse::error('A salon profile already exists for this tenant.', [], 409);
        }
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= BusinessStatus::ACTIVE;

        $salon = DB::transaction(function () use ($data, $provisioning): Salon {
            // `->fresh()` matters here, not just style: `timezone` (and any
            // other column relying on its DB-level default, e.g. when the
            // owner didn't fill it in) is only actually populated by SQL's
            // own DEFAULT during the INSERT — the in-memory model from
            // create() alone would still read back as null for it, which
            // `defaultBranchFor()` would then pass through as an explicit
            // NULL and fail `branches.timezone`'s NOT NULL constraint.
            $salon = Salon::query()->create($data)->fresh();
            $branch = $this->defaultBranchFor($salon);
            $provisioning->provisionForBranch($branch);

            return $salon;
        });

        return ApiResponse::success(new SalonResource($salon), 'Salon created.', 201);
    }

    /**
     * A Branch is a required column on `services`/`service_categories`, so
     * it's the earliest point a tenant can have any — see
     * CatalogProvisioningService. Copies whatever the owner already typed
     * into the Salon form (phone/email/address/timezone) so there's nothing
     * new to fill in; the owner can rename/edit this branch, or add more,
     * exactly like any other, once they reach the dashboard.
     */
    private function defaultBranchFor(Salon $salon): Branch
    {
        return Branch::query()->create([
            'salon_id' => $salon->id,
            'name' => 'Main Branch',
            'slug' => Str::slug('Main Branch'),
            'phone' => $salon->phone,
            'email' => $salon->email,
            'address_line_1' => $salon->address_line_1,
            'city' => $salon->city,
            'timezone' => $salon->timezone,
            'status' => BusinessStatus::ACTIVE,
        ]);
    }

    public function update(SalonRequest $request): JsonResponse
    {
        $this->managedTenant();
        $salon = Salon::query()->firstOrFail();
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= $salon->status;
        $salon->update($data);

        return ApiResponse::success(new SalonResource($salon->fresh()), 'Salon updated.');
    }

    public function settings(): JsonResponse
    {
        $this->managedTenant();
        $salon = Salon::query()->firstOrFail();

        return ApiResponse::success(new SalonSettingsResource($salon->settings()->get()), 'Salon settings retrieved.');
    }

    public function updateSettings(SalonSettingsRequest $request): JsonResponse
    {
        $this->managedTenant();
        $salon = Salon::query()->firstOrFail();
        DB::transaction(function () use ($request, $salon): void {
            foreach ($request->validated('settings') as $key => $value) {
                SalonSetting::query()->updateOrCreate(['salon_id' => $salon->id, 'key' => $key], ['value' => $value]);
            }
        });

        return ApiResponse::success(new SalonSettingsResource($salon->settings()->get()), 'Salon settings updated.');
    }
}
