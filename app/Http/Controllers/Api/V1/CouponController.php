<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Pricing\CouponRequest;
use App\Http\Resources\CouponResource;
use App\Models\Coupon;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Owner/super-admin only for every action — see "Authorization" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md: staff never manage coupons.
 */
class CouponController extends TenantManagementController
{
    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = Coupon::query();
        if ($request->filled('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }
        if ($request->filled('search')) {
            $query->where(fn ($q) => $q->where('code', 'like', '%'.$request->string('search').'%')->orWhere('name', 'like', '%'.$request->string('search').'%'));
        }

        return ApiResponse::success(CouponResource::collection($query->latest()->paginate(min($request->integer('per_page', 20), 100))), 'Coupons retrieved.');
    }

    public function store(CouponRequest $request): JsonResponse
    {
        $this->managedTenant();
        $coupon = Coupon::query()->create($this->couponData($request));
        $this->syncRestrictions($coupon, $request);

        return ApiResponse::success(new CouponResource($coupon->load(['services', 'categories'])), 'Coupon created.', 201);
    }

    public function show(string $coupon): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new CouponResource($this->coupon($coupon)->load(['services', 'categories'])), 'Coupon retrieved.');
    }

    public function update(CouponRequest $request, string $coupon): JsonResponse
    {
        $this->managedTenant();
        $model = $this->coupon($coupon);
        $model->update($this->couponData($request));
        $this->syncRestrictions($model, $request);

        return ApiResponse::success(new CouponResource($model->fresh()->load(['services', 'categories'])), 'Coupon updated.');
    }

    public function activate(string $coupon): JsonResponse
    {
        $this->managedTenant();
        $model = $this->coupon($coupon);
        $model->update(['is_active' => true]);

        return ApiResponse::success(new CouponResource($model->fresh()), 'Coupon activated.');
    }

    public function deactivate(string $coupon): JsonResponse
    {
        $this->managedTenant();
        $model = $this->coupon($coupon);
        $model->update(['is_active' => false]);

        return ApiResponse::success(new CouponResource($model->fresh()), 'Coupon deactivated.');
    }

    /**
     * Soft-deletes only — a used coupon's historical bookings/usages must
     * keep their coupon reference readable (see "Coupon delete policy").
     * Deactivating rather than deleting is the recommended action for a
     * coupon that has ever been used; delete remains available for a
     * never-used coupon created by mistake.
     */
    public function destroy(string $coupon): JsonResponse
    {
        $this->managedTenant();
        $this->coupon($coupon)->delete();

        return ApiResponse::success(null, 'Coupon deleted.');
    }

    private function couponData(CouponRequest $request): array
    {
        $data = $request->validated();
        $data['code'] = Coupon::normalizeCode($data['code']);
        unset($data['service_ids'], $data['category_ids']);

        return $data;
    }

    private function syncRestrictions(Coupon $coupon, CouponRequest $request): void
    {
        $tenantId = $coupon->tenant_id;
        if ($request->has('service_ids')) {
            $coupon->services()->sync(collect($request->validated('service_ids', []))->mapWithKeys(fn ($id) => [$id => ['tenant_id' => $tenantId]]));
        }
        if ($request->has('category_ids')) {
            $coupon->categories()->sync(collect($request->validated('category_ids', []))->mapWithKeys(fn ($id) => [$id => ['tenant_id' => $tenantId]]));
        }
    }

    private function coupon(string $id): Coupon
    {
        return Coupon::query()->findOrFail($id);
    }
}
