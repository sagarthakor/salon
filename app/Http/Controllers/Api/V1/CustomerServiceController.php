<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Enums\ServiceAudience;
use App\Http\Controllers\Controller;
use App\Http\Resources\ServiceCategoryResource;
use App\Http\Resources\ServiceResource;
use App\Models\Branch;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Support\ApiResponse;
use App\Support\BrandAppGuard;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Read-only service/category catalog for a branch, reachable without tenant
 * membership — the same reviewed pattern as AvailabilityController (resolves
 * the tenant from the branch id, not from a `tenant_user` membership). Without
 * this, a customer has no way to discover which service_ids to pass to the
 * availability/booking APIs at all. See MOBILE_API_INTEGRATION.md.
 */
class CustomerServiceController extends Controller
{
    /**
     * `audience` (optional) is the customer app's "Men / Women / Unisex /
     * Kids" entry point (see MASTER_CATALOG_ARCHITECTURE.md) — an exact
     * match only. Selecting Unisex never also pulls in Male/Female
     * services, and vice versa: a service belongs to exactly one audience,
     * never silently duplicated across several.
     */
    public function index(string $branch, Request $request): JsonResponse
    {
        $branchModel = Branch::withoutGlobalScope('tenant')->findOrFail($branch);
        app(BrandAppGuard::class)->assertTenant($request, $branchModel->tenant_id);
        $audience = $request->filled('audience') ? ServiceAudience::tryFrom($request->string('audience')->toString()) : null;
        if ($request->filled('audience') && $audience === null) {
            return ApiResponse::error('Invalid audience.', ['audience' => ['The selected audience is invalid.']], 422);
        }
        $context = app(TenantContext::class);
        $context->set($branchModel->tenant);
        try {
            $categoriesQuery = ServiceCategory::query()->where('branch_id', $branchModel->id)->where('status', BusinessStatus::ACTIVE);
            $servicesQuery = Service::query()->where('branch_id', $branchModel->id)->where('status', BusinessStatus::ACTIVE);
            if ($audience !== null) {
                $categoriesQuery->where('audience', $audience);
                $servicesQuery->where('audience', $audience);
            }
            $categories = $categoriesQuery->orderBy('sort_order')->orderBy('name')->get();
            $services = $servicesQuery->with('category')->orderBy('sort_order')->orderBy('name')->get();
        } finally {
            $context->clear();
        }

        return ApiResponse::success([
            'categories' => ServiceCategoryResource::collection($categories),
            'services' => ServiceResource::collection($services),
        ], 'Services retrieved.');
    }
}
