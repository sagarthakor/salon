<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\BranchResource;
use App\Http\Resources\SalonResource;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\Salon;
use App\Models\Tenant;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Lists the salons the authenticated customer already has a relationship with
 * (i.e. tenants where a customer_profiles row links to this user). This is
 * deliberately not a public salon directory/search — the customer must already
 * be a registered customer of a salon (created by staff, per Phase 5) for it to
 * appear here. See CUSTOMER_ARCHITECTURE.md and MOBILE_API_INTEGRATION.md.
 */
class CustomerSalonController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $tenantIds = Customer::withoutGlobalScope('tenant')->where('user_id', $request->user()->id)->pluck('tenant_id')->unique()->values();
        $tenants = Tenant::query()->whereIn('id', $tenantIds)->orderBy('name')->get();
        $context = app(TenantContext::class);

        $result = $tenants->map(function (Tenant $tenant) use ($context): array {
            $context->set($tenant);
            $salon = Salon::query()->first();
            $branches = Branch::query()->where('status', BusinessStatus::ACTIVE)->orderBy('name')->get();
            $context->clear();

            return [
                'tenant_slug' => $tenant->slug,
                'salon' => $salon ? new SalonResource($salon) : null,
                'branches' => BranchResource::collection($branches),
            ];
        })->values();

        return ApiResponse::success($result, 'Salons retrieved.');
    }
}
