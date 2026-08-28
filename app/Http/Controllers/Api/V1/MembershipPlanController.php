<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Pricing\MembershipPlanRequest;
use App\Http\Resources\MembershipPlanResource;
use App\Models\MembershipPlan;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Owner/super-admin only — staff never manage membership plans. See
 * "Authorization" in LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class MembershipPlanController extends TenantManagementController
{
    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = MembershipPlan::query();
        if ($request->filled('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }

        return ApiResponse::success(MembershipPlanResource::collection($query->latest()->paginate(min($request->integer('per_page', 20), 100))), 'Membership plans retrieved.');
    }

    public function store(MembershipPlanRequest $request): JsonResponse
    {
        $this->managedTenant();
        $plan = MembershipPlan::query()->create($this->planData($request));
        $this->syncRestrictions($plan, $request);

        return ApiResponse::success(new MembershipPlanResource($plan->load(['services', 'categories'])), 'Membership plan created.', 201);
    }

    public function show(string $membershipPlan): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new MembershipPlanResource($this->plan($membershipPlan)->load(['services', 'categories'])), 'Membership plan retrieved.');
    }

    public function update(MembershipPlanRequest $request, string $membershipPlan): JsonResponse
    {
        $this->managedTenant();
        $model = $this->plan($membershipPlan);
        $model->update($this->planData($request));
        $this->syncRestrictions($model, $request);

        return ApiResponse::success(new MembershipPlanResource($model->fresh()->load(['services', 'categories'])), 'Membership plan updated.');
    }

    public function activate(string $membershipPlan): JsonResponse
    {
        $this->managedTenant();
        $model = $this->plan($membershipPlan);
        $model->update(['is_active' => true]);

        return ApiResponse::success(new MembershipPlanResource($model->fresh()), 'Membership plan activated.');
    }

    public function deactivate(string $membershipPlan): JsonResponse
    {
        $this->managedTenant();
        $model = $this->plan($membershipPlan);
        $model->update(['is_active' => false]);

        return ApiResponse::success(new MembershipPlanResource($model->fresh()), 'Membership plan deactivated.');
    }

    /**
     * Soft-delete only — a plan with historical customer memberships must
     * keep them readable. See "Membership delete policy".
     */
    public function destroy(string $membershipPlan): JsonResponse
    {
        $this->managedTenant();
        $this->plan($membershipPlan)->delete();

        return ApiResponse::success(null, 'Membership plan deleted.');
    }

    private function planData(MembershipPlanRequest $request): array
    {
        $data = $request->validated();
        unset($data['service_ids'], $data['category_ids']);
        $data['currency'] ??= 'INR';

        return $data;
    }

    private function syncRestrictions(MembershipPlan $plan, MembershipPlanRequest $request): void
    {
        $tenantId = $plan->tenant_id;
        if ($request->has('service_ids')) {
            $plan->services()->sync(collect($request->validated('service_ids', []))->mapWithKeys(fn ($id) => [$id => ['tenant_id' => $tenantId]]));
        }
        if ($request->has('category_ids')) {
            $plan->categories()->sync(collect($request->validated('category_ids', []))->mapWithKeys(fn ($id) => [$id => ['tenant_id' => $tenantId]]));
        }
    }

    private function plan(string $id): MembershipPlan
    {
        return MembershipPlan::query()->findOrFail($id);
    }
}
