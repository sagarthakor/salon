<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\ServiceCategoryResource;
use App\Http\Resources\ServiceResource;
use App\Models\Branch;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;

/**
 * Read-only service/category catalog for a branch, reachable without tenant
 * membership — the same reviewed pattern as AvailabilityController (resolves
 * the tenant from the branch id, not from a `tenant_user` membership). Without
 * this, a customer has no way to discover which service_ids to pass to the
 * availability/booking APIs at all. See MOBILE_API_INTEGRATION.md.
 */
class CustomerServiceController extends Controller
{
    public function index(string $branch): JsonResponse
    {
        $branchModel = Branch::withoutGlobalScope('tenant')->findOrFail($branch);
        $context = app(TenantContext::class);
        $context->set($branchModel->tenant);
        try {
            $categories = ServiceCategory::query()->where('branch_id', $branchModel->id)->where('status', BusinessStatus::ACTIVE)
                ->orderBy('sort_order')->orderBy('name')->get();
            $services = Service::query()->where('branch_id', $branchModel->id)->where('status', BusinessStatus::ACTIVE)
                ->with('category')->orderBy('sort_order')->orderBy('name')->get();
        } finally {
            $context->clear();
        }

        return ApiResponse::success([
            'categories' => ServiceCategoryResource::collection($categories),
            'services' => ServiceResource::collection($services),
        ], 'Services retrieved.');
    }
}
