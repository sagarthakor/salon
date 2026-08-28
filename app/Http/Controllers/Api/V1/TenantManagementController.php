<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Models\Tenant;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\Gate;

abstract class TenantManagementController extends Controller
{
    protected function managedTenant(): Tenant
    {
        $tenant = app(TenantContext::class)->require();
        Gate::authorize('manage', $tenant);

        return $tenant;
    }

    protected function viewableTenant(): Tenant
    {
        $tenant = app(TenantContext::class)->require();
        Gate::authorize('view', $tenant);

        return $tenant;
    }

    /**
     * A brand-new self-registered owner has a Tenant + trial subscription
     * but no Salon profile yet (that's a separate onboarding step — see
     * "Owner onboarding: salon setup" in OWNER_APP_ARCHITECTURE.md). Every
     * owner-management endpoint that needs a Salon to already exist (e.g.
     * BranchController::store() deriving salon_id) must call this instead
     * of `Salon::query()->firstOrFail()` directly: a missing Salon is a
     * real, expected onboarding state, never a 500/raw
     * ModelNotFoundException. `Salon::query()->first()` is already
     * tenant-scoped via `BelongsToTenant` — this can never select another
     * tenant's salon.
     */
    protected function requireSalon(string $action): Salon
    {
        $salon = Salon::query()->first();
        if ($salon === null) {
            throw new HttpResponseException(ApiResponse::error(
                "Please set up your salon profile before {$action}.",
                ['salon' => ['Salon profile not found.']],
                422,
            ));
        }

        return $salon;
    }
}
