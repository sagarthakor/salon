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
 * `index()` lists the salons the authenticated customer already has a
 * relationship with (i.e. tenants where a customer_profiles row links to
 * this user) — kept for existing callers/tests, unchanged.
 *
 * `discover()`/`branches()` are the public/customer salon directory: cross-
 * tenant by design, filtered only by `Salon`/`Branch` status, never by
 * customer_profiles membership — a brand-new customer must be able to find
 * and book a salon without a staff member registering them first. See
 * CUSTOMER_ARCHITECTURE.md, "Customer discovery and first-time booking",
 * and MOBILE_API_INTEGRATION.md.
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

    /**
     * Public/customer salon directory — deliberately cross-tenant and
     * independent of `index()` above: a brand-new customer with zero
     * `customer_profiles` rows anywhere must still be able to browse and
     * pick a salon. Never filtered by membership. Every other field this
     * exposes via `SalonResource` is already customer-safe (no owner/admin/
     * billing/staff data) — the same resource `index()` already returns to
     * customers. See CUSTOMER_ARCHITECTURE.md, "Customer discovery and
     * first-time booking".
     */
    public function discover(): JsonResponse
    {
        $salons = Salon::withoutGlobalScope('tenant')->where('status', BusinessStatus::ACTIVE)->orderBy('name')->get();

        return ApiResponse::success(SalonResource::collection($salons), 'Salons retrieved.');
    }

    /**
     * Active branches for a salon the customer picked from `discover()`.
     * The salon (and therefore its tenant) is resolved entirely server-side
     * from `$salon` — never from a client-supplied tenant id — and
     * `salons.tenant_id`/`salons.slug` are both globally unique (see the
     * `create_salon_management_tables` migration), so this can never leak
     * another tenant's branches. Reachable without `X-Tenant-Slug` and
     * without any customer_profiles row, same as `discover()`.
     */
    public function branches(string $salon): JsonResponse
    {
        $salonModel = Salon::withoutGlobalScope('tenant')->where('status', BusinessStatus::ACTIVE)->findOrFail($salon);
        $context = app(TenantContext::class);
        $context->set($salonModel->tenant);
        try {
            $branches = Branch::query()->where('salon_id', $salonModel->id)->where('status', BusinessStatus::ACTIVE)->orderBy('name')->get();
        } finally {
            $context->clear();
        }

        return ApiResponse::success(BranchResource::collection($branches), 'Branches retrieved.');
    }

    /**
     * Resolves the single salon for a branded, single-tenant Flutter app
     * (see `config/brand_apps.php`) from the tenant id baked into that
     * build — the same public/cross-tenant pattern as `discover()`, just
     * keyed by tenant id instead of returning every active salon. This is
     * how a branded app turns "tenant id baked into the build" into the
     * `salon_id` it feeds into the existing, unchanged
     * `GET /customer/salons/{salon}/branches` → booking flow, without ever
     * needing a hardcoded salon/branch id. `salons.tenant_id` is globally
     * unique (see the `create_salon_management_tables` migration), so this
     * can never resolve more than one salon.
     */
    public function byTenant(string $tenant): JsonResponse
    {
        $salon = Salon::withoutGlobalScope('tenant')->where('tenant_id', $tenant)->where('status', BusinessStatus::ACTIVE)->firstOrFail();

        return ApiResponse::success(new SalonResource($salon), 'Salon retrieved.');
    }
}
