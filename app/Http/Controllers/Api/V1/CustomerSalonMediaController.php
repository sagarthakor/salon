<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\SalonMediaCategory;
use App\Http\Controllers\Controller;
use App\Http\Resources\CustomerSalonMediaResource;
use App\Models\Branch;
use App\Models\SalonMedia;
use App\Support\ApiResponse;
use App\Support\BrandAppGuard;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Read-only public gallery for a branch — same reviewed pattern as
 * CustomerServiceController (tenant resolved from the branch id, BrandAppGuard
 * enforced). Only active items that are salon-wide or belong to this branch.
 */
class CustomerSalonMediaController extends Controller
{
    public function index(string $branch, Request $request): JsonResponse
    {
        $branchModel = Branch::withoutGlobalScope('tenant')->findOrFail($branch);
        app(BrandAppGuard::class)->assertTenant($request, $branchModel->tenant_id);
        $category = $request->filled('category') ? SalonMediaCategory::tryFrom($request->string('category')->toString()) : null;
        if ($request->filled('category') && $category === null) {
            return ApiResponse::error('Invalid category.', ['category' => ['The selected category is invalid.']], 422);
        }

        $context = app(TenantContext::class);
        $context->set($branchModel->tenant);
        try {
            $query = SalonMedia::query()->with('service')
                ->where('is_active', true)
                ->where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branchModel->id));
            if ($category !== null) {
                $query->where('category', $category->value);
            }
            SalonMediaController::ordered($query);
            $page = $query->paginate(min($request->integer('per_page', 12), 50));
        } finally {
            $context->clear();
        }

        return ApiResponse::success(CustomerSalonMediaResource::collection($page), 'Gallery retrieved.');
    }
}
